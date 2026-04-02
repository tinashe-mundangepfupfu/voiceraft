import Foundation
import OSLog
import Speech

actor NativeMeetingProcessor {
    private let maxRevisions = 2
    private let logger = Logger(subsystem: "com.voiceraft.app", category: "processing")

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
        let client = try makeClient(settings: settings)

        var draft = try await client.draft(transcript: transcript, request: request)
        var decision = try await client.judge(transcript: transcript, draft: draft)
        var revisionCount = 0

        while !decision.approved && revisionCount < maxRevisions {
            draft = try await client.revise(draft: draft, feedback: decision.feedback, request: request)
            revisionCount += 1
            decision = try await client.judge(transcript: transcript, draft: draft)
        }

        let status = decision.approved ? "final" : "needs-review"
        let frontmatter = WorkflowResponsePayload.Frontmatter(
            title: draft.frontmatter.title,
            date: draft.frontmatter.date,
            meetingMode: draft.frontmatter.meetingMode,
            language: draft.frontmatter.language,
            status: status,
            tags: draft.frontmatter.tags
        )
        let result = WorkflowResponsePayload(
            status: status,
            confidence: decision.confidence,
            judgeSummary: decision.feedback.reason,
            frontmatter: frontmatter,
            sections: draft.sections,
            markdown: ""
        )

        return WorkflowResponsePayload(
            status: result.status,
            confidence: result.confidence,
            judgeSummary: result.judgeSummary,
            frontmatter: result.frontmatter,
            sections: result.sections,
            markdown: buildMarkdown(result: result)
        )
    }

    private func buildRequestPayload(session: MeetingSession, audioURL: URL, endedAt: Date) -> ProcessingRequestPayload {
        ProcessingRequestPayload(
            sessionID: session.id,
            audioPath: audioURL.path,
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

    private func makeClient(settings: AppSettings) throws -> LMStudioMeetingClient {
        guard let baseURL = URL(string: settings.lmStudioBaseURL) else {
            throw VoiceRaftError.invalidLMStudioBaseURL
        }
        return LMStudioMeetingClient(baseURL: baseURL, model: settings.lmStudioModel)
    }

    private func buildMarkdown(result: WorkflowResponsePayload) -> String {
        let tags = result.frontmatter.tags.joined(separator: ", ")
        var lines = [
            "---",
            "title: \(result.frontmatter.title)",
            "date: \(result.frontmatter.date)",
            "meeting_mode: \(result.frontmatter.meetingMode)",
            "language: \(result.frontmatter.language)",
            "status: \(result.frontmatter.status)",
            "tags: [\(tags)]",
            "---",
            "",
        ]

        if result.status == "needs-review" {
            lines.append("> Review recommended: \(result.judgeSummary)")
            lines.append("")
        }

        lines.append(contentsOf: [
            "## Summary",
            result.sections.summary,
            "",
            "## Key Discussion Points",
        ])
        lines.append(contentsOf: renderBullets(result.sections.keyDiscussionPoints))
        lines.append(contentsOf: [
            "",
            "## Decisions",
        ])
        lines.append(contentsOf: renderBullets(result.sections.decisions))
        lines.append(contentsOf: [
            "",
            "## Action Items",
        ])
        lines.append(contentsOf: renderActionItems(result.sections.actionItems))
        lines.append(contentsOf: [
            "",
            "## Open Questions / Risks",
        ])
        lines.append(contentsOf: renderBullets(result.sections.openQuestionsOrRisks))
        lines.append(contentsOf: [
            "",
            "## Follow-Up",
        ])
        lines.append(contentsOf: renderBullets(result.sections.followUp))
        return lines.joined(separator: "\n")
    }

    private func renderBullets(_ items: [String]) -> [String] {
        if items.isEmpty {
            return ["- None"]
        }
        return items.map { "- \($0)" }
    }

    private func renderActionItems(_ items: [WorkflowResponsePayload.ActionItem]) -> [String] {
        if items.isEmpty {
            return ["- None"]
        }
        return items.map { item in
            var parts = ["Owner: \(item.owner ?? "Unassigned")"]
            if let due = item.due {
                parts.append("Due: \(due)")
            }
            return "- \(item.task) (\(parts.joined(separator: ", ")))"
        }
    }
}

private struct DraftNote {
    let frontmatter: WorkflowResponsePayload.Frontmatter
    let sections: WorkflowResponsePayload.Sections
}

private struct JudgeFeedback {
    let reason: String
    let missingRequirements: [String]
}

private struct JudgeDecision {
    let approved: Bool
    let confidence: Double
    let feedback: JudgeFeedback
}

private struct LMStudioMeetingClient {
    private static let requestTimeoutSeconds: TimeInterval = 300
    let baseURL: URL
    let model: String

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func draft(transcript: String, request: ProcessingRequestPayload) async throws -> DraftNote {
        let output: DraftOutput = try await complete(
            systemPrompt: """
            You write informative, professional meeting minutes.
            Only use information grounded in the transcript.
            Keep decisions separate from open questions.
            Only assign an owner when explicitly stated or strongly inferable.
            Respond with one JSON object and no extra text.
            """,
            userPrompt: """
            Meeting title: \(request.meetingTitle)
            Meeting mode: \(request.meetingMode)
            Language: \(request.language)
            Transcript:
            \(transcript)
            """,
            responseFormat: .meetingNote
        )
        return draftNote(from: output, request: request)
    }

    func judge(transcript: String, draft: DraftNote) async throws -> JudgeDecision {
        let output: JudgeOutput = try await complete(
            systemPrompt: """
            Judge the meeting note against this rubric:
            1) no unsupported claims,
            2) decisions and open questions are clearly separated,
            3) action items include owners only when explicit or strongly inferable,
            4) tone is professional and concise,
            5) uncertainty is labeled rather than guessed.
            Approve only when the note is safe to auto-save.
            Respond with one JSON object and no extra text.
            """,
            userPrompt: """
            Transcript:
            \(transcript)

            Candidate note:
            \(encodeDraftPayload(draft))
            """,
            responseFormat: .judgeDecision
        )
        return JudgeDecision(
            approved: output.approved,
            confidence: output.confidence,
            feedback: JudgeFeedback(
                reason: output.reason,
                missingRequirements: output.missingRequirements
            )
        )
    }

    func revise(draft: DraftNote, feedback: JudgeFeedback, request: ProcessingRequestPayload) async throws -> DraftNote {
        let output: DraftOutput = try await complete(
            systemPrompt: """
            Revise the meeting note so it passes the review rubric.
            Do not invent facts.
            Keep tone professional and concise.
            Respond with one JSON object and no extra text.
            """,
            userPrompt: """
            Meeting title: \(request.meetingTitle)
            Meeting mode: \(request.meetingMode)
            Language: \(request.language)
            Existing note draft:
            \(encodeDraftPayload(draft))
            Judge feedback:
            \(encodeJudgeFeedback(feedback))
            """,
            responseFormat: .meetingNote
        )
        return draftNote(from: output, request: request)
    }

    private func complete<Response: Decodable>(
        systemPrompt: String,
        userPrompt: String,
        responseFormat: ResponseFormat
    ) async throws -> Response {
        let url = baseURL.appending(path: "chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = Self.requestTimeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer lm-studio", forHTTPHeaderField: "Authorization")
        request.httpBody = try encoder.encode(
            ChatCompletionsRequest(
                model: model,
                temperature: 0,
                responseFormat: responseFormat,
                messages: [
                    ChatMessage(role: "system", content: systemPrompt),
                    ChatMessage(role: "user", content: userPrompt),
                ]
            )
        )

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw VoiceRaftError.lmStudioRequestFailed(
                "LM Studio timed out before it returned a response. Try a smaller model or increase the local server timeout."
            )
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw VoiceRaftError.lmStudioRequestFailed("LM Studio returned a non-HTTP response.")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw VoiceRaftError.lmStudioRequestFailed(body)
        }

        let envelope = try decoder.decode(ChatCompletionsResponse.self, from: data)
        guard
            let content = envelope.choices.first?.message.content,
            let json = extractJSONObject(from: content),
            let jsonData = json.data(using: .utf8)
        else {
            throw VoiceRaftError.lmStudioRequestFailed("LM Studio did not return valid JSON content.")
        }

        do {
            return try decoder.decode(Response.self, from: jsonData)
        } catch {
            throw VoiceRaftError.lmStudioRequestFailed("LM Studio returned malformed structured output.")
        }
    }

    private func draftNote(from output: DraftOutput, request: ProcessingRequestPayload) -> DraftNote {
        DraftNote(
            frontmatter: WorkflowResponsePayload.Frontmatter(
                title: request.meetingTitle,
                date: request.startedAt,
                meetingMode: request.meetingMode,
                language: request.language,
                status: "final",
                tags: ["meeting", request.meetingMode]
            ),
            sections: WorkflowResponsePayload.Sections(
                summary: output.summary,
                keyDiscussionPoints: output.keyDiscussionPoints,
                decisions: output.decisions,
                actionItems: output.actionItems.map {
                    WorkflowResponsePayload.ActionItem(task: $0.task, owner: $0.owner, due: $0.due)
                },
                openQuestionsOrRisks: output.openQuestionsOrRisks,
                followUp: output.followUp
            )
        )
    }

    private func encodeDraftPayload(_ draft: DraftNote) -> String {
        let payload = DraftOutput(
            summary: draft.sections.summary,
            keyDiscussionPoints: draft.sections.keyDiscussionPoints,
            decisions: draft.sections.decisions,
            actionItems: draft.sections.actionItems.map {
                ActionItemOutput(task: $0.task, owner: $0.owner, due: $0.due)
            },
            openQuestionsOrRisks: draft.sections.openQuestionsOrRisks,
            followUp: draft.sections.followUp
        )
        return encodeJSON(payload)
    }

    private func encodeJudgeFeedback(_ feedback: JudgeFeedback) -> String {
        encodeJSON(
            JudgeFeedbackOutput(
                reason: feedback.reason,
                missingRequirements: feedback.missingRequirements
            )
        )
    }

    private func encodeJSON<T: Encodable>(_ value: T) -> String {
        guard
            let data = try? encoder.encode(value),
            let string = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return string
    }

    private func extractJSONObject(from content: String) -> String? {
        let cleaned = content
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.first == "{", cleaned.last == "}" {
            return cleaned
        }

        guard let start = cleaned.firstIndex(of: "{"), let end = cleaned.lastIndex(of: "}") else {
            return nil
        }
        return String(cleaned[start...end])
    }
}

