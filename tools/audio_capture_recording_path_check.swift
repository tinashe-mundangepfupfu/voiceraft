import Foundation

private struct CheckFailure: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

@main
struct AudioCaptureRecordingPathCheck {
    static func main() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("voiceraft/AudioCaptureService.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        try assert(
            source.contains("AVCaptureAudioFileOutput"),
            "AudioCaptureService should use AVCaptureAudioFileOutput for macOS audio recording."
        )
        try assert(
            !source.contains("AVCaptureAudioDataOutput"),
            "AudioCaptureService should avoid manual AVCaptureAudioDataOutput sample writing."
        )
        try assert(
            !source.contains("AVAssetWriter"),
            "AudioCaptureService should avoid AVAssetWriter for live microphone capture."
        )
    }

    private static func assert(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else {
            throw CheckFailure(message: message)
        }
    }
}
