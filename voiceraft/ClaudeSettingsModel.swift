import Combine
import Foundation
import VoiceRaftCore

@MainActor
final class ClaudeSettingsModel: ObservableObject {
    typealias ModelFetcher = @Sendable (String) async throws -> [String]

    @Published var apiKeyDraft = ""
    @Published private(set) var hasSavedAPIKey = false
    @Published private(set) var apiKeyStatusError: VoiceRaftError?
    @Published private(set) var availableModels: [String] = []
    @Published private(set) var unavailableSavedModel: String?
    @Published private(set) var isLoadingModels = false
    @Published private(set) var modelFetchError: VoiceRaftError?

    init(
        settingsStore: SettingsStore,
        secretStore: any ClaudeSecretStoring = KeychainSecretStore(),
        modelFetcher: @escaping ModelFetcher = { apiKey in
            try await ClaudeSettingsModel.liveClaudeModelFetcher(apiKey: apiKey)
        }
    ) {
        self.settingsStore = settingsStore
        self.secretStore = secretStore
        self.modelFetcher = modelFetcher
        refreshSavedKeyStatus()
        refreshUnavailableSelection(using: settingsStore.settings.claudeModel)
    }

    private let settingsStore: SettingsStore
    private let secretStore: any ClaudeSecretStoring
    private let modelFetcher: ModelFetcher
    private var nextRefreshToken = 0
    private var latestRefreshToken: Int?
    private var activeRefreshTokens: Set<Int> = []

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
        do {
            hasSavedAPIKey = try secretStore.hasAnthropicAPIKey()
            apiKeyStatusError = nil
        } catch {
            hasSavedAPIKey = false
            apiKeyStatusError = wrapKeychainError(error)
        }
    }

    func loadSavedAPIKey() throws -> String {
        do {
            guard
                let apiKey = try secretStore.loadAnthropicAPIKey()?.trimmingCharacters(in: .whitespacesAndNewlines),
                !apiKey.isEmpty
            else {
                hasSavedAPIKey = false
                apiKeyStatusError = nil
                throw VoiceRaftError.missingClaudeAPIKey
            }

            hasSavedAPIKey = true
            apiKeyStatusError = nil
            return apiKey
        } catch let error as VoiceRaftError {
            if case .missingClaudeAPIKey = error {
                throw error
            }
            let wrappedError = wrapKeychainError(error)
            hasSavedAPIKey = false
            apiKeyStatusError = wrappedError
            throw wrappedError
        }
    }

    func saveAPIKey() async throws {
        let trimmedKey = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw VoiceRaftError.missingClaudeAPIKey
        }

        do {
            try secretStore.saveAnthropicAPIKey(trimmedKey)
        } catch {
            let wrappedError = wrapKeychainError(error)
            apiKeyStatusError = wrappedError
            throw wrappedError
        }

        apiKeyDraft = ""
        hasSavedAPIKey = true
        apiKeyStatusError = nil
        try await refreshModels()
    }

    func clearAPIKey() throws {
        do {
            try secretStore.deleteAnthropicAPIKey()
        } catch {
            let wrappedError = wrapKeychainError(error)
            apiKeyStatusError = wrappedError
            throw wrappedError
        }

        invalidateRefreshes()
        apiKeyDraft = ""
        hasSavedAPIKey = false
        apiKeyStatusError = nil
        modelFetchError = nil
        refreshUnavailableSelection(using: settingsStore.settings.claudeModel)
    }

    func refreshModels() async throws {
        let refreshToken = beginRefresh()
        defer { endRefresh(refreshToken) }

        do {
            let apiKey = try loadSavedAPIKey()
            let models = try await modelFetcher(apiKey)

            guard isLatestRefresh(refreshToken) else {
                return
            }

            availableModels = models

            if settingsStore.settings.claudeModel.isEmpty, let firstModel = models.first {
                updateClaudeModel(to: firstModel)
            }

            refreshUnavailableSelection(using: settingsStore.settings.claudeModel)
        } catch let error as VoiceRaftError {
            guard isLatestRefresh(refreshToken) else {
                return
            }

            availableModels = []
            modelFetchError = error
            refreshUnavailableSelection(using: settingsStore.settings.claudeModel)
            throw error
        } catch {
            guard isLatestRefresh(refreshToken) else {
                return
            }

            let wrappedError = VoiceRaftError.claudeModelFetchFailed(error.localizedDescription)
            availableModels = []
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

    private func beginRefresh() -> Int {
        let refreshToken = nextRefreshToken
        nextRefreshToken += 1
        latestRefreshToken = refreshToken
        activeRefreshTokens.insert(refreshToken)
        isLoadingModels = true
        modelFetchError = nil
        availableModels = []
        refreshUnavailableSelection(using: settingsStore.settings.claudeModel)
        return refreshToken
    }

    private func endRefresh(_ refreshToken: Int) {
        activeRefreshTokens.remove(refreshToken)
        isLoadingModels = !activeRefreshTokens.isEmpty
    }

    private func invalidateRefreshes() {
        latestRefreshToken = nil
        activeRefreshTokens.removeAll()
        isLoadingModels = false
        availableModels = []
    }

    private func isLatestRefresh(_ refreshToken: Int) -> Bool {
        latestRefreshToken == refreshToken
    }

    private func wrapKeychainError(_ error: Error) -> VoiceRaftError {
        if let voiceRaftError = error as? VoiceRaftError {
            return voiceRaftError
        }

        return VoiceRaftError.claudeAPIKeyAccessFailed(error.localizedDescription)
    }

    private static func liveClaudeModelFetcher(apiKey: String) async throws -> [String] {
        do {
            return try await AnthropicModelsService(apiKey: apiKey).listModels()
        } catch {
            throw VoiceRaftError.claudeModelFetchFailed(error.localizedDescription)
        }
    }
}
