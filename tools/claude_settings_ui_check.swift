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

        try assert(settingsSource.contains("Notes Provider"))
        try assert(settingsSource.contains("Claude"))
        try assert(settingsSource.contains("SecureField"))
        try assert(settingsSource.contains("Refresh Models"))
        try assert(settingsSource.contains("Save API Key"))
    }

    private static func assert(_ condition: @autoclosure () -> Bool) throws {
        guard condition() else {
            throw CheckFailure(message: "assertion failed")
        }
    }

    private static func repoRootURL() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }
}
