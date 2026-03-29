import AppKit
import Foundation

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
    private let sidecarManager = SidecarManager()
    private let vaultWriter = ObsidianVaultWriter()
    private let pendingExportStore = PendingExportStore()

    func start(mode: MeetingMode) {
        guard case .idle = state else { return }
        guard let title = promptForMeetingTitle(defaultTitle: mode == .room ? "Room Meeting" : "Online Meeting") else {
            return
        }

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
            } catch {
                presentError(error)
            }
        }
    }

    func stop() {
        guard case let .recording(session, audioURL) = state else { return }
        state = .processing(session, audioURL)

        Task {
            do {
                let audioURL = try await audioCaptureService.stopRecording()
                let response = try await sidecarManager.processMeeting(
                    session: session,
                    audioURL: audioURL,
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
                    try? FileManager.default.removeItem(at: audioURL)
                    notifications.post(
                        title: "VoiceRaft Saved Note",
                        body: "\(session.title) was saved to your Obsidian vault."
                    )
                } catch {
                    let pendingURL = try pendingExportStore.save(markdown: response.markdown, session: session)
                    latestNoteURL = pendingURL
                    notifications.post(
                        title: "VoiceRaft Saved Pending Export",
                        body: "\(session.title) could not be written to Obsidian, so it was saved locally for retry."
                    )
                    presentError(error)
                }
            } catch {
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
        let alert = NSAlert()
        alert.messageText = "VoiceRaft"
        alert.informativeText = error.localizedDescription
        alert.runModal()
        notifications.post(title: "VoiceRaft Error", body: error.localizedDescription)
    }
}
