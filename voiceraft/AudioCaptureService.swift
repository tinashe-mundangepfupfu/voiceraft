@preconcurrency import AVFoundation
import CoreMedia
import Foundation

final class AudioCaptureService: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let captureSession = AVCaptureSession()
    private let audioOutput = AVCaptureAudioDataOutput()
    private let writingQueue = DispatchQueue(label: "VoiceRaft.AudioCapture")

    private var currentInput: AVCaptureDeviceInput?
    private var assetWriter: AVAssetWriter?
    private var assetWriterInput: AVAssetWriterInput?
    private var outputURL: URL?
    private var isRecording = false

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

        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }

        if let currentInput {
            captureSession.removeInput(currentInput)
            self.currentInput = nil
        }
        captureSession.removeOutput(audioOutput)

        let input = try AVCaptureDeviceInput(device: selectedDevice)
        guard captureSession.canAddInput(input) else {
            throw VoiceRaftError.inputDeviceNotFound
        }
        captureSession.addInput(input)
        currentInput = input

        guard captureSession.canAddOutput(audioOutput) else {
            throw VoiceRaftError.inputDeviceNotFound
        }
        audioOutput.setSampleBufferDelegate(self, queue: writingQueue)
        captureSession.addOutput(audioOutput)

        let writer = try AVAssetWriter(outputURL: targetURL, fileType: .m4a)
        let inputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVEncoderBitRateKey: 128_000,
            AVNumberOfChannelsKey: 1,
        ]
        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: inputSettings)
        writerInput.expectsMediaDataInRealTime = true
        guard writer.canAdd(writerInput) else {
            throw VoiceRaftError.exportFailed("Could not attach an audio writer input.")
        }
        writer.add(writerInput)

        assetWriter = writer
        assetWriterInput = writerInput
        outputURL = targetURL
        isRecording = true

        captureSession.startRunning()
        return targetURL
    }

    func stopRecording() async throws -> URL {
        guard let writerInput = assetWriterInput, let outputURL else {
            throw VoiceRaftError.recordingNotActive
        }

        captureSession.stopRunning()
        isRecording = false

        writerInput.markAsFinished()
        return try await withCheckedThrowingContinuation { continuation in
            assetWriter?.finishWriting { [weak self] in
                let error = self?.assetWriter?.error
                self?.assetWriter = nil
                self?.assetWriterInput = nil
                self?.outputURL = nil

                if let error {
                    continuation.resume(throwing: VoiceRaftError.exportFailed(error.localizedDescription))
                } else {
                    continuation.resume(returning: outputURL)
                }
            }
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard isRecording, let writer = assetWriter, let writerInput = assetWriterInput else { return }
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }

        if writer.status == .unknown {
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            writer.startWriting()
            writer.startSession(atSourceTime: timestamp)
        }

        guard writer.status == .writing else { return }
        if writerInput.isReadyForMoreMediaData {
            writerInput.append(sampleBuffer)
        }
    }

    private func resolveDevice(for mode: MeetingMode, settings: AppSettings) throws -> AVCaptureDevice {
        let devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
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
}
