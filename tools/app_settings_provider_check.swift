import Foundation

private struct CheckFailure: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

@main
struct AppSettingsProviderCheck {
    static func main() throws {
        try assertSourceShape()
        try assertLegacyDecode()
    }

    private static func assertSourceShape() throws {
        let sourceURL = repoRootURL()
            .appendingPathComponent("voiceraft/AppSettings.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        try assert(source.contains("enum NotesProvider"))
        try assert(source.contains("decodeIfPresent"))
        try assert(source.contains(".lmStudio"))
        try assert(source.contains("claudeModel"))
    }

    private static func assertLegacyDecode() throws {
        let fileManager = FileManager.default
        let tempDirectory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempDirectory) }

        let harnessURL = tempDirectory.appendingPathComponent("legacy_decode_check.swift")
        let binaryURL = tempDirectory.appendingPathComponent("legacy_decode_check")

        try #"""
        import Foundation

        @main
        struct LegacyDecodeCheck {
            static func main() throws {
                let payload = #"{"obsidianVaultPath":"/Users/tmundangepfupfu/Documents/Obsidian Vault","lmStudioBaseURL":"http://example.invalid/v1","lmStudioModel":"legacy-model","onlineInputDeviceID":"input-123"}"#

                let data = Data(payload.utf8)
                let settings = try JSONDecoder().decode(AppSettings.self, from: data)

                guard settings.lmStudioBaseURL == "http://example.invalid/v1" else {
                    throw Failure(message: "lmStudioBaseURL should be preserved")
                }
                guard settings.lmStudioModel == "legacy-model" else {
                    throw Failure(message: "lmStudioModel should be preserved")
                }
                guard settings.notesProvider == .lmStudio else {
                    throw Failure(message: "notesProvider should default to .lmStudio")
                }
                guard settings.claudeModel.isEmpty else {
                    throw Failure(message: "claudeModel should default to empty string")
                }
                guard settings.onlineInputDeviceID == "input-123" else {
                    throw Failure(message: "onlineInputDeviceID should be preserved")
                }
            }
        }

        private struct Failure: LocalizedError {
            let message: String

            var errorDescription: String? { message }
        }
        """#
        .write(to: harnessURL, atomically: true, encoding: .utf8)

        let appSettingsURL = repoRootURL().appendingPathComponent("voiceraft/AppSettings.swift")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = [
            "swiftc",
            "-parse-as-library",
            harnessURL.path,
            appSettingsURL.path,
            "-o",
            binaryURL.path
        ]

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw CheckFailure(message: "legacy decode harness failed to compile")
        }

        let runProcess = Process()
        runProcess.executableURL = binaryURL
        try runProcess.run()
        runProcess.waitUntilExit()

        guard runProcess.terminationStatus == 0 else {
            throw CheckFailure(message: "legacy decode harness failed")
        }
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
