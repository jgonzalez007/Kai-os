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

    // The Keychain can stop to ask the person for permission, and that stops the caller until they answer.
    // So each key is read once per launch and remembered. `cachedApiKey` never touches the Keychain.
    private static let cacheLock = NSLock()
    private static var cache: [String: String?] = [:]

    private static func remember(_ key: String?, for provider: String) {
        cacheLock.lock(); cache[provider] = .some(key); cacheLock.unlock()
    }

    /// What this launch already knows about a key: nil when the Keychain has not been read yet, and
    /// `.some(nil)` when it was read and there is none. Never blocks.
    public static func cachedApiKey(for provider: String) -> String?? {
        cacheLock.lock(); defer { cacheLock.unlock() }
        return cache[provider]
    }

    /// Forgets what this launch remembered about a key, so the next read goes to the Keychain again.
    public static func forgetCachedKey(for provider: String) {
        cacheLock.lock(); cache[provider] = nil; cacheLock.unlock()
    }

    /// Returns the stored key for a provider ("openai", "anthropic"), or nil.
    public static func apiKey(for provider: String) -> String? {
        if let known = cachedApiKey(for: provider) { return known }
        let key = readApiKey(for: provider)
        remember(key, for: provider)
        return key
    }

    private static func readApiKey(for provider: String) -> String? {
        #if DEBUG
        // Page snapshots must never stop on a Keychain permission dialog.
        if ProcessInfo.processInfo.environment["KAI_NO_KEYCHAIN"] != nil { return nil }
        #endif
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
        if status == errSecSuccess { remember(key, for: provider); return true }
        guard status == errSecItemNotFound else { return false }
        var add = baseQuery(provider)
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let added = SecItemAdd(add as CFDictionary, nil) == errSecSuccess
        if added { remember(key, for: provider) }
        return added
    }

    @discardableResult
    public static func deleteApiKey(for provider: String) -> Bool {
        let status = SecItemDelete(baseQuery(provider) as CFDictionary)
        let gone = status == errSecSuccess || status == errSecItemNotFound
        if gone { remember(nil, for: provider) }
        return gone
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
