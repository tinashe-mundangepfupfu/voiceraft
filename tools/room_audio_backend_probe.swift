@preconcurrency import AVFoundation
import Foundation

private enum ProbeError: LocalizedError {
    case microphonePermissionDenied
    case inputDeviceNotFound
    case captureFailed(String)
    case timeout(String)

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            "Microphone access was denied for the probe."
        case .inputDeviceNotFound:
            "The built-in microphone could not be resolved."
        case let .captureFailed(message):
            "Capture failed: \(message)"
        case let .timeout(message):
            "Timed out: \(message)"
        }
    }
}

private enum Backend: String {
    case avcapture
    case avaudioengine
}

private struct ProbeResult {
    let backend: Backend
    let outputURL: URL
    let byteCount: Int64
    let durationSeconds: Double
}

@main
struct RoomAudioBackendProbe {
    static func main() async {
        do {
            let backend = try parseBackend()
            try await requestMicrophonePermissionIfNeeded()
            let result = try await runProbe(using: backend)
            print("backend=\(result.backend.rawValue)")
            print("path=\(result.outputURL.path)")
            print("bytes=\(result.byteCount)")
            print("duration=\(String(format: "%.2f", result.durationSeconds))")
            exit(0)
        } catch {
            fputs("\(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func parseBackend() throws -> Backend {
        let arguments = CommandLine.arguments.dropFirst()
        if let value = arguments.first, let backend = Backend(rawValue: value) {
            return backend
        }
        return .avcapture
    }

    private static func requestMicrophonePermissionIfNeeded() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return
        case .notDetermined:
            let granted = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { continuation.resume(returning: $0) }
            }
            guard granted else { throw ProbeError.microphonePermissionDenied }
        default:
            throw ProbeError.microphonePermissionDenied
        }
    }

    private static func runProbe(using backend: Backend) async throws -> ProbeResult {
        switch backend {
        case .avcapture:
            return try await AVCaptureProbe().record()
        case .avaudioengine:
            return try await AVAudioEngineProbe().record()
        }
    }
}

private final class AVCaptureProbe: NSObject, AVCaptureFileOutputRecordingDelegate {
    private let session = AVCaptureSession()
    private let fileOutput = AVCaptureAudioFileOutput()
    private var continuation: CheckedContinuation<ProbeResult, Error>?

    func record() async throws -> ProbeResult {
        let device = try resolveBuiltInMicrophone()
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("voiceraft-probe-avcapture-\(UUID().uuidString).m4a")

        fileOutput.audioSettings = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVEncoderBitRateKey: 128_000,
            AVNumberOfChannelsKey: 1,
        ]

        session.beginConfiguration()

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw ProbeError.inputDeviceNotFound }
        guard session.canAddOutput(fileOutput) else {
            throw ProbeError.captureFailed("AVCaptureAudioFileOutput could not be added to the session.")
        }
        session.addInput(input)
        session.addOutput(fileOutput)

        session.commitConfiguration()
        session.startRunning()

        fileOutput.startRecording(to: outputURL, outputFileType: .m4a, recordingDelegate: self)

        try await Task.sleep(nanoseconds: 3_000_000_000)

        return try await withTimeout(seconds: 10) {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                self.fileOutput.stopRecording()
            }
        }
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        defer {
            session.stopRunning()
            continuation = nil
        }

        if let error {
            continuation?.resume(throwing: ProbeError.captureFailed(error.localizedDescription))
            return
        }

        do {
            continuation?.resume(returning: try makeResult(backend: .avcapture, outputURL: outputFileURL))
        } catch {
            continuation?.resume(throwing: error)
        }
    }

    private func resolveBuiltInMicrophone() throws -> AVCaptureDevice {
        let devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        ).devices

        if let builtIn = devices.first(where: { $0.uniqueID == "BuiltInMicrophoneDevice" }) {
            return builtIn
        }
        if let fallback = AVCaptureDevice.default(for: .audio) {
            return fallback
        }
        throw ProbeError.inputDeviceNotFound
    }
}

private final class AVAudioEngineProbe {
    private let engine = AVAudioEngine()

    func record() async throws -> ProbeResult {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("voiceraft-probe-avaudioengine-\(UUID().uuidString).caf")
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        let file = try AVAudioFile(forWriting: outputURL, settings: format.settings)

        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
            do {
                try file.write(from: buffer)
            } catch {
                fputs("tap-write-error: \(error.localizedDescription)\n", stderr)
            }
        }

        engine.prepare()
        try engine.start()

        try await Task.sleep(nanoseconds: 3_000_000_000)

        inputNode.removeTap(onBus: 0)
        engine.stop()

        return try makeResult(backend: .avaudioengine, outputURL: outputURL)
    }
}

private func withTimeout<T>(seconds: UInt64, operation: @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            throw ProbeError.timeout("recording delegate did not finish in time")
        }

        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

private func makeResult(backend: Backend, outputURL: URL) throws -> ProbeResult {
    let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
    let byteCount = (attributes[.size] as? NSNumber)?.int64Value ?? 0
    let audioFile = try AVAudioFile(forReading: outputURL)
    let sampleRate = audioFile.processingFormat.sampleRate
    let durationSeconds = sampleRate > 0 ? Double(audioFile.length) / sampleRate : 0
    return ProbeResult(
        backend: backend,
        outputURL: outputURL,
        byteCount: byteCount,
        durationSeconds: durationSeconds
    )
}
