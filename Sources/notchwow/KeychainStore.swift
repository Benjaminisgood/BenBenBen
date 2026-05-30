import Foundation
import Security

enum KeychainStore {
    private static let service = "io.github.benjaminisgood.notchwow"

    static func string(for account: String) -> String? {
        var query = baseQuery(for: account)
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

    private static func baseQuery(for account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
