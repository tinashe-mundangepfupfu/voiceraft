import Combine
import Foundation

struct AppSettings: Codable, Equatable {
    var obsidianVaultPath: String
    var lmStudioBaseURL: String
    var lmStudioModel: String
    var onlineInputDeviceID: String

    static let storageKey = "VoiceRaft.AppSettings"

    static func `default`() -> AppSettings {
        AppSettings(
            obsidianVaultPath: "/Users/tmundangepfupfu/Documents/Obsidian Vault",
            lmStudioBaseURL: "http://127.0.0.1:1234/v1",
            lmStudioModel: "qwen3-8b-deepseek-v3.2-speciale-distill",
            onlineInputDeviceID: ""
        )
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