private struct ChatCompletionsRequest: Encodable {
    let model: String
    let temperature: Double
    let responseFormat: ResponseFormat
    let messages: [ChatMessage]

    enum CodingKeys: String, CodingKey {
        case model
        case temperature
        case responseFormat = "response_format"
        case messages
    }
}

private struct ChatMessage: Encodable {
    let role: String
    let content: String
}

private struct ChatCompletionsResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }

        let message: Message
    }

    let choices: [Choice]
}

private struct ResponseFormat: Encodable, Sendable {
    let type = "json_schema"
    let jsonSchema: JSONSchemaEnvelope

    enum CodingKeys: String, CodingKey {
        case type
        case jsonSchema = "json_schema"
    }

    static let meetingNote = ResponseFormat(
        jsonSchema: JSONSchemaEnvelope(
            name: "meeting_note",
            strict: true,
            schema: .meetingNote
        )
    )

    static let judgeDecision = ResponseFormat(
        jsonSchema: JSONSchemaEnvelope(
            name: "judge_decision",
            strict: true,
            schema: .judgeDecision
        )
    )
}

private struct JSONSchemaEnvelope: Encodable, Sendable {
    let name: String
    let strict: Bool
    let schema: JSONSchema
}

private struct JSONSchema: Encodable, Sendable {
    let type = "object"
    let properties: [String: SchemaProperty]
    let required: [String]
    let additionalProperties = false

