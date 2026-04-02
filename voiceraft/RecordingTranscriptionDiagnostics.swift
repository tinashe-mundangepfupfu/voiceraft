import Foundation

struct RecordedAudioDiagnostics: Sendable, Equatable {
    let inputDeviceName: String
    let durationSeconds: Double
    let averagePowerDBFS: Double?
    let byteCount: Int64
}

struct RecordedAudioCapture: Sendable {
    let url: URL
    let diagnostics: RecordedAudioDiagnostics
}

enum RecordingTranscriptionDiagnostics {
    private static let minimumDurationSeconds = 0.5
    private static let mostlySilentThresholdDBFS = -55.0

    static func preflightFailureMessage(for diagnostics: RecordedAudioDiagnostics) -> String? {
        if diagnostics.durationSeconds < minimumDurationSeconds {
            return failureMessage(for: diagnostics)
        }
        if let averagePowerDBFS = diagnostics.averagePowerDBFS, averagePowerDBFS <= mostlySilentThresholdDBFS {
            return failureMessage(for: diagnostics)
        }
        return nil
    }

    static func failureMessage(for diagnostics: RecordedAudioDiagnostics) -> String {
        if diagnostics.durationSeconds < minimumDurationSeconds {
            return "The recording from \(diagnostics.inputDeviceName) was only \(format(diagnostics.durationSeconds))s long, which is too short to transcribe reliably."
        }

        if let averagePowerDBFS = diagnostics.averagePowerDBFS, averagePowerDBFS <= mostlySilentThresholdDBFS {
            return "The recording from \(diagnostics.inputDeviceName) was \(format(diagnostics.durationSeconds))s long with an average level of \(format(averagePowerDBFS)) dBFS, so it appears to be mostly silence."
        }

        if let averagePowerDBFS = diagnostics.averagePowerDBFS {
            return "Speech recognition produced no usable text from the recording taken on \(diagnostics.inputDeviceName). The clip was \(format(diagnostics.durationSeconds))s long with an average level of \(format(averagePowerDBFS)) dBFS."
        }

        return "Speech recognition produced no usable text from the recording taken on \(diagnostics.inputDeviceName). The clip was \(format(diagnostics.durationSeconds))s long."
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}
