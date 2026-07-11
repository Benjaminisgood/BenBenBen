import Combine
import Foundation

enum TriggerMode: String, CaseIterable, Identifiable {
    case hover
    case click

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hover:
            return "Hover"
        case .click:
            return "Click"
        }
    }

    var systemImage: String {
        switch self {
        case .hover:
            return "cursorarrow.motionlines"
        case .click:
            return "cursorarrow.click.2"
        }
    }
}

@MainActor
final class AppSettingsStore: ObservableObject {
    @Published var triggerMode: TriggerMode {
        didSet {
            AppDefaults.set(triggerMode.rawValue, forKey: Self.triggerModeKey, removing: Self.legacyTriggerModeKey)
        }
    }

    @Published var bailianAPIKey: String {
        didSet {
            KeychainStore.set(bailianAPIKey, for: Self.bailianAPIKeyAccount)
        }
    }

    @Published var bailianModel: String {
        didSet {
            AppDefaults.set(bailianModel, forKey: Self.bailianModelKey, removing: Self.legacyBailianModelKey)
        }
    }

    @Published private(set) var isMigratingLegacyKeychain = false
    @Published private(set) var legacyKeychainMigrationMessage: String?

    /// Kept for compatibility with callers that have not migrated to WorkspaceDirectoryStore yet.
    var launchdPath: String {
        AppDefaults.string(
            forKey: "benbenben.launchdPath",
            migrating: ["notchwow.launchdPath", "notchNotes.launchdPath"]
        )
            ?? WorkspacePaths.launchdRoot.path
    }

    private static let triggerModeKey = "benbenben.triggerMode"
    private static let legacyTriggerModeKey = "notchwow.triggerMode"
    private static let legacyBailianAPIKeyKey = "notchNotes.bailianAPIKey"
    private static let bailianAPIKeyAccount = "bailian-api-key"
    private static let bailianModelKey = "benbenben.bailianModel"
    private static let legacyBailianModelKey = "notchwow.bailianModel"

    init() {
        let rawMode = AppDefaults.string(
            forKey: Self.triggerModeKey,
            migrating: [Self.legacyTriggerModeKey, "notchNotes.triggerMode"]
        )
        triggerMode = rawMode.flatMap(TriggerMode.init(rawValue:)) ?? .hover

        let defaults = UserDefaults.standard
        let keychainAPIKey = KeychainStore.string(for: Self.bailianAPIKeyAccount)
        let legacyAPIKey = defaults.string(forKey: Self.legacyBailianAPIKeyKey)
        bailianAPIKey = keychainAPIKey ?? legacyAPIKey ?? ""
        if keychainAPIKey != nil || (legacyAPIKey.map { KeychainStore.set($0, for: Self.bailianAPIKeyAccount) } == true) {
            defaults.removeObject(forKey: Self.legacyBailianAPIKeyKey)
        }

        bailianModel = AppDefaults.string(
            forKey: Self.bailianModelKey,
            migrating: [Self.legacyBailianModelKey, "notchNotes.bailianModel"]
        )
            ?? "qwen3-coder-plus"
    }

    func migrateLegacyBailianKeychain() {
        guard !isMigratingLegacyKeychain else { return }
        isMigratingLegacyKeychain = true
        legacyKeychainMigrationMessage = nil
        let account = Self.bailianAPIKeyAccount

        Task { [weak self] in
            let value = await Task.detached(priority: .userInitiated) {
                KeychainStore.migrateLegacyString(for: account)
            }.value
            guard let self else { return }
            self.isMigratingLegacyKeychain = false
            if let value, !value.isEmpty {
                self.bailianAPIKey = value
                self.legacyKeychainMigrationMessage = "Imported the legacy key without deleting it."
            } else {
                self.legacyKeychainMigrationMessage = "No readable legacy key was found."
            }
        }
    }
}
