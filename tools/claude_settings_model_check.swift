import Foundation

private struct CheckFailure: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

private actor ControlledFetcher {
    private var callCount = 0
    private var waiters: [Int: [CheckedContinuation<Void, Never>]] = [:]
    private var continuations: [Int: CheckedContinuation<[String], Error>] = [:]

    func fetch(apiKey _: String) async throws -> [String] {
        callCount += 1
        let currentCall = callCount

        if let resumptions = waiters.removeValue(forKey: callCount) {
            for continuation in resumptions {
                continuation.resume()
            }
        }

        return try await withCheckedThrowingContinuation { continuation in
            continuations[currentCall] = continuation
        }
    }

    func waitUntilCallCount(_ expectedCount: Int) async {
        if callCount >= expectedCount {
            return
        }

        await withCheckedContinuation { continuation in
            waiters[expectedCount, default: []].append(continuation)
        }
    }

    func resumeCall(_ call: Int, with result: Result<[String], Error>) throws {
        guard let continuation = continuations.removeValue(forKey: call) else {
            throw CheckFailure(message: "fetch continuation missing for call \(call)")
        }

        switch result {
        case let .success(models):
            continuation.resume(returning: models)
        case let .failure(error):
            continuation.resume(throwing: error)
        }
    }
}

private actor ResponseQueue {
    private var responses: [Result<[String], Error>]

    init(_ responses: [Result<[String], Error>]) {
        self.responses = responses
    }

    func next() throws -> [String] {
        guard !responses.isEmpty else {
            throw CheckFailure(message: "missing fetch response")
        }

        return try responses.removeFirst().get()
    }
}

private final class FakeSecretStore: ClaudeSecretStoring {
    var hasKeyResult: Result<Bool, Error>
    var loadResult: Result<String?, Error>
    var saveResult: Result<Void, Error> = .success(())
    var deleteResult: Result<Void, Error> = .success(())

    init(
        hasKeyResult: Result<Bool, Error>,
        loadResult: Result<String?, Error>
    ) {
        self.hasKeyResult = hasKeyResult
        self.loadResult = loadResult
    }

    func loadAnthropicAPIKey() throws -> String? {
        try loadResult.get()
    }

    func saveAnthropicAPIKey(_: String) throws {
        try saveResult.get()
    }

    func deleteAnthropicAPIKey() throws {
        try deleteResult.get()
    }

    func hasAnthropicAPIKey() throws -> Bool {
        try hasKeyResult.get()
    }
}

@MainActor
@main
struct ClaudeSettingsModelCheck {
    static func main() async throws {
        try await assertInitSurfacesKeychainFailures()
        try await assertClearInvalidatesInFlightRefresh()
        try await assertConcurrentRefreshesKeepLoadingStateConsistent()
        try await assertRefreshSurfacesKeychainReadFailures()
        try await assertFailedRefreshClearsStaleModels()
    }

    private static func assertInitSurfacesKeychainFailures() async throws {
        let store = makeSettingsStore()
        let secretStore = FakeSecretStore(
            hasKeyResult: .failure(CheckFailure(message: "keychain unavailable")),
            loadResult: .success(nil)
        )

        let model = ClaudeSettingsModel(
            settingsStore: store,
            secretStore: secretStore,
            modelFetcher: { _ in [] }
        )

        try assert(!model.hasSavedAPIKey, "init should not report a saved key on keychain failure")
        try assert(
            model.apiKeyStatusError?.localizedDescription.contains("keychain unavailable") == true,
            "init should surface keychain status failures"
        )
    }

    private static func assertClearInvalidatesInFlightRefresh() async throws {
        let store = makeSettingsStore()
        let fetcher = ControlledFetcher()
        let secretStore = FakeSecretStore(
            hasKeyResult: .success(true),
            loadResult: .success("test-key")
        )

        let model = ClaudeSettingsModel(
            settingsStore: store,
            secretStore: secretStore,
            modelFetcher: { apiKey in
                try await fetcher.fetch(apiKey: apiKey)
            }
        )

        let refreshTask = Task { try await model.refreshModels() }
        await fetcher.waitUntilCallCount(1)

        try model.clearAPIKey()
        try await fetcher.resumeCall(1, with: .success(["claude-after-clear"]))
        try? await refreshTask.value

        try assert(model.availableModels.isEmpty, "clear should prevent stale refresh results from repopulating models")
        try assert(!model.isLoadingModels, "clear should leave loading state idle")
        try assert(!model.hasSavedAPIKey, "clear should remove saved-key status")
    }

