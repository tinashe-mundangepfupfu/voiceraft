import Combine
import Foundation
import VoiceRaftCore

@MainActor
final class ClaudeSettingsModel: ObservableObject {
    typealias ModelFetcher = @Sendable (String) async throws -> [String]

    @Published var apiKeyDraft = ""
    @Published private(set) var hasSavedAPIKey: Bool
    @Published private(set) var availableModels: [String] = []
    @Published private(set) var unavailableSavedModel: String?
    @Published private(set) var isLoadingModels = false
    @Published private(set) var modelFetchError: VoiceRaftError?

    init(
        settingsStore: SettingsStore,
        secretStore: KeychainSecretStore = KeychainSecretStore(),
        modelFetcher: @escaping ModelFetcher = liveClaudeModelFetcher(apiKey:)
    ) {
        self.settingsStore = settingsStore
        self.secretStore = secretStore
        self.modelFetcher = modelFetcher
        hasSavedAPIKey = (try? secretStore.hasAnthropicAPIKey()) ?? false
        refreshUnavailableSelection(using: settingsStore.settings.claudeModel)
    }

    private let settingsStore: SettingsStore
    private let secretStore: KeychainSecretStore
    private let modelFetcher: ModelFetcher

    var displayedModels: [String] {
        guard let unavailableSavedModel else {
            return availableModels
        }

        return [unavailableSavedModel] + availableModels.filter { $0 != unavailableSavedModel }
    }

    var canSelectClaudeModels: Bool {
        hasSavedAPIKey && !isLoadingModels && !availableModels.isEmpty
    }

    func refreshSavedKeyStatus() {
        hasSavedAPIKey = (try? secretStore.hasAnthropicAPIKey()) ?? false
    }

    func loadSavedAPIKey() throws -> String {
        guard
            let apiKey = try secretStore.loadAnthropicAPIKey()?.trimmingCharacters(in: .whitespacesAndNewlines),
            !apiKey.isEmpty
        else {
            hasSavedAPIKey = false
            throw VoiceRaftError.missingClaudeAPIKey
        }

        hasSavedAPIKey = true
        return apiKey
    }

    func saveAPIKey() async throws {
        let trimmedKey = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw VoiceRaftError.missingClaudeAPIKey
        }

        try secretStore.saveAnthropicAPIKey(trimmedKey)
        apiKeyDraft = ""
        hasSavedAPIKey = true
        try await refreshModels()
    }

    func clearAPIKey() throws {
        try secretStore.deleteAnthropicAPIKey()
        apiKeyDraft = ""
        hasSavedAPIKey = false
        availableModels = []
        modelFetchError = nil
        isLoadingModels = false
        refreshUnavailableSelection(using: settingsStore.settings.claudeModel)
    }

    func refreshModels() async throws {
        let apiKey = try loadSavedAPIKey()

        isLoadingModels = true
        modelFetchError = nil
        defer { isLoadingModels = false }

        do {
            let models = try await modelFetcher(apiKey)
            availableModels = models

            if settingsStore.settings.claudeModel.isEmpty, let firstModel = models.first {
                updateClaudeModel(to: firstModel)
            }

            refreshUnavailableSelection(using: settingsStore.settings.claudeModel)
        } catch let error as VoiceRaftError {
            modelFetchError = error
            refreshUnavailableSelection(using: settingsStore.settings.claudeModel)
            throw error
        } catch {
            let wrappedError = VoiceRaftError.claudeModelFetchFailed(error.localizedDescription)
            modelFetchError = wrappedError
            refreshUnavailableSelection(using: settingsStore.settings.claudeModel)
            throw wrappedError
        }
    }

    func selectClaudeModel(_ model: String) throws {
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedModel == settingsStore.settings.claudeModel {
            refreshUnavailableSelection(using: trimmedModel)
            return
        }

        guard trimmedModel.isEmpty || availableModels.contains(trimmedModel) else {
            throw VoiceRaftError.invalidClaudeModel(trimmedModel)
        }

        updateClaudeModel(to: trimmedModel)
        modelFetchError = nil
    }

    private func refreshUnavailableSelection(using savedModel: String) {
        let trimmedModel = savedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else {
            unavailableSavedModel = nil
            return
        }

        unavailableSavedModel = availableModels.contains(trimmedModel) ? nil : trimmedModel
    }

    private func updateClaudeModel(to model: String) {
        var updatedSettings = settingsStore.settings
        updatedSettings.claudeModel = model
        settingsStore.settings = updatedSettings
        refreshUnavailableSelection(using: model)
    }

    private static func liveClaudeModelFetcher(apiKey: String) async throws -> [String] {
        do {
            return try await AnthropicModelsService(apiKey: apiKey).listModels()
        } catch {
            throw VoiceRaftError.claudeModelFetchFailed(error.localizedDescription)
        }
    }
}
