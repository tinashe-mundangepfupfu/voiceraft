import Foundation

private struct CheckFailure: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

@main
struct NativeProviderSelectionCheck {
    static func main() throws {
        let processorURL = repoRootURL().appendingPathComponent("voiceraft/NativeMeetingProcessor.swift")
        let processorSource = try String(contentsOf: processorURL, encoding: .utf8)

        try assert(processorSource.contains("switch settings.notesProvider"), "NativeMeetingProcessor is missing provider switching")
        try assert(processorSource.contains("ClaudeClient"), "NativeMeetingProcessor is missing Claude client wiring")
        try assert(
            processorSource.contains("LMStudioClient") || processorSource.contains("LMStudioMeetingClient"),
            "NativeMeetingProcessor is missing LM Studio client wiring"
        )
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
