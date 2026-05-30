import Foundation

enum AppDefaults {
    static func string(forKey key: String, migrating legacyKey: String? = nil) -> String? {
        let defaults = UserDefaults.standard
        if let value = defaults.string(forKey: key) {
            return value
        }

        guard let legacyKey, let value = defaults.string(forKey: legacyKey) else {
            return nil
        }

        defaults.set(value, forKey: key)
        defaults.removeObject(forKey: legacyKey)
        return value
    }

    static func set(_ value: String, forKey key: String, removing legacyKey: String? = nil) {
        let defaults = UserDefaults.standard
        defaults.set(value, forKey: key)
        if let legacyKey {
            defaults.removeObject(forKey: legacyKey)
        }
    }
}
