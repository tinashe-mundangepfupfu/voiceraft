@preconcurrency import AVFoundation

protocol CaptureSessionLifecycle {
    func beginConfiguration()
    func commitConfiguration()
    func startRunning()
}

extension AVCaptureSession: CaptureSessionLifecycle {}

enum CaptureSessionStartup {
    static func configureAndStart<Session: CaptureSessionLifecycle>(
        _ session: Session,
        configure: () throws -> Void
    ) throws {
        session.beginConfiguration()
        do {
            try configure()
            session.commitConfiguration()
        } catch {
            session.commitConfiguration()
            throw error
        }

        // AVFoundation requires startRunning() after configuration is committed.
        session.startRunning()
    }
}
