import Combine
import Foundation

enum NotesProvider: String, Codable, Equatable {
    case lmStudio
    case claude
}

struct AppSettings: Codable, Equatable {
    var obsidianVaultPath: String
    var notesProvider: NotesProvider
    var lmStudioBaseURL: String
    var lmStudioModel: String
    var claudeModel: String
    var onlineInputDeviceID: String

    static let storageKey = "VoiceRaft.AppSettings"

    static func `default`() -> AppSettings {
        AppSettings(
            obsidianVaultPath: "/Users/tmundangepfupfu/Documents/Obsidian Vault",
            notesProvider: .lmStudio,
            lmStudioBaseURL: "http://127.0.0.1:1234/v1",
            lmStudioModel: "qwen3-8b-deepseek-v3.2-speciale-distill",
            claudeModel: "",
            onlineInputDeviceID: ""
        )
    }

    init(
        obsidianVaultPath: String,
        notesProvider: NotesProvider,
        lmStudioBaseURL: String,
        lmStudioModel: String,
        claudeModel: String,
        onlineInputDeviceID: String
    ) {
        self.obsidianVaultPath = obsidianVaultPath
        self.notesProvider = notesProvider
        self.lmStudioBaseURL = lmStudioBaseURL
        self.lmStudioModel = lmStudioModel
        self.claudeModel = claudeModel
        self.onlineInputDeviceID = onlineInputDeviceID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        obsidianVaultPath = try container.decode(String.self, forKey: .obsidianVaultPath)
        notesProvider = try container.decodeIfPresent(NotesProvider.self, forKey: .notesProvider) ?? .lmStudio
        lmStudioBaseURL = try container.decode(String.self, forKey: .lmStudioBaseURL)
        lmStudioModel = try container.decode(String.self, forKey: .lmStudioModel)
        claudeModel = try container.decodeIfPresent(String.self, forKey: .claudeModel) ?? ""
        onlineInputDeviceID = try container.decode(String.self, forKey: .onlineInputDeviceID)
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings {
        didSet {
            save()
        }
    }

    init(userDefaults: UserDefaults = .standard) {
        if
            let data = userDefaults.data(forKey: AppSettings.storageKey),
            let decoded = try? JSONDecoder().decode(AppSettings.self, from: data)
        {
            settings = decoded
        } else {
            settings = .default()
        }
        self.userDefaults = userDefaults
    }

    private let userDefaults: UserDefaults

    private func save() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        userDefaults.set(data, forKey: AppSettings.storageKey)
    }
}