    static let meetingNote = JSONSchema(
        properties: [
            "summary": .string,
            "key_discussion_points": .stringArray,
            "decisions": .stringArray,
            "action_items": .actionItemArray,
            "open_questions_or_risks": .stringArray,
            "follow_up": .stringArray,
        ],
        required: [
            "summary",
            "key_discussion_points",
            "decisions",
            "action_items",
            "open_questions_or_risks",
            "follow_up",
        ]
    )

    static let judgeDecision = JSONSchema(
        properties: [
            "approved": .boolean,
            "confidence": .number,
            "reason": .string,
            "missing_requirements": .stringArray,
        ],
        required: [
            "approved",
            "confidence",
            "reason",
            "missing_requirements",
        ]
    )
}

private final class SchemaProperty: Encodable, @unchecked Sendable {
    let type: String?
    let unionType: [String]?
    let items: SchemaProperty?
    let properties: [String: SchemaProperty]?
    let required: [String]?
    let additionalProperties: Bool?

    static let string = SchemaProperty(type: "string")
    static let number = SchemaProperty(type: "number")
    static let boolean = SchemaProperty(type: "boolean")
    static let stringArray = SchemaProperty(type: "array", items: .string)
    static let actionItemArray = SchemaProperty(
        type: "array",
        items: SchemaProperty(
            type: "object",
            properties: [
                "task": .string,
                "owner": SchemaProperty(type: ["string", "null"]),
                "due": SchemaProperty(type: ["string", "null"]),
            ],
            required: ["task", "owner", "due"],
            additionalProperties: false
        )
    )

