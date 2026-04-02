import Foundation
@preconcurrency import AVFoundation

@main
struct AudioInputDiscoveryPolicyCheck {
    static func main() {
        let deviceTypes = AudioInputDiscoveryPolicy.deviceTypes
        guard deviceTypes == [.microphone] else {
            let names = deviceTypes.map(\.rawValue).joined(separator: ", ")
            fputs("Expected microphone-only discovery, found: \(names)\n", stderr)
            exit(1)
        }
    }
}
