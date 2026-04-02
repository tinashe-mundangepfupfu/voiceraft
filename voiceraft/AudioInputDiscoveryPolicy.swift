@preconcurrency import AVFoundation

enum AudioInputDiscoveryPolicy {
    // On macOS, broad external-device discovery can walk CMIO camera extensions and
    // produce noisy HAL/CMIO warnings even when we only need audio capture devices.
    static let deviceTypes: [AVCaptureDevice.DeviceType] = [.microphone]
}
