import Foundation

private struct CheckFailure: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

@main
struct VaultStartupCheckTool {
    static func main() throws {
        try verifiesMissingConfiguration()
        try verifiesMissingDirectory()
        try verifiesNonVaultDirectory()
        try verifiesValidVault()
    }

    private static func verifiesMissingConfiguration() throws {
        let status = VaultStartupCheck.status(for: "   ")
        try assert(status == .missingConfiguration, "expected blank path to fail fast")
    }

    private static func verifiesMissingDirectory() throws {
        let path = "/tmp/voiceraft-missing-\(UUID().uuidString)"
        let status = VaultStartupCheck.status(for: path)
        try assert(status == .directoryMissing(path), "expected missing path to be reported verbatim")
    }

    private static func verifiesNonVaultDirectory() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url) }

        let status = VaultStartupCheck.status(for: url.path)
        try assert(status == .notObsidianVault(url.path), "expected plain directory to warn about missing .obsidian")
    }

    private static func verifiesValidVault() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let obsidianURL = url.appendingPathComponent(".obsidian", isDirectory: true)
        try FileManager.default.createDirectory(at: obsidianURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url) }

        let status = VaultStartupCheck.status(for: url.path)
        try assert(status == .validVault(url.path), "expected directory with .obsidian to pass")
    }

    private static func assert(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else {
            throw CheckFailure(message: message)
        }
    }
}
