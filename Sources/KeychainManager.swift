import Foundation
import Security

/// Manages connection configs and API keys in iOS Keychain
final class KeychainManager {
    static let shared = KeychainManager()
    private init() {}

    private let service = AppConfig.keychainService

    // MARK: - Save

    func save(_ config: ConnectionConfig) throws {
        let data = try JSONEncoder().encode(config)
        try save(key: "active_config", data: data)
    }

    func saveAll(_ configs: [ConnectionConfig]) throws {
        let data = try JSONEncoder().encode(configs)
        try save(key: "all_configs", data: data)
    }

    // MARK: - Load

    func loadActive() -> ConnectionConfig? {
        guard let data = load(key: "active_config") else { return nil }
        return try? JSONDecoder().decode(ConnectionConfig.self, from: data)
    }

    func loadAll() -> [ConnectionConfig] {
        guard let data = load(key: "all_configs") else { return [] }
        return (try? JSONDecoder().decode([ConnectionConfig].self, from: data)) ?? []
    }

    // MARK: - Delete

    func deleteActive() {
        delete(key: "active_config")
    }

    func deleteAll() {
        delete(key: "active_config")
        delete(key: "all_configs")
    }

    // MARK: - Private Keychain Operations

    private func save(key: String, data: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]

        // Delete existing
        SecItemDelete(query as CFDictionary)

        // Add new
        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status: status)
        }
    }

    private func load(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return data
    }

    private func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Errors

enum KeychainError: Error {
    case saveFailed(status: OSStatus)
    case loadFailed(status: OSStatus)
    case deleteFailed(status: OSStatus)
}