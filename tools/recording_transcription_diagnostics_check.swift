import Foundation

private struct CheckFailure: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

@main
struct RecordingTranscriptionDiagnosticsCheck {
    static func main() throws {
        try verifiesTooShortMessage()
        try verifiesMostlySilentMessage()
    }

    private static func verifiesTooShortMessage() throws {
        let diagnostics = RecordedAudioDiagnostics(
            inputDeviceName: "MacBook Pro Microphone",
            durationSeconds: 0.3,
            averagePowerDBFS: -28.4,
            byteCount: 2_048
        )

        let message = RecordingTranscriptionDiagnostics.failureMessage(for: diagnostics)
        try assert(
            message == "The recording from MacBook Pro Microphone was only 0.3s long, which is too short to transcribe reliably.",
            "expected very short recordings to explain the duration problem"
        )
    }

    private static func verifiesMostlySilentMessage() throws {
        let diagnostics = RecordedAudioDiagnostics(
            inputDeviceName: "MacBook Pro Microphone",
            durationSeconds: 18.2,
            averagePowerDBFS: -58.1,
            byteCount: 128_000
        )

        let message = RecordingTranscriptionDiagnostics.failureMessage(for: diagnostics)
        try assert(
            message == "The recording from MacBook Pro Microphone was 18.2s long with an average level of -58.1 dBFS, so it appears to be mostly silence.",
            "expected mostly silent recordings to explain the level problem"
        )
    }

    private static func assert(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else {
            throw CheckFailure(message: message)
        }
    }
}
