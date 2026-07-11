import Foundation

enum PersonalWorkspaceKind: String, CaseIterable, Codable, Sendable {
    case markdown
    case shell
    case python
    case appleScript
    case launchd
}

struct PersonalWorkspaceLocation: Identifiable, Hashable, Sendable {
    let kind: PersonalWorkspaceKind
    let url: URL

    var id: PersonalWorkspaceKind { kind }
}

/// The single source of truth for BenBenBen's personal workspace locations.
///
/// The root is injectable so previews and tests never need to read or mutate the
/// user's real `~/keyoti` tree.
struct WorkspaceRegistry: Hashable, Sendable {
    let root: URL

    init(root: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("keyoti", isDirectory: true)) {
        self.root = root.standardizedFileURL
    }

    var markdownRoot: URL {
        root.appendingPathComponent("mds", isDirectory: true)
    }

    var shellScriptRoot: URL {
        root
            .appendingPathComponent("shs", isDirectory: true)
            .appendingPathComponent("workspace-scripts", isDirectory: true)
    }

    var pythonRoot: URL {
        root.appendingPathComponent("pys", isDirectory: true)
    }

    var appleScriptRoot: URL {
        root.appendingPathComponent("applescripts", isDirectory: true)
    }

    var launchdRoot: URL {
        root.appendingPathComponent("launchds", isDirectory: true)
    }

    var inboxURL: URL {
        markdownRoot.appendingPathComponent("Inbox.md", isDirectory: false)
    }

    var indexedLocations: [PersonalWorkspaceLocation] {
        [
            PersonalWorkspaceLocation(kind: .markdown, url: markdownRoot),
            PersonalWorkspaceLocation(kind: .shell, url: shellScriptRoot),
            PersonalWorkspaceLocation(kind: .python, url: pythonRoot),
            PersonalWorkspaceLocation(kind: .appleScript, url: appleScriptRoot),
            PersonalWorkspaceLocation(kind: .launchd, url: launchdRoot)
        ]
    }
}
