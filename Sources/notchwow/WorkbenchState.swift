import Combine
import Foundation

enum WorkbenchMode: String, CaseIterable, Identifiable {
    case markdown
    case terminal
    case python
    case appleScript
    case tasks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .markdown: return "MD"
        case .terminal: return "Shell"
        case .python: return "Py"
        case .appleScript: return "AS"
        case .tasks: return "Jobs"
        }
    }

    var systemImage: String {
        switch self {
        case .markdown: return "doc.richtext"
        case .terminal: return "dollarsign.square"
        case .python: return "chevron.left.forwardslash.chevron.right"
        case .appleScript: return "command.square"
        case .tasks: return "clock.arrow.2.circlepath"
        }
    }
}

@MainActor
final class WorkbenchState: ObservableObject {
    @Published var activeMode: WorkbenchMode = .markdown

    func select(_ mode: WorkbenchMode) {
        activeMode = mode
    }

    func selectNext() {
        move(by: 1)
    }

    func selectPrevious() {
        move(by: -1)
    }

    private func move(by offset: Int) {
        let modes = WorkbenchMode.allCases
        guard let currentIndex = modes.firstIndex(of: activeMode) else {
            activeMode = .markdown
            return
        }

        let nextIndex = (currentIndex + offset + modes.count) % modes.count
        activeMode = modes[nextIndex]
    }
}
