import Combine
import Foundation

struct AppSettings: Codable, Equatable {
    var obsidianVaultPath: String
    var projectRootPath: String
    var lmStudioBaseURL: String
    var lmStudioModel: String
    var whisperModel: String
    var sidecarHost: String
    var sidecarPort: Int
    var onlineInputDeviceID: String

    static let storageKey = "VoiceRaft.AppSettings"

    static func `default`() -> AppSettings {
        AppSettings(
            obsidianVaultPath: "",
            projectRootPath: FileManager.default.currentDirectoryPath,
            lmStudioBaseURL: "http://127.0.0.1:1234/v1",
            lmStudioModel: "qwen2.5-7b-instruct",
            whisperModel: "small.en",
            sidecarHost: "127.0.0.1",
            sidecarPort: 8765,
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
