import Foundation
import Security

struct KeychainSecretStore {
    enum StoreError: LocalizedError {
        case invalidStoredSecret
        case unexpectedStatus(operation: String, status: OSStatus)

        var errorDescription: String? {
            switch self {
            case .invalidStoredSecret:
                return "VoiceRaft could not read the saved Claude API key from macOS Keychain."
            case let .unexpectedStatus(operation, status):
                let message = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown Keychain error"
                return "VoiceRaft could not \(operation) the Claude API key in macOS Keychain. \(message)"
            }
        }
    }

    init(
        service: String = Bundle.main.bundleIdentifier ?? "com.voiceraft.app",
        account: String = "anthropic-api-key"
    ) {
        self.service = service
        self.account = account
    }

    private let service: String
    private let account: String

    func loadAnthropicAPIKey() throws -> String? {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(loadQuery as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard
                let data = item as? Data,
                let apiKey = String(data: data, encoding: .utf8)
            else {
                throw StoreError.invalidStoredSecret
            }
            return apiKey
        case errSecItemNotFound:
            return nil
        default:
            throw StoreError.unexpectedStatus(operation: "load", status: status)
        }
    }

    func saveAnthropicAPIKey(_ apiKey: String) throws {
        let payload = Data(apiKey.utf8)
        let addAttributes = [
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: payload,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ] as [String: Any]
        let updateAttributes = [
            kSecValueData as String: payload,
        ] as [String: Any]

        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, updateAttributes as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addQuery = baseQuery
            addQuery.merge(addAttributes) { _, new in new }

            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw StoreError.unexpectedStatus(operation: "save", status: addStatus)
            }
        default:
            throw StoreError.unexpectedStatus(operation: "save", status: updateStatus)
        }
    }

    func deleteAnthropicAPIKey() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw StoreError.unexpectedStatus(operation: "delete", status: status)
        }
    }

    func hasAnthropicAPIKey() throws -> Bool {
        guard let apiKey = try loadAnthropicAPIKey() else {
            return false
        }
        return !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private var loadQuery: [String: Any] {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return query
    }
}
