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
            UserDefaults.standard.set(triggerMode.rawValue, forKey: Self.triggerModeKey)
        }
    }

    @Published var bailianAPIKey: String {
        didSet {
            UserDefaults.standard.set(bailianAPIKey, forKey: Self.bailianAPIKeyKey)
        }
    }

    @Published var bailianModel: String {
        didSet {
            UserDefaults.standard.set(bailianModel, forKey: Self.bailianModelKey)
        }
    }

    /// Kept for backward compatibility — reads from the same UserDefaults key as WorkspaceDirectoryStore.launchdDirectory
    var launchdPath: String {
        UserDefaults.standard.string(forKey: "notchNotes.launchdPath")
            ?? WorkspacePaths.launchdRoot.path
    }

    private static let triggerModeKey = "notchNotes.triggerMode"
    private static let bailianAPIKeyKey = "notchNotes.bailianAPIKey"
    private static let bailianModelKey = "notchNotes.bailianModel"

    init() {
        let rawMode = UserDefaults.standard.string(forKey: Self.triggerModeKey)
        triggerMode = rawMode.flatMap(TriggerMode.init(rawValue:)) ?? .hover
        bailianAPIKey = UserDefaults.standard.string(forKey: Self.bailianAPIKeyKey) ?? ""
        bailianModel = UserDefaults.standard.string(forKey: Self.bailianModelKey) ?? "qwen3-coder-plus"
    }
}
