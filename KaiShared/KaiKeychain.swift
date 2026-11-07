import Foundation
import Security

/// Stores cloud-provider API keys in the macOS Keychain.
///
/// Keys used to live in plaintext in UserDefaults (`kai.<provider>.apiKey`).
/// `apiKey(for:)` migrates any legacy value into the Keychain on first read
/// and removes it from UserDefaults.
public enum KaiKeychain {
    public static let service = "ai.kai.apikeys"

    private static func legacyDefaultsKey(_ provider: String) -> String {
        "kai.\(provider).apiKey"
    }

    private static func baseQuery(_ provider: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider
        ]
    }

    /// Returns the stored key for a provider ("openai", "anthropic"), or nil.
    public static func apiKey(for provider: String) -> String? {
        var query = baseQuery(provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
           let data = item as? Data,
           let key = String(data: data, encoding: .utf8),
           !key.isEmpty {
            return key
        }
        return migrateLegacyKey(for: provider)
    }

    /// Saves a key. An empty string deletes it.
    @discardableResult
    public static func setApiKey(_ key: String, for provider: String) -> Bool {
        UserDefaults.standard.removeObject(forKey: legacyDefaultsKey(provider))
        guard !key.isEmpty else { return deleteApiKey(for: provider) }
        let data = Data(key.utf8)
        let status = SecItemUpdate(
            baseQuery(provider) as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var add = baseQuery(provider)
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    public static func deleteApiKey(for provider: String) -> Bool {
        let status = SecItemDelete(baseQuery(provider) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    public static func hasApiKey(for provider: String) -> Bool {
        apiKey(for: provider) != nil
    }

    /// Moves a plaintext UserDefaults key into the Keychain. The plaintext copy
    /// is removed only after the Keychain write succeeds.
    private static func migrateLegacyKey(for provider: String) -> String? {
        let defaultsKey = legacyDefaultsKey(provider)
        guard let legacy = UserDefaults.standard.string(forKey: defaultsKey), !legacy.isEmpty else {
            return nil
        }
        var add = baseQuery(provider)
        add[kSecValueData as String] = Data(legacy.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        if status == errSecSuccess || status == errSecDuplicateItem {
            UserDefaults.standard.removeObject(forKey: defaultsKey)
        }
        return legacy
    }
}
