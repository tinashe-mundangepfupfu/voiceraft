import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var claudeSettingsModel: ClaudeSettingsModel
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

            Section("Notes") {
                Picker("Notes Provider", selection: binding(\.notesProvider)) {
                    ForEach(NotesProvider.allCases, id: \.self) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }

                Text("VoiceRaft shows provider-specific note generation settings for the selected provider.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if store.settings.notesProvider == .lmStudio {
                Section("LM Studio") {
                    TextField("LM Studio base URL", text: binding(\.lmStudioBaseURL))
                    TextField("LM Studio model", text: binding(\.lmStudioModel))
                }
            } else {
                Section("Claude") {
                    HStack(alignment: .top) {
                        SecureField("Anthropic API key", text: $claudeSettingsModel.apiKeyDraft)
                        Button(claudeSettingsModel.hasSavedAPIKey ? "Update API Key" : "Save API Key") {
                            saveClaudeAPIKey()
                        }
                        .disabled(claudeSettingsModel.apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button("Clear Key") {
                            clearClaudeAPIKey()
                        }
                        .disabled(!claudeSettingsModel.hasSavedAPIKey)
                    }

                    if let apiKeyStatusError = claudeSettingsModel.apiKeyStatusError {
                        Text(apiKeyStatusError.localizedDescription)
                            .foregroundStyle(.red)
                    }

                    HStack {
                        Picker("Claude model", selection: claudeModelSelectionBinding()) {
                            ForEach(claudeSettingsModel.displayedModels, id: \.self) { model in
                                if model == claudeSettingsModel.unavailableSavedModel {
                                    Text("\(model) (Unavailable)").tag(model)
                                } else {
                                    Text(model).tag(model)
                                }
                            }
                        }
                        .disabled(!claudeSettingsModel.canSelectClaudeModels && claudeSettingsModel.unavailableSavedModel == nil)

                        Button("Refresh Models") {
                            refreshClaudeModels()
                        }
                        .disabled(!claudeSettingsModel.hasSavedAPIKey || claudeSettingsModel.isLoadingModels)
                    }

                    if claudeSettingsModel.isLoadingModels {
                        ProgressView("Loading Claude models…")
                    } else if let modelFetchError = claudeSettingsModel.modelFetchError {
                        Text(modelFetchError.localizedDescription)
                            .foregroundStyle(.red)
                    } else if claudeSettingsModel.hasSavedAPIKey && claudeSettingsModel.availableModels.isEmpty {
                        Text("No Claude models are available for the saved API key.")
                            .foregroundStyle(.secondary)
                    }

                    if let unavailableSavedModel = claudeSettingsModel.unavailableSavedModel {
                        Text("Selected Claude model \"\(unavailableSavedModel)\" is unavailable. Choose a current Claude model to continue.")
                            .foregroundStyle(.orange)
                    }
                }
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
        .frame(width: 620, height: 420)
        .onAppear {
            refreshClaudeModelsIfNeeded()
        }
        .onChange(of: store.settings.notesProvider) { _, provider in
            guard provider == .claude else { return }
            refreshClaudeModelsIfNeeded()
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { store.settings[keyPath: keyPath] },
            set: { update(keyPath, to: $0) }
        )
    }

    private func claudeModelSelectionBinding() -> Binding<String> {
        let storedClaudeModel = binding(\.claudeModel)
        return Binding(
            get: { storedClaudeModel.wrappedValue },
            set: { newValue in
                do {
                    try claudeSettingsModel.selectClaudeModel(newValue)
                } catch {}
            }
        )
    }

    private func update<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>, to newValue: Value) {
        var updated = store.settings
        updated[keyPath: keyPath] = newValue
        store.settings = updated
    }

    private func saveClaudeAPIKey() {
        Task {
            try? await claudeSettingsModel.saveAPIKey()
        }
    }

    private func refreshClaudeModels() {
        Task {
            try? await claudeSettingsModel.refreshModels()
        }
    }

    private func clearClaudeAPIKey() {
        try? claudeSettingsModel.clearAPIKey()
    }

    private func refreshClaudeModelsIfNeeded() {
        guard store.settings.notesProvider == .claude else { return }
        guard claudeSettingsModel.hasSavedAPIKey else { return }
        guard !claudeSettingsModel.isLoadingModels else { return }
        guard claudeSettingsModel.availableModels.isEmpty else { return }
        guard claudeSettingsModel.modelFetchError == nil else { return }
        refreshClaudeModels()
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
    private let claudeSettingsModel: ClaudeSettingsModel

    init(store: SettingsStore) {
        claudeSettingsModel = ClaudeSettingsModel(settingsStore: store)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 460),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "VoiceRaft Settings"
        window.contentViewController = NSHostingController(
            rootView: SettingsView(store: store, claudeSettingsModel: claudeSettingsModel)
        )
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
