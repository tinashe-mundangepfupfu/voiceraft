import AppKit

@MainActor
final class VoiceRaftAppDelegate: NSObject, NSApplicationDelegate {
    private let settingsStore = SettingsStore()
    private let notifications = NotificationPresenter()

    private lazy var coordinator = SessionCoordinator(
        settingsStore: settingsStore,
        notifications: notifications
    )
    private lazy var statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private lazy var settingsWindowController = SettingsWindowController(store: settingsStore)

    private let statusMenu = NSMenu()
    private var roomItem: NSMenuItem!
    private var onlineItem: NSMenuItem!
    private var stopItem: NSMenuItem!
    private var openLatestItem: NSMenuItem!
    private var statusItemMenuTitle: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        notifications.requestAuthorization()
        configureMenu()
        coordinator.onStateChange = { [weak self] in
            self?.refreshMenu()
        }
        refreshMenu()
        runStartupChecks()
    }

    private func configureMenu() {
        statusItem.menu = statusMenu
        statusItem.isVisible = true

        statusItemMenuTitle = NSMenuItem(title: "Idle", action: nil, keyEquivalent: "")
        roomItem = NSMenuItem(title: "Start Room Meeting", action: #selector(startRoomMeeting), keyEquivalent: "")
        roomItem.target = self
        onlineItem = NSMenuItem(title: "Start Online Meeting", action: #selector(startOnlineMeeting), keyEquivalent: "")
        onlineItem.target = self
        stopItem = NSMenuItem(title: "Stop Recording", action: #selector(stopRecording), keyEquivalent: "")
        stopItem.target = self
        openLatestItem = NSMenuItem(title: "Open Latest Note", action: #selector(openLatestNote), keyEquivalent: "")
        openLatestItem.target = self

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self
        let quitItem = NSMenuItem(title: "Quit VoiceRaft", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self

        statusMenu.addItem(statusItemMenuTitle)
        statusMenu.addItem(.separator())
        statusMenu.addItem(roomItem)
        statusMenu.addItem(onlineItem)
        statusMenu.addItem(stopItem)
        statusMenu.addItem(openLatestItem)
        statusMenu.addItem(.separator())
        statusMenu.addItem(settingsItem)
        statusMenu.addItem(quitItem)
    }

    private func refreshMenu() {
        statusItemMenuTitle.title = coordinator.state.detail
        refreshStatusItemButton()

        let canStart: Bool
        switch coordinator.state {
        case .idle:
            canStart = true
        case .recording, .processing:
            canStart = false
        }

        roomItem.isEnabled = canStart
        onlineItem.isEnabled = canStart
        stopItem.isEnabled = {
            if case .recording = coordinator.state { return true }
            return false
        }()
        openLatestItem.isEnabled = coordinator.latestNoteURL != nil
    }

    private func refreshStatusItemButton() {
        guard let button = statusItem.button else { return }

        let appearance = coordinator.state.statusItemAppearance
        let image = VoiceRaftStatusItemIcon.makeImage(named: appearance.symbolName)
            ?? {
                let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
                let image = NSImage(
                    systemSymbolName: appearance.symbolName,
                    accessibilityDescription: coordinator.state.detail
                )?.withSymbolConfiguration(configuration)
                image?.isTemplate = true
                return image
            }()

        button.title = appearance.title
        button.imagePosition = .imageOnly
        button.image = image
        button.contentTintColor = appearance.tintColor
        button.toolTip = coordinator.state.detail
    }

    private func runStartupChecks() {
        let status = VaultStartupCheck.status(for: settingsStore.settings.obsidianVaultPath)
        notifications.post(title: status.title, body: status.message)

        guard status.shouldInterruptLaunch else { return }

        let alert = NSAlert()
        alert.messageText = status.title
        alert.informativeText = status.message
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "OK")

        if alert.runModal() == .alertFirstButtonReturn {
            openSettings()
        }
    }

    @objc private func startRoomMeeting() {
        coordinator.start(mode: .room)
    }

    @objc private func startOnlineMeeting() {
        coordinator.start(mode: .online)
    }

    @objc private func stopRecording() {
        coordinator.stop()
    }

    @objc private func openLatestNote() {
        coordinator.openLatestNote()
    }

    @objc private func openSettings() {
        settingsWindowController.showWindow(nil)
        settingsWindowController.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
