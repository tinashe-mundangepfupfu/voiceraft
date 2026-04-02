import Foundation

private struct CheckFailure: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

@main
struct StatusItemAppearanceCheck {
    static func main() throws {
        try assertAppearance(
            StatusItemAppearance.make(for: .idle),
            title: "",
            symbolName: "voiceraft.splitv",
            context: "idle state should use the shared VoiceRaft glyph"
        )
        try assertAppearance(
            StatusItemAppearance.make(for: .recording),
            title: "",
            symbolName: "voiceraft.splitv",
            context: "recording state should keep the branded glyph instead of a generic symbol"
        )
        try assertAppearance(
            StatusItemAppearance.make(for: .processing),
            title: "",
            symbolName: "voiceraft.splitv",
            context: "processing state should keep the branded glyph instead of swapping icons"
        )
    }

    private static func assertAppearance(
        _ appearance: StatusItemAppearance,
        title: String,
        symbolName: String,
        context: String
    ) throws {
        guard appearance.title == title else {
            throw CheckFailure(message: "\(context): expected title \(title), found \(appearance.title)")
        }
        guard appearance.symbolName == symbolName else {
            throw CheckFailure(message: "\(context): expected symbol \(symbolName), found \(appearance.symbolName)")
        }
    }
}
