import Combine
import Foundation

enum ScriptDocumentKind: String, CaseIterable, Identifiable {
    case shell
    case appleScript

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shell: return "Shell"
        case .appleScript: return "AppleScript"
        }
    }

    var shortTitle: String {
        switch self {
        case .shell: return "sh"
        case .appleScript: return "as"
        }
    }

    var systemImage: String {
        switch self {
        case .shell: return "dollarsign.square"
        case .appleScript: return "command.square"
        }
    }

    var scriptLanguage: ScriptLanguage {
        switch self {
        case .shell: return .shell
        case .appleScript: return .appleScript
        }
    }
}

@MainActor
final class ScriptsModuleState: ObservableObject {
    @Published var activeKind: ScriptDocumentKind = .shell
    @Published var scriptSearchQuery = ""
    @Published var commandSearchQuery = ""
    @Published var selectedCommandID: String?
    @Published var lastLaunchStatus: String?

    func selectKind(_ kind: ScriptDocumentKind) {
        activeKind = kind
    }

    func selectCommand(_ command: ShellCommandItem) {
        selectedCommandID = command.id
        commandSearchQuery = command.command
    }

    func selectedCommand(from commands: [ShellCommandItem]) -> ShellCommandItem? {
        if let selectedCommandID,
           let selected = commands.first(where: { $0.id == selectedCommandID }) {
            return selected
        }
        return commands.first
    }
}
