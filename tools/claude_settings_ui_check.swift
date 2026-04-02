import Foundation

private struct CheckFailure: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

@main
struct ClaudeSettingsUICheck {
    static func main() throws {
        let settingsURL = repoRootURL().appendingPathComponent("voiceraft/SettingsUI.swift")
        let settingsSource = try String(contentsOf: settingsURL, encoding: .utf8)

        try assert(settingsSource.contains("Notes Provider"), "SettingsUI is missing the Notes Provider control")
        try assert(settingsSource.contains("Claude"), "SettingsUI is missing Claude provider text")
        try assert(settingsSource.contains("SecureField"), "SettingsUI is missing the Claude API key secure field")
        try assert(settingsSource.contains("Refresh Models"), "SettingsUI is missing the Claude Refresh Models action")
        try assert(settingsSource.contains("Save API Key"), "SettingsUI is missing the Claude Save API Key action")
    }

    private static func assert(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else {
            throw CheckFailure(message: message)
        }
    }

    private static func repoRootURL() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }
}
