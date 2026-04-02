import Foundation

enum VoiceRaftError: LocalizedError {
    case microphonePermissionDenied
    case speechRecognitionPermissionDenied
    case inputDeviceNotFound
    case recordingNotActive
    case noAudioCaptured
    case recordingFailed(String)
    case invalidLMStudioBaseURL
    case transcriptionFailed(String)
    case lmStudioRequestFailed(String)
    case missingClaudeAPIKey
    case claudeModelFetchFailed(String)
    case invalidClaudeModel(String)
    case missingOrInvalidVaultPath
    case exportFailed(String)
    case pendingExportFailed(String)

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            "VoiceRaft needs microphone access to record meetings."
        case .speechRecognitionPermissionDenied:
            "VoiceRaft needs speech recognition permission to transcribe recorded meetings."
        case .inputDeviceNotFound:
            "The configured online meeting input device could not be found."
        case .recordingNotActive:
            "There is no active recording to stop."
        case .noAudioCaptured:
            "VoiceRaft didn't receive any audio before the recording stopped."
        case let .recordingFailed(message):
            "VoiceRaft could not finish recording the meeting. \(message)"
        case .invalidLMStudioBaseURL:
            "The LM Studio base URL is invalid."
        case let .transcriptionFailed(message):
            "VoiceRaft could not transcribe the meeting. \(message)"
        case let .lmStudioRequestFailed(message):
            "VoiceRaft could not generate meeting notes. \(message)"
        case .missingClaudeAPIKey:
            "Save a Claude API key in Settings before using Claude for meeting notes."
        case let .claudeModelFetchFailed(message):
            "VoiceRaft could not load Claude models. \(message)"
        case let .invalidClaudeModel(model):
            "The Claude model \"\(model)\" is unavailable. Choose a current Claude model in Settings."
        case .missingOrInvalidVaultPath:
            "The configured Obsidian vault path is missing or invalid."
        case let .exportFailed(message):
            "VoiceRaft could not save the note to Obsidian. \(message)"
        case let .pendingExportFailed(message):
            "VoiceRaft could not save the pending export. \(message)"
        }
    }
}
