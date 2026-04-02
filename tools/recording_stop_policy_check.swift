import Foundation

private struct CheckFailure: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

@main
struct RecordingStopPolicyCheck {
    static func main() throws {
        try assertAction(
            RecordingStopPolicy.action(for: .waitingForFirstSample),
            equals: .discardEmptyRecording,
            context: "expected empty recordings to be discarded instead of waiting for finishWriting"
        )
        try assertAction(
            RecordingStopPolicy.action(for: .writing),
            equals: .finishWriting,
            context: "expected active recordings to finish writing"
        )
        try assertAction(
            RecordingStopPolicy.action(for: .failed("disk full")),
            equals: .fail("disk full"),
            context: "expected writer failures to preserve their message"
        )
        try assertAction(
            RecordingStopPolicy.action(for: .failed(nil)),
            equals: .fail("The recording writer failed before VoiceRaft could finish the file."),
            context: "expected generic writer failures to surface a fallback message"
        )
        try assertAction(
            RecordingStopPolicy.action(for: .cancelled),
            equals: .fail("The recording was cancelled before VoiceRaft could finish the file."),
            context: "expected cancelled recordings to fail clearly"
        )
    }

    private static func assertAction(
        _ actual: RecordingStopAction,
        equals expected: RecordingStopAction,
        context: String
    ) throws {
        guard actual == expected else {
            throw CheckFailure(message: "\(context): expected \(expected), found \(actual)")
        }
    }
}
