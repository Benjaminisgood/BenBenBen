import Foundation
import Security

enum KeychainStore {
    private static let service = "io.github.benjaminisgood.benbenben"
    private static let legacyServices = [
        "io.github.benjaminisgood.notchwow",
        "io.github.benjaminisgood.notchwow.dev"
    ]

    static func string(for account: String) -> String? {
        string(for: account, service: service)
    }

    /// Reads an old ACL-protected item only after an explicit user action. A
    /// differently signed replacement app may trigger a macOS Keychain prompt,
    /// so this must never run synchronously during application startup.
    static func migrateLegacyString(for account: String) -> String? {
        for legacyService in legacyServices {
            if let value = string(for: account, service: legacyService) {
                _ = set(value, for: account)
                return value
            }
        }
        return nil
    }

    private static func string(for account: String, service: String) -> String? {
        var query = baseQuery(for: account, service: service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func set(_ value: String, for account: String) -> Bool {
        guard !value.isEmpty else {
            return remove(account)
        }

        let data = Data(value.utf8)
        let query = baseQuery(for: account)
        let update = [kSecValueData as String: data]

        switch SecItemUpdate(query as CFDictionary, update as CFDictionary) {
        case errSecSuccess:
            return true
        case errSecItemNotFound:
            var item = query
            item[kSecValueData as String] = data
            return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
        default:
            return false
        }
    }

    @discardableResult
    static func remove(_ account: String) -> Bool {
        let status = SecItemDelete(baseQuery(for: account) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private static func baseQuery(for account: String, service: String = service) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
