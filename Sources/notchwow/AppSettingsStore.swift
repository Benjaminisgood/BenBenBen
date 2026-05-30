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

    /// Kept for compatibility with callers that have not migrated to WorkspaceDirectoryStore yet.
    var launchdPath: String {
        AppDefaults.string(forKey: "notchwow.launchdPath", migrating: "notchNotes.launchdPath")
            ?? WorkspacePaths.launchdRoot.path
    }

    private static let triggerModeKey = "notchwow.triggerMode"
    private static let legacyTriggerModeKey = "notchNotes.triggerMode"
    private static let legacyBailianAPIKeyKey = "notchNotes.bailianAPIKey"
    private static let bailianAPIKeyAccount = "bailian-api-key"
    private static let bailianModelKey = "notchwow.bailianModel"
    private static let legacyBailianModelKey = "notchNotes.bailianModel"

    init() {
        let rawMode = AppDefaults.string(forKey: Self.triggerModeKey, migrating: Self.legacyTriggerModeKey)
        triggerMode = rawMode.flatMap(TriggerMode.init(rawValue:)) ?? .hover

        let defaults = UserDefaults.standard
        let keychainAPIKey = KeychainStore.string(for: Self.bailianAPIKeyAccount)
        let legacyAPIKey = defaults.string(forKey: Self.legacyBailianAPIKeyKey)
        bailianAPIKey = keychainAPIKey ?? legacyAPIKey ?? ""
        if keychainAPIKey != nil || (legacyAPIKey.map { KeychainStore.set($0, for: Self.bailianAPIKeyAccount) } == true) {
            defaults.removeObject(forKey: Self.legacyBailianAPIKeyKey)
        }

        bailianModel = AppDefaults.string(forKey: Self.bailianModelKey, migrating: Self.legacyBailianModelKey)
            ?? "qwen3-coder-plus"
    }
}
