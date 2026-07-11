import Foundation

enum AppDefaults {
    static func string(forKey key: String, migrating legacyKey: String? = nil) -> String? {
        string(forKey: key, migrating: legacyKey.map { [$0] } ?? [])
    }

    static func string(forKey key: String, migrating legacyKeys: [String]) -> String? {
        let defaults = UserDefaults.standard
        if let value = defaults.string(forKey: key) {
            return value
        }

        for candidateKey in [key] + legacyKeys {
            if let value = defaults.string(forKey: candidateKey) {
                defaults.set(value, forKey: key)
                legacyKeys.forEach(defaults.removeObject(forKey:))
                return value
            }

            for suite in legacySuites {
                if let value = suite.string(forKey: candidateKey) {
                    defaults.set(value, forKey: key)
                    return value
                }
            }
        }
        return nil
    }

    static func set(_ value: String, forKey key: String, removing legacyKey: String? = nil) {
        set(value, forKey: key, removing: legacyKey.map { [$0] } ?? [])
    }

    static func set(_ value: String, forKey key: String, removing legacyKeys: [String]) {
        let defaults = UserDefaults.standard
        defaults.set(value, forKey: key)
        legacyKeys.forEach(defaults.removeObject(forKey:))
    }

    static func dictionary(forKey key: String, migrating legacyKeys: [String] = []) -> [String: Any]? {
        let defaults = UserDefaults.standard
        if let value = defaults.dictionary(forKey: key) {
            return value
        }

        for candidateKey in [key] + legacyKeys {
            for suite in legacySuites {
                if let value = suite.dictionary(forKey: candidateKey) {
                    defaults.set(value, forKey: key)
                    return value
                }
            }
        }
        return nil
    }

    private static var legacySuites: [UserDefaults] {
        [
            "io.github.benjaminisgood.notchwow.dev",
            "io.github.benjaminisgood.notchwow"
        ].compactMap(UserDefaults.init(suiteName:))
    }
}
