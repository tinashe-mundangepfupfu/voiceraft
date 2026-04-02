import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    @State private var devices: [AudioInputDeviceOption] = AudioInputDeviceCatalog.availableDevices()

    var body: some View {
        Form {
            Section("Obsidian") {
                HStack {
                    TextField("Vault path", text: binding(\.obsidianVaultPath))
                    Button("Browse") {
                        chooseFolder { path in
                            update(\.obsidianVaultPath, to: path)
                        }
                    }
                }
            }

            Section("LM Studio") {
                TextField("LM Studio base URL", text: binding(\.lmStudioBaseURL))
                TextField("LM Studio model", text: binding(\.lmStudioModel))
            }

            Section("Online Meeting Audio") {
                Picker("Helper input", selection: binding(\.onlineInputDeviceID)) {
                    Text("Default input").tag("")
                    ForEach(devices) { device in
                        Text(device.name).tag(device.id)
                    }
                }
                Button("Refresh Devices") {
                    devices = AudioInputDeviceCatalog.availableDevices()
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 620, height: 320)
    }

    private func binding(_ keyPath: WritableKeyPath<AppSettings, String>) -> Binding<String> {
        Binding(
            get: { store.settings[keyPath: keyPath] },
            set: { update(keyPath, to: $0) }
        )
    }

    private func update<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>, to newValue: Value) {
        var updated = store.settings
        updated[keyPath: keyPath] = newValue
        store.settings = updated
    }

    private func chooseFolder(assign: @escaping (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            assign(url.path)
        }
    }
}

@MainActor
final class SettingsWindowController: NSWindowController {
    init(store: SettingsStore) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 360),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "VoiceRaft Settings"
        window.contentViewController = NSHostingController(rootView: SettingsView(store: store))
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
