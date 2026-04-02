import Foundation

private struct CheckFailure: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

@main
struct AudioCaptureDeviceSelectionCheck {
    static func main() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("voiceraft/AudioCaptureService.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        try assert(
            !source.contains("kAudioHardwarePropertyDefaultInputDevice"),
            "AudioCaptureService should not switch the machine-wide default input device."
        )
        try assert(
            !source.contains("AudioObjectSetPropertyData"),
            "AudioCaptureService should not mutate global CoreAudio device state."
        )
        try assert(
            source.contains("AVCaptureDeviceInput(device:"),
            "AudioCaptureService should configure capture using the selected AVCaptureDevice."
        )
    }

    private static func assert(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else {
            throw CheckFailure(message: message)
        }
    }
}