    private static func assertConcurrentRefreshesKeepLoadingStateConsistent() async throws {
        let store = makeSettingsStore()
        let fetcher = ControlledFetcher()
        let secretStore = FakeSecretStore(
            hasKeyResult: .success(true),
            loadResult: .success("test-key")
        )

        let model = ClaudeSettingsModel(
            settingsStore: store,
            secretStore: secretStore,
            modelFetcher: { apiKey in
                try await fetcher.fetch(apiKey: apiKey)
            }
        )

        let firstRefresh = Task { try await model.refreshModels() }
        await fetcher.waitUntilCallCount(1)
        let secondRefresh = Task { try await model.refreshModels() }
        await fetcher.waitUntilCallCount(2)

        try await fetcher.resumeCall(2, with: .success(["claude-latest"]))
        try await secondRefresh.value

        try assert(model.isLoadingModels, "a still-running older refresh should keep loading state active")
        try assert(model.availableModels == ["claude-latest"], "latest refresh should win model selection")

        try await fetcher.resumeCall(1, with: .success(["claude-stale"]))
        try? await firstRefresh.value

        try assert(!model.isLoadingModels, "loading state should clear after all refreshes finish")
        try assert(model.availableModels == ["claude-latest"], "stale refresh completion should not overwrite newer results")
    }

    private static func assertFailedRefreshClearsStaleModels() async throws {
        let store = makeSettingsStore()
        let secretStore = FakeSecretStore(
            hasKeyResult: .success(true),
            loadResult: .success("test-key")
        )
        let responses = ResponseQueue([
            .success(["claude-valid"]),
            .failure(CheckFailure(message: "bad key"))
        ])

        let model = ClaudeSettingsModel(
            settingsStore: store,
            secretStore: secretStore,
            modelFetcher: { _ in try await responses.next() }
        )

        try await model.refreshModels()
        try assert(model.availableModels == ["claude-valid"], "initial refresh should populate available models")

        do {
            try await model.refreshModels()
            throw CheckFailure(message: "refresh should fail when fetcher throws")
        } catch {}

        try assert(model.availableModels.isEmpty, "failed refresh should clear stale models")
        try assert(!model.canSelectClaudeModels, "failed refresh should leave Claude model selection disabled")
    }

    private static func assertRefreshSurfacesKeychainReadFailures() async throws {
        let store = makeSettingsStore()
        let secretStore = FakeSecretStore(
            hasKeyResult: .success(true),
            loadResult: .failure(KeychainSecretStore.StoreError.invalidStoredSecret)
        )

        let model = ClaudeSettingsModel(
            settingsStore: store,
            secretStore: secretStore,
            modelFetcher: { _ in
                throw CheckFailure(message: "model fetcher should not be called when keychain read fails")
            }
        )

        do {
            try await model.refreshModels()
            throw CheckFailure(message: "refresh should fail when the keychain read fails")
        } catch let error as VoiceRaftError {
            switch error {
            case let .claudeAPIKeyAccessFailed(message):
                try assert(message.contains("macOS Keychain"), "refresh should wrap keychain read failures as key access errors")
            default:
                throw CheckFailure(message: "refresh should surface a Claude API key access error, got \(error)")
            }
        }

        switch model.apiKeyStatusError {
        case let .claudeAPIKeyAccessFailed(message):
            try assert(message.contains("macOS Keychain"), "refresh should publish the keychain read failure in apiKeyStatusError")
        default:
            throw CheckFailure(message: "apiKeyStatusError should capture the keychain read failure")
        }

        switch model.modelFetchError {
        case let .claudeAPIKeyAccessFailed(message):
            try assert(message.contains("macOS Keychain"), "refresh should not remap keychain read failures into model fetch failures")
        default:
            throw CheckFailure(message: "modelFetchError should surface the keychain access failure for refresh flows")
        }
    }

    private static func makeSettingsStore() -> SettingsStore {
        let suiteName = "ClaudeSettingsModelCheck.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return SettingsStore(userDefaults: defaults)
    }

    private static func assert(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else {
            throw CheckFailure(message: message)
        }
    }
}
