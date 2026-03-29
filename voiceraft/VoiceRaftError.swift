import Foundation

enum VoiceRaftError: LocalizedError {
    case microphonePermissionDenied
    case inputDeviceNotFound
    case recordingNotActive
    case invalidSidecarBaseURL
    case sidecarExecutableMissing(String)
    case sidecarLaunchFailed(String)
    case sidecarRequestFailed(String)
    case missingOrInvalidVaultPath
    case exportFailed(String)
    case pendingExportFailed(String)

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            "VoiceRaft needs microphone access to record meetings."
        case .inputDeviceNotFound:
            "The configured online meeting input device could not be found."
        case .recordingNotActive:
            "There is no active recording to stop."
        case .invalidSidecarBaseURL:
            "The local sidecar URL is invalid."
        case let .sidecarExecutableMissing(path):
            "VoiceRaft could not find the sidecar executable at \(path)."
        case let .sidecarLaunchFailed(message):
            "VoiceRaft could not launch the sidecar. \(message)"
        case let .sidecarRequestFailed(message):
            "VoiceRaft could not process the meeting. \(message)"
        case .missingOrInvalidVaultPath:
            "The configured Obsidian vault path is missing or invalid."
        case let .exportFailed(message):
            "VoiceRaft could not save the note to Obsidian. \(message)"
        case let .pendingExportFailed(message):
            "VoiceRaft could not save the pending export. \(message)"
        }
    }
}