    init(
        type: String? = nil,
        items: SchemaProperty? = nil,
        properties: [String: SchemaProperty]? = nil,
        required: [String]? = nil,
        additionalProperties: Bool? = nil
    ) {
        self.type = type
        self.unionType = nil
        self.items = items
        self.properties = properties
        self.required = required
        self.additionalProperties = additionalProperties
    }

    init(
        type: [String],
        items: SchemaProperty? = nil,
        properties: [String: SchemaProperty]? = nil,
        required: [String]? = nil,
        additionalProperties: Bool? = nil
    ) {
        self.type = nil
        self.unionType = type
        self.items = items
        self.properties = properties
        self.required = required
        self.additionalProperties = additionalProperties
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)
        if let type {
            try container.encode(type, forKey: DynamicCodingKey("type"))
        } else if let unionType {
            try container.encode(unionType, forKey: DynamicCodingKey("type"))
        }
        try container.encodeIfPresent(items, forKey: DynamicCodingKey("items"))
        try container.encodeIfPresent(properties, forKey: DynamicCodingKey("properties"))
        try container.encodeIfPresent(required, forKey: DynamicCodingKey("required"))
        try container.encodeIfPresent(additionalProperties, forKey: DynamicCodingKey("additionalProperties"))
    }
}

private struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init(_ stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(stringValue: String) {
        self.init(stringValue)
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

private struct ActionItemOutput: Codable {
    let task: String
    let owner: String?
    let due: String?
}

private struct DraftOutput: Codable {
    let summary: String
    let keyDiscussionPoints: [String]
    let decisions: [String]
    let actionItems: [ActionItemOutput]
    let openQuestionsOrRisks: [String]
    let followUp: [String]

    enum CodingKeys: String, CodingKey {
        case summary
        case keyDiscussionPoints = "key_discussion_points"
        case decisions
        case actionItems = "action_items"
        case openQuestionsOrRisks = "open_questions_or_risks"
        case followUp = "follow_up"
    }
}

private struct JudgeOutput: Codable {
    let approved: Bool
    let confidence: Double
    let reason: String
    let missingRequirements: [String]

    enum CodingKeys: String, CodingKey {
        case approved
        case confidence
        case reason
        case missingRequirements = "missing_requirements"
    }
}

private struct JudgeFeedbackOutput: Codable {
    let reason: String
    let missingRequirements: [String]

    enum CodingKeys: String, CodingKey {
        case reason
        case missingRequirements = "missing_requirements"
    }
}
