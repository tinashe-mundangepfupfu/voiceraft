@preconcurrency import AVFoundation
import Foundation
import OSLog

final class AudioCaptureService: NSObject, AVCaptureFileOutputRecordingDelegate, @unchecked Sendable {
    private struct PendingRecordingStop {
        let outputURL: URL
        let inputDeviceName: String
        let continuation: CheckedContinuation<RecordedAudioCapture, Error>
    }

    private struct StopRequest {
        let outputURL: URL?
        let inputDeviceName: String
        let terminalError: VoiceRaftError?
    }

    private struct FinishedRecordingContext {
        let pendingStop: PendingRecordingStop?
        let error: VoiceRaftError?
    }

    private let captureSession = AVCaptureSession()
    private let audioFileOutput = AVCaptureAudioFileOutput()
    private let stateQueue = DispatchQueue(label: "VoiceRaft.AudioCapture.State")
    private let logger = Logger(subsystem: "com.voiceraft.app", category: "audio-capture")

    private var currentInput: AVCaptureDeviceInput?
    private var outputURL: URL?
    private var currentInputDeviceName: String?
    private var pendingStop: PendingRecordingStop?
    private var terminalRecordingError: VoiceRaftError?

    func requestPermissionIfNeeded() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return
        case .notDetermined:
            let granted = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { allowed in
                    continuation.resume(returning: allowed)
                }
            }
            guard granted else { throw VoiceRaftError.microphonePermissionDenied }
        default:
            throw VoiceRaftError.microphonePermissionDenied
        }
    }

    func startRecording(session: MeetingSession, settings: AppSettings) throws -> URL {
        let selectedDevice = try resolveDevice(for: session.mode, settings: settings)
        let recordingsDirectory = try FileLayout.applicationSupportDirectory().appendingPathComponent("Recordings", isDirectory: true)
        try FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)
        let targetURL = recordingsDirectory.appendingPathComponent(FileLayout.timestampedAudioFilename(for: session))
        let outputFileType = AVFileType.m4a

        logger.info(
            "start recording mode=\(session.mode.rawValue, privacy: .public) device=\(selectedDevice.localizedName, privacy: .public) id=\(selectedDevice.uniqueID, privacy: .public)"
        )

        guard AVCaptureAudioFileOutput.availableOutputFileTypes().contains(outputFileType) else {
            throw VoiceRaftError.recordingFailed("This Mac does not support m4a audio capture output.")
        }

        audioFileOutput.audioSettings = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVEncoderBitRateKey: 128_000,
            AVNumberOfChannelsKey: 1,
        ]

        try CaptureSessionStartup.configureAndStart(captureSession) {
            if let currentInput {
                captureSession.removeInput(currentInput)
                self.currentInput = nil
            }
            captureSession.removeOutput(audioFileOutput)

            let input = try AVCaptureDeviceInput(device: selectedDevice)
            guard captureSession.canAddInput(input) else {
                throw VoiceRaftError.inputDeviceNotFound
            }
            captureSession.addInput(input)
            self.currentInput = input

            guard captureSession.canAddOutput(audioFileOutput) else {
                throw VoiceRaftError.inputDeviceNotFound
            }
            captureSession.addOutput(audioFileOutput)
        }

        stateQueue.sync {
            outputURL = targetURL
            currentInputDeviceName = selectedDevice.localizedName
            pendingStop = nil
            terminalRecordingError = nil
        }

        audioFileOutput.startRecording(to: targetURL, outputFileType: outputFileType, recordingDelegate: self)
        logger.info("recording requested output=\(targetURL.path, privacy: .public)")

        return targetURL
    }

    func stopRecording() async throws -> RecordedAudioCapture {
        let request = stateQueue.sync {
            let request = StopRequest(
                outputURL: outputURL,
                inputDeviceName: currentInputDeviceName ?? "Selected Input",
                terminalError: terminalRecordingError
            )
            terminalRecordingError = nil
            return request
        }

        logger.info(
            "stop recording requested output=\(request.outputURL?.path ?? "nil", privacy: .public) terminalError=\(request.terminalError?.localizedDescription ?? "none", privacy: .public)"
        )

        if let terminalError = request.terminalError {
            throw terminalError
        }

        guard let outputURL = request.outputURL else {
            throw VoiceRaftError.recordingNotActive
        }

        guard audioFileOutput.isRecording else {
            let recording = makeRecordedAudioCapture(outputURL: outputURL, inputDeviceName: request.inputDeviceName)
            try validate(recording)
            captureSession.stopRunning()
            clearFinishedRecordingState()
            logger.info(
                "recording already finished bytes=\(recording.diagnostics.byteCount) duration=\(recording.diagnostics.durationSeconds, privacy: .public)"
            )
            return recording
        }

        return try await withCheckedThrowingContinuation { continuation in
            stateQueue.sync {
                pendingStop = PendingRecordingStop(
                    outputURL: outputURL,
                    inputDeviceName: request.inputDeviceName,
                    continuation: continuation
                )
            }
            audioFileOutput.stopRecording()
        }
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        let context = stateQueue.sync { () -> FinishedRecordingContext in
            let pendingStop = self.pendingStop
            self.pendingStop = nil
            self.outputURL = nil
            self.currentInputDeviceName = nil

            if let error {
                let wrappedError = VoiceRaftError.recordingFailed(error.localizedDescription)
                if pendingStop == nil {
                    terminalRecordingError = wrappedError
                    return FinishedRecordingContext(pendingStop: nil, error: nil)
                }
                terminalRecordingError = nil
                return FinishedRecordingContext(pendingStop: pendingStop, error: wrappedError)
            }

            terminalRecordingError = nil
            return FinishedRecordingContext(pendingStop: pendingStop, error: nil)
        }

        captureSession.stopRunning()

        guard let pendingStop = context.pendingStop else { return }
        if let error = context.error {
            logger.error("recording finished with error=\(error.localizedDescription, privacy: .public)")
            pendingStop.continuation.resume(throwing: error)
            return
        }

        let recording = makeRecordedAudioCapture(
            outputURL: pendingStop.outputURL,
            inputDeviceName: pendingStop.inputDeviceName
        )

        do {
            try validate(recording)
            logger.info(
                "recording finished bytes=\(recording.diagnostics.byteCount) duration=\(recording.diagnostics.durationSeconds, privacy: .public) device=\(recording.diagnostics.inputDeviceName, privacy: .public)"
            )
            pendingStop.continuation.resume(returning: recording)
        } catch {
            logger.error("recording validation failed error=\(error.localizedDescription, privacy: .public)")
            pendingStop.continuation.resume(throwing: error)
        }
    }

    private func resolveDevice(for mode: MeetingMode, settings: AppSettings) throws -> AVCaptureDevice {
        let devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: AudioInputDiscoveryPolicy.deviceTypes,
            mediaType: .audio,
            position: .unspecified
        ).devices
        switch mode {
        case .room:
            if let defaultDevice = AVCaptureDevice.default(for: .audio) {
                return defaultDevice
            }
            guard let fallback = devices.first else { throw VoiceRaftError.inputDeviceNotFound }
            return fallback
        case .online:
            if !settings.onlineInputDeviceID.isEmpty {
                guard let matching = devices.first(where: { $0.uniqueID == settings.onlineInputDeviceID }) else {
                    throw VoiceRaftError.inputDeviceNotFound
                }
                return matching
            }
            if let defaultDevice = AVCaptureDevice.default(for: .audio) {
                return defaultDevice
            }
            guard let fallback = devices.first else { throw VoiceRaftError.inputDeviceNotFound }
            return fallback
        }
    }

    private func makeRecordedAudioCapture(outputURL: URL, inputDeviceName: String) -> RecordedAudioCapture {
        RecordedAudioCapture(
            url: outputURL,
            diagnostics: RecordedAudioDiagnostics(
                inputDeviceName: inputDeviceName,
                durationSeconds: readDurationSeconds(from: outputURL),
                averagePowerDBFS: readAveragePowerDBFS(from: outputURL),
                byteCount: readByteCount(from: outputURL)
            )
        )
    }

    private func validate(_ recording: RecordedAudioCapture) throws {
        guard recording.diagnostics.byteCount > 0 else {
            try? FileManager.default.removeItem(at: recording.url)
            throw VoiceRaftError.noAudioCaptured
        }
    }

    private func clearFinishedRecordingState() {
        stateQueue.sync {
            outputURL = nil
            currentInputDeviceName = nil
            pendingStop = nil
            terminalRecordingError = nil
        }
    }

    private func readByteCount(from url: URL) -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }

    private func readDurationSeconds(from url: URL) -> Double {
        if let audioFile = try? AVAudioFile(forReading: url) {
            let sampleRate = audioFile.processingFormat.sampleRate
            if sampleRate > 0 {
                return Double(audioFile.length) / sampleRate
            }
        }
        return 0
    }

    private func readAveragePowerDBFS(from url: URL) -> Double? {
        guard let audioFile = try? AVAudioFile(forReading: url) else { return nil }
        return averagePowerDBFS(for: audioFile)
    }

    private func averagePowerDBFS(for audioFile: AVAudioFile) -> Double? {
        let format = audioFile.processingFormat
        let frameCapacity: AVAudioFrameCount = 4_096
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else { return nil }

        var sumSquares = 0.0
        var sampleCount = 0

        while audioFile.framePosition < audioFile.length {
            do {
                try audioFile.read(into: buffer, frameCount: frameCapacity)
            } catch {
                return nil
            }

            let frames = Int(buffer.frameLength)
            if frames == 0 { break }

            if let channels = buffer.floatChannelData {
                for channelIndex in 0..<Int(format.channelCount) {
                    let samples = UnsafeBufferPointer(start: channels[channelIndex], count: frames)
                    for sample in samples {
                        let value = Double(sample)
                        sumSquares += value * value
                        sampleCount += 1
                    }
                }
                continue
            }

            if let channels = buffer.int16ChannelData {
                let scale = Double(Int16.max)
                for channelIndex in 0..<Int(format.channelCount) {
                    let samples = UnsafeBufferPointer(start: channels[channelIndex], count: frames)
                    for sample in samples {
                        let value = Double(sample) / scale
                        sumSquares += value * value
                        sampleCount += 1
                    }
                }
                continue
            }

            if let channels = buffer.int32ChannelData {
                let scale = Double(Int32.max)
                for channelIndex in 0..<Int(format.channelCount) {
                    let samples = UnsafeBufferPointer(start: channels[channelIndex], count: frames)
                    for sample in samples {
                        let value = Double(sample) / scale
                        sumSquares += value * value
                        sampleCount += 1
                    }
                }
                continue
            }

            return nil
        }

        guard sampleCount > 0 else { return nil }
        let rms = sqrt(sumSquares / Double(sampleCount))
        guard rms > 0 else { return -160 }
        return 20 * log10(rms)
    }
}
