import AppKit
import Foundation
import OSLog

@MainActor
final class SessionCoordinator {
    var onStateChange: (() -> Void)?
    private(set) var latestNoteURL: URL?
    private(set) var state: CoordinatorState = .idle {
        didSet { onStateChange?() }
    }

    init(settingsStore: SettingsStore, notifications: NotificationPresenter) {
        self.settingsStore = settingsStore
        self.notifications = notifications
    }

    private let settingsStore: SettingsStore
    private let notifications: NotificationPresenter
    private let audioCaptureService = AudioCaptureService()
    private let nativeMeetingProcessor = NativeMeetingProcessor()
    private let vaultWriter = ObsidianVaultWriter()
    private let pendingExportStore = PendingExportStore()
    private let logger = Logger(subsystem: "com.voiceraft.app", category: "session")

    func start(mode: MeetingMode) {
        guard case .idle = state else { return }
        guard let title = promptForMeetingTitle(defaultTitle: mode == .room ? "Room Meeting" : "Online Meeting") else {
            return
        }

        logger.info("session start requested mode=\(mode.rawValue, privacy: .public) title=\(title, privacy: .public)")

        Task {
            do {
                try await audioCaptureService.requestPermissionIfNeeded()
                let session = MeetingSession(
                    id: UUID().uuidString,
                    title: title,
                    mode: mode,
                    startedAt: Date()
                )
                let audioURL = try audioCaptureService.startRecording(session: session, settings: settingsStore.settings)
                state = .recording(session, audioURL)
                logger.info("session recording started path=\(audioURL.path, privacy: .public)")
                notifications.post(
                    title: "VoiceRaft Recording Started",
                    body: "Click the VoiceRaft menu bar icon again to stop \(session.title)."
                )
            } catch {
                logger.error("session start failed error=\(error.localizedDescription, privacy: .public)")
                presentError(error)
            }
        }
    }

    func stop() {
        guard case let .recording(session, audioURL) = state else { return }
        logger.info("session stop requested path=\(audioURL.path, privacy: .public)")
        state = .processing(session, audioURL)

        Task {
            do {
                let recording = try await audioCaptureService.stopRecording()
                logger.info(
                    "session capture complete bytes=\(recording.diagnostics.byteCount) duration=\(recording.diagnostics.durationSeconds, privacy: .public) device=\(recording.diagnostics.inputDeviceName, privacy: .public)"
                )
                let response = try await nativeMeetingProcessor.processMeeting(
                    session: session,
                    audioURL: recording.url,
                    diagnostics: recording.diagnostics,
                    settings: settingsStore.settings,
                    endedAt: Date()
                )

                do {
                    let noteURL = try vaultWriter.write(
                        markdown: response.markdown,
                        session: session,
                        vaultPath: settingsStore.settings.obsidianVaultPath
                    )
                    latestNoteURL = noteURL
                    try? FileManager.default.removeItem(at: recording.url)
                    logger.info("session saved note path=\(noteURL.path, privacy: .public)")
                    notifications.post(
                        title: "VoiceRaft Saved Note",
                        body: "\(session.title) was saved to your Obsidian vault."
                    )
                } catch {
                    let pendingURL = try pendingExportStore.save(markdown: response.markdown, session: session)
                    latestNoteURL = pendingURL
                    logger.error("session vault write failed pendingPath=\(pendingURL.path, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
                    notifications.post(
                        title: "VoiceRaft Saved Pending Export",
                        body: "\(session.title) could not be written to Obsidian, so it was saved locally for retry."
                    )
                    presentError(error)
                }
            } catch {
                logger.error("session processing failed error=\(error.localizedDescription, privacy: .public)")
                presentError(error)
            }

            state = .idle
        }
    }

    func openLatestNote() {
        guard let latestNoteURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([latestNoteURL])
    }

    private func promptForMeetingTitle(defaultTitle: String) -> String? {
        let alert = NSAlert()
        alert.messageText = "Meeting Title"
        alert.informativeText = "VoiceRaft uses this for the note filename and frontmatter."
        alert.addButton(withTitle: "Start")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(string: defaultTitle)
        textField.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        alert.accessoryView = textField

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return nil }
        let value = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? defaultTitle : value
    }

    private func presentError(_ error: Error) {
        logger.error("presenting error=\(error.localizedDescription, privacy: .public)")
        let alert = NSAlert()
        alert.messageText = "VoiceRaft"
        alert.informativeText = error.localizedDescription
        alert.runModal()
        notifications.post(title: "VoiceRaft Error", body: error.localizedDescription)
    }
}
