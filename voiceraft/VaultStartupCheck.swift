import Foundation

enum VaultStartupStatus: Equatable {
    case validVault(String)
    case directoryMissing(String)
    case notObsidianVault(String)
    case missingConfiguration

    var title: String {
        switch self {
        case .validVault:
            "VoiceRaft Vault"
        case .directoryMissing, .notObsidianVault, .missingConfiguration:
            "VoiceRaft Vault Check"
        }
    }

    var message: String {
        switch self {
        case let .validVault(path):
            "Using Obsidian vault: \(path)"
        case let .directoryMissing(path):
            "The configured vault path does not exist: \(path)"
        case let .notObsidianVault(path):
            "The configured folder exists, but it does not contain a .obsidian folder: \(path)"
        case .missingConfiguration:
            "No Obsidian vault path is configured."
        }
    }

    var shouldInterruptLaunch: Bool {
        switch self {
        case .validVault:
            false
        case .directoryMissing, .notObsidianVault, .missingConfiguration:
            true
        }
    }
}

enum VaultStartupCheck {
    static func status(for configuredPath: String, fileManager: FileManager = .default) -> VaultStartupStatus {
        let path = configuredPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            return .missingConfiguration
        }

        let url = URL(fileURLWithPath: path, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return .directoryMissing(path)
        }

        let obsidianConfigURL = url.appendingPathComponent(".obsidian", isDirectory: true)
        guard fileManager.fileExists(atPath: obsidianConfigURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return .notObsidianVault(path)
        }

        return .validVault(path)
    }
}
