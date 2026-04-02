import Foundation

private struct CheckFailure: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

private final class RecordingSession: CaptureSessionLifecycle {
    var calls: [String] = []

    func beginConfiguration() {
        calls.append("beginConfiguration")
    }

    func commitConfiguration() {
        calls.append("commitConfiguration")
    }

    func startRunning() {
        calls.append("startRunning")
    }
}

@main
struct CaptureSessionStartupCheck {
    static func main() throws {
        try commitOccursBeforeStartRunning()
        try failedConfigurationStillCommits()
    }

    private static func commitOccursBeforeStartRunning() throws {
        let session = RecordingSession()
        try CaptureSessionStartup.configureAndStart(session) {
            session.calls.append("configure")
        }

        try assertCalls(
            session.calls,
            equal: ["beginConfiguration", "configure", "commitConfiguration", "startRunning"],
            context: "expected commit before startRunning"
        )
    }

    private static func failedConfigurationStillCommits() throws {
        let session = RecordingSession()

        do {
            try CaptureSessionStartup.configureAndStart(session) {
                session.calls.append("configure")
                throw CheckFailure(message: "expected configuration failure")
            }
            throw CheckFailure(message: "expected configureAndStart to rethrow configuration failure")
        } catch let error as CheckFailure {
            guard error.message == "expected configuration failure" else {
                throw error
            }
        }

        try assertCalls(
            session.calls,
            equal: ["beginConfiguration", "configure", "commitConfiguration"],
            context: "expected failed configuration to commit but not start"
        )
    }

    private static func assertCalls(_ actual: [String], equal expected: [String], context: String) throws {
        guard actual == expected else {
            throw CheckFailure(
                message: "\(context): expected \(expected.joined(separator: ", ")), found \(actual.joined(separator: ", "))"
            )
        }
    }
}
