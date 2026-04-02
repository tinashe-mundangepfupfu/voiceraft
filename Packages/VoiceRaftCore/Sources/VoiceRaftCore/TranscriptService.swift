import Foundation
import Speech

public final class AppleSpeechTranscriptService: NSObject, TranscriptService, @unchecked Sendable {
    public override init() {
        super.init()
    }

    public func transcribe(audioURL: URL, language: String) async throws -> String {
        try await authorizeSpeechRecognition()

        let locale = Locale(identifier: language)
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw VoiceRaftCoreError.speechTranscriptionUnavailable(
                "Speech transcription is unavailable for locale \(locale.identifier)."
            )
        }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition

        return try await withCheckedThrowingContinuation { continuation in
            var finished = false
            recognizer.recognitionTask(with: request) { result, error in
                if finished {
                    return
                }

                if let error {
                    finished = true
                    continuation.resume(throwing: VoiceRaftCoreError.transcriptionFailed(error.localizedDescription))
                    return
                }

                guard let result, result.isFinal else {
                    return
                }

                let normalized = self.normalizeTranscript(result.bestTranscription.formattedString)
                finished = true
                if normalized.isEmpty {
                    continuation.resume(throwing: VoiceRaftCoreError.emptyTranscript)
                } else {
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
                throw VoiceRaftCoreError.speechRecognitionPermissionDenied
            }
        default:
            throw VoiceRaftCoreError.speechRecognitionPermissionDenied
        }
    }

    private func normalizeTranscript(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
