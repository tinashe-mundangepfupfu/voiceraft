import Foundation
import OSLog
import Speech
import VoiceRaftCore

actor NativeMeetingProcessor {
    private let maxRevisions = 2
    private let logger = Logger(subsystem: "com.voiceraft.app", category: "processing")
    private let secretStore: any ClaudeSecretStoring

    init(secretStore: any ClaudeSecretStoring = KeychainSecretStore()) {
        self.secretStore = secretStore
    }

    func processMeeting(
        session: MeetingSession,
        audioURL: URL,
        diagnostics: RecordedAudioDiagnostics,
        settings: AppSettings,
        endedAt: Date
    ) async throws -> WorkflowResponsePayload {
        logger.info(
            "process meeting started title=\(session.title, privacy: .public) path=\(audioURL.path, privacy: .public) bytes=\(diagnostics.byteCount) duration=\(diagnostics.durationSeconds, privacy: .public)"
        )
        let request = buildRequestPayload(session: session, audioURL: audioURL, endedAt: endedAt)
        let transcript = try await transcribe(audioURL: audioURL, language: request.language, diagnostics: diagnostics)
        logger.info("transcription complete characters=\(transcript.count)")

        do {
            let client = try await makeClient(settings: settings)

            var draft = try await client.draft(transcript: transcript, request: request)
            var decision = try await client.judge(transcript: transcript, draft: draft)
            var revisionCount = 0

            while !decision.approved && revisionCount < maxRevisions {
                draft = try await client.revise(draft: draft, feedback: decision.feedback, request: request)
                revisionCount += 1
                decision = try await client.judge(transcript: transcript, draft: draft)
            }

            return makeWorkflowResponsePayload(
                draft: draft,
                decision: decision,
                revisionCount: revisionCount
            )
        } catch {
            throw mapWorkflowError(error)
        }
    }

    private func buildRequestPayload(session: MeetingSession, audioURL: URL, endedAt: Date) -> MeetingWorkflowRequest {
        MeetingWorkflowRequest(
            sessionID: session.id,
            audioURL: audioURL,
            meetingTitle: session.title,
            meetingMode: session.mode.rawValue,
            language: "en",
            startedAt: session.startedAt.voiceraftISO8601String(),
            endedAt: endedAt.voiceraftISO8601String()
        )
    }

    private func transcribe(audioURL: URL, language: String, diagnostics: RecordedAudioDiagnostics) async throws -> String {
        if let message = RecordingTranscriptionDiagnostics.preflightFailureMessage(for: diagnostics) {
            logger.error("transcription preflight failed message=\(message, privacy: .public)")
            throw VoiceRaftError.transcriptionFailed(message)
        }

        try await authorizeSpeechRecognition()
        logger.info("speech recognition authorized locale=\(language, privacy: .public)")

        let locale = Locale(identifier: language)
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw VoiceRaftError.transcriptionFailed("Speech recognition is unavailable for locale \(locale.identifier).")
        }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition

        return try await withCheckedThrowingContinuation { continuation in
            var completed = false
            recognizer.recognitionTask(with: request) { result, error in
                if completed {
                    return
                }

                if let error {
                    completed = true
                    self.logger.error("speech recognition failed error=\(error.localizedDescription, privacy: .public)")
                    continuation.resume(throwing: VoiceRaftError.transcriptionFailed(error.localizedDescription))
                    return
                }

                guard let result, result.isFinal else {
                    return
                }

                let normalized = self.normalizeTranscript(result.bestTranscription.formattedString)
                completed = true
                if normalized.isEmpty {
                    self.logger.error("speech recognition produced empty transcript")
                    continuation.resume(
                        throwing: VoiceRaftError.transcriptionFailed(
                            RecordingTranscriptionDiagnostics.failureMessage(for: diagnostics)
                        )
                    )
                } else {
                    self.logger.info("speech recognition final transcript characters=\(normalized.count)")
                    continuation.resume(returning: normalized)
                }
            }
        }
    }

    private func authorizeSpeechRecognition() async throws {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return
        case .notDetermined:
            let status = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status)
                }
            }
            guard status == .authorized else {
                throw VoiceRaftError.speechRecognitionPermissionDenied
            }
        default:
            throw VoiceRaftError.speechRecognitionPermissionDenied
        }
    }

    private func normalizeTranscript(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func makeClient(settings: AppSettings) async throws -> any MeetingNotesModeling {
        switch settings.notesProvider {
        case .lmStudio:
            guard let baseURL = URL(string: settings.lmStudioBaseURL) else {
                throw VoiceRaftError.invalidLMStudioBaseURL
            }
            return LMStudioClient(
                configuration: LMStudioConfiguration(
                    baseURL: baseURL,
                    model: settings.lmStudioModel
                )
            )

        case .claude:
            let apiKey = try loadClaudeAPIKey()
            let model = settings.claudeModel.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !model.isEmpty else {
                throw VoiceRaftError.invalidClaudeModel("No Claude model selected")
            }

            let availableModels: [String]
            do {
                availableModels = try await AnthropicModelsService(apiKey: apiKey).listModels()
            } catch {
                throw mapModelDiscoveryError(error)
            }

            guard availableModels.contains(model) else {
                throw VoiceRaftError.invalidClaudeModel(model)
            }

            return ClaudeClient(
                configuration: ClaudeConfiguration(
                    model: model,
                    apiKey: apiKey
                )
            )
        }
    }

    private func loadClaudeAPIKey() throws -> String {
        do {
            guard
                let apiKey = try secretStore.loadAnthropicAPIKey()?.trimmingCharacters(in: .whitespacesAndNewlines),
                !apiKey.isEmpty
            else {
                throw VoiceRaftError.missingClaudeAPIKey
            }

            return apiKey
        } catch let error as VoiceRaftError {
            throw error
        } catch {
            throw VoiceRaftError.claudeAPIKeyAccessFailed(error.localizedDescription)
        }
    }

    private func mapModelDiscoveryError(_ error: Error) -> VoiceRaftError {
        if let voiceRaftError = error as? VoiceRaftError {
            return voiceRaftError
        }

        if let coreError = error as? VoiceRaftCoreError {
            switch coreError {
            case .anthropicModelDiscoveryTimedOut:
                return .claudeModelFetchFailed("Anthropic timed out before it returned the Claude model list.")
            default:
                return .claudeModelFetchFailed(coreError.localizedDescription)
            }
        }

        return .claudeModelFetchFailed(error.localizedDescription)
    }

    private func mapWorkflowError(_ error: Error) -> VoiceRaftError {
        if let voiceRaftError = error as? VoiceRaftError {
            return voiceRaftError
        }

        guard let coreError = error as? VoiceRaftCoreError else {
            return .processingProviderFailure(error.localizedDescription)
        }

        switch coreError {
        case let .invalidLMStudioResponse(message):
            return .lmStudioRequestFailed(message)
        case let .lmStudioRequestFailed(statusCode, body):
            return .lmStudioRequestFailed("LM Studio returned HTTP \(statusCode). \(body)")
        case let .invalidAnthropicResponse(message):
            return .processingProviderFailure(message)
        case let .anthropicRequestFailed(statusCode, body):
            return .processingProviderFailure("Anthropic returned HTTP \(statusCode). \(body)")
        case .anthropicRequestTimedOut:
            return .processingProviderFailure("Anthropic timed out before it returned a response.")
        case .anthropicModelDiscoveryTimedOut:
            return .claudeModelFetchFailed("Anthropic timed out before it returned the Claude model list.")
        case .emptyTranscript:
            return .transcriptionFailed("Speech transcription produced no usable text.")
        case .speechRecognitionPermissionDenied:
            return .speechRecognitionPermissionDenied
        case let .speechTranscriptionUnavailable(message):
            return .transcriptionFailed(message)
        case let .transcriptionFailed(message):
            return .transcriptionFailed(message)
        }
    }

    private func makeWorkflowResponsePayload(
        draft: DraftNote,
        decision: JudgeDecision,
        revisionCount: Int
    ) -> WorkflowResponsePayload {
        let status: MeetingWorkflowStatus = decision.approved ? .final : .needsReview
        let frontmatter = Frontmatter(
            title: draft.frontmatter.title,
            date: draft.frontmatter.date,
            meetingMode: draft.frontmatter.meetingMode,
            language: draft.frontmatter.language,
            status: status,
            tags: draft.frontmatter.tags
        )
        let result = MeetingWorkflowResult(
            status: status,
            confidence: decision.confidence,
            judgeSummary: decision.feedback.reason,
            frontmatter: frontmatter,
            sections: draft.sections,
            markdown: "",
            revisionCount: revisionCount
        )

        return WorkflowResponsePayload(
            status: result.status.rawValue,
            confidence: result.confidence,
            judgeSummary: result.judgeSummary,
            frontmatter: WorkflowResponsePayload.Frontmatter(
                title: result.frontmatter.title,
                date: result.frontmatter.date,
                meetingMode: result.frontmatter.meetingMode,
                language: result.frontmatter.language,
                status: result.status.rawValue,
                tags: result.frontmatter.tags
            ),
            sections: WorkflowResponsePayload.Sections(
                summary: result.sections.summary,
                keyDiscussionPoints: result.sections.keyDiscussionPoints,
                decisions: result.sections.decisions,
                actionItems: result.sections.actionItems.map {
                    WorkflowResponsePayload.ActionItem(task: $0.task, owner: $0.owner, due: $0.due)
                },
                openQuestionsOrRisks: result.sections.openQuestionsOrRisks,
                followUp: result.sections.followUp
            ),
            markdown: MarkdownRenderer().render(result: result)
        )
    }
}
