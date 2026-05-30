import Combine
import Foundation

struct ShellWorkspace: Identifiable, Equatable {
    let id: String
    let title: String
    let transcriptURL: URL
    let inputURL: URL
    let scriptURL: URL
    let modifiedAt: Date

    var detail: String {
        transcriptURL.path
    }
}

@MainActor
final class ShellWorkspaceStore: ObservableObject {
    @Published private(set) var workspaces: [ShellWorkspace] = []
    @Published private(set) var activeWorkspaceID: String
    @Published private(set) var scriptText: String
    @Published var searchQuery = ""

    private static let activeWorkspaceKey = "notchwow.activeShellWorkspace"
    private static let legacyActiveWorkspaceKey = "notchNotes.activeShellWorkspace"

    init() {
        WorkspacePaths.ensureDirectories()
        Self.migrateLegacyTranscriptIfNeeded()
        let loadedWorkspaces = Self.availableWorkspaces()

        let savedID = AppDefaults.string(forKey: Self.activeWorkspaceKey, migrating: Self.legacyActiveWorkspaceKey)
        let activeID = savedID.flatMap { saved in
            loadedWorkspaces.first(where: { $0.id == saved })?.id
        } ?? loadedWorkspaces[0].id

        workspaces = loadedWorkspaces
        activeWorkspaceID = activeID
        scriptText = Self.loadScriptText(for: loadedWorkspaces.first { $0.id == activeID } ?? loadedWorkspaces[0])
    }

    var activeWorkspace: ShellWorkspace {
        workspaces.first { $0.id == activeWorkspaceID } ?? workspaces[0]
    }

    var filteredWorkspaces: [ShellWorkspace] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return workspaces }

        return workspaces.filter { workspace in
            workspace.title.localizedCaseInsensitiveContains(query)
                || workspace.detail.localizedCaseInsensitiveContains(query)
                || workspace.scriptURL.lastPathComponent.localizedCaseInsensitiveContains(query)
        }
    }

    func addWorkspace() {
        let workspace = Self.createWorkspace(stem: "shell")
        workspaces.append(workspace)
        sortWorkspaces()
        selectWorkspace(workspace.id)
        searchQuery = ""
    }

    func selectWorkspace(_ id: String) {
        guard let workspace = workspaces.first(where: { $0.id == id }) else { return }
        activeWorkspaceID = id
        scriptText = Self.loadScriptText(for: workspace)
        AppDefaults.set(id, forKey: Self.activeWorkspaceKey, removing: Self.legacyActiveWorkspaceKey)
    }

    func updateScriptText(_ nextText: String) {
        scriptText = nextText
        Self.writeScriptText(nextText, for: activeWorkspace)
    }

    func syncFromDisk() {
        let loaded = Self.availableWorkspaces()
        workspaces = loaded
        if !workspaces.contains(where: { $0.id == activeWorkspaceID }) {
            activeWorkspaceID = workspaces[0].id
            AppDefaults.set(activeWorkspaceID, forKey: Self.activeWorkspaceKey, removing: Self.legacyActiveWorkspaceKey)
        }
        scriptText = Self.loadScriptText(for: activeWorkspace)
    }

    private func sortWorkspaces() {
        workspaces.sort {
            if $0.modifiedAt != $1.modifiedAt {
                return $0.modifiedAt > $1.modifiedAt
            }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    private nonisolated static func loadWorkspaces() -> [ShellWorkspace] {
        let manager = FileManager.default
        try? manager.createDirectory(at: WorkspacePaths.shellWorkspaceRoot, withIntermediateDirectories: true)
        try? manager.createDirectory(at: WorkspacePaths.shellWorkspaceInputRoot, withIntermediateDirectories: true)
        try? manager.createDirectory(at: WorkspacePaths.shellWorkspaceScriptRoot, withIntermediateDirectories: true)

        let logURLs = (try? manager.contentsOfDirectory(
            at: WorkspacePaths.shellWorkspaceRoot,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        let logStems = Set(
            logURLs
                .filter { $0.pathExtension.lowercased() == "log" }
                .map { $0.deletingPathExtension().lastPathComponent }
        )

        // Discover orphan .sh scripts that have no corresponding .log workspace
        let scriptURLs = (try? manager.contentsOfDirectory(
            at: WorkspacePaths.shellWorkspaceScriptRoot,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        for scriptURL in scriptURLs where scriptURL.pathExtension.lowercased() == "sh" {
            let stem = scriptURL.deletingPathExtension().lastPathComponent
            guard !logStems.contains(stem) else { continue }
            let logURL = WorkspacePaths.shellWorkspaceRoot
                .appendingPathComponent(stem, isDirectory: false)
                .appendingPathExtension("log")
            try? "".write(to: logURL, atomically: true, encoding: .utf8)
        }

        // Reload after creating any new log files
        let allLogURLs = (try? manager.contentsOfDirectory(
            at: WorkspacePaths.shellWorkspaceRoot,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return allLogURLs
            .filter { $0.pathExtension.lowercased() == "log" }
            .map(workspace)
            .sorted {
                if $0.modifiedAt != $1.modifiedAt {
                    return $0.modifiedAt > $1.modifiedAt
                }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
    }

    private nonisolated static func availableWorkspaces() -> [ShellWorkspace] {
        let loadedWorkspaces = loadWorkspaces()
        guard loadedWorkspaces.isEmpty else { return loadedWorkspaces }

        return [createWorkspace(stem: "shell")]
    }

    private nonisolated static func createWorkspace(stem: String) -> ShellWorkspace {
        let transcriptURL = WorkspacePaths.uniquedFileURL(
            stem: stem,
            fileExtension: "log",
            in: WorkspacePaths.shellWorkspaceRoot
        )
        try? "".write(to: transcriptURL, atomically: true, encoding: .utf8)
        return workspace(from: transcriptURL)
    }

    private nonisolated static func workspace(from transcriptURL: URL) -> ShellWorkspace {
        let values = try? transcriptURL.resourceValues(forKeys: [.contentModificationDateKey])
        let stem = transcriptURL.deletingPathExtension().lastPathComponent
        let inputURL = WorkspacePaths.shellWorkspaceInputRoot
            .appendingPathComponent(stem, isDirectory: false)
            .appendingPathExtension("input")
        let scriptURL = WorkspacePaths.shellWorkspaceScriptRoot
            .appendingPathComponent(stem, isDirectory: false)
            .appendingPathExtension("sh")
        ensureFileExists(at: inputURL, defaultText: "")
        ensureFileExists(at: scriptURL, defaultText: "")

        return ShellWorkspace(
            id: transcriptURL.path,
            title: stem,
            transcriptURL: transcriptURL,
            inputURL: inputURL,
            scriptURL: scriptURL,
            modifiedAt: values?.contentModificationDate ?? Date()
        )
    }

    private nonisolated static func loadScriptText(for workspace: ShellWorkspace) -> String {
        (try? String(contentsOf: workspace.scriptURL, encoding: .utf8))
            ?? (try? String(contentsOf: workspace.scriptURL))
            ?? ""
    }

    private nonisolated static func writeScriptText(_ text: String, for workspace: ShellWorkspace) {
        try? FileManager.default.createDirectory(
            at: workspace.scriptURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? text.write(to: workspace.scriptURL, atomically: true, encoding: .utf8)
    }

    private nonisolated static func ensureFileExists(at url: URL, defaultText: String) {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? defaultText.write(to: url, atomically: true, encoding: .utf8)
    }

    private nonisolated static func migrateLegacyTranscriptIfNeeded() {
        let manager = FileManager.default
        let defaultURL = WorkspacePaths.shellWorkspaceRoot
            .appendingPathComponent("default", isDirectory: false)
            .appendingPathExtension("log")
        guard !manager.fileExists(atPath: defaultURL.path) else { return }
        guard manager.fileExists(atPath: WorkspacePaths.shellOutputFile.path) else { return }

        try? manager.copyItem(at: WorkspacePaths.shellOutputFile, to: defaultURL)

        let inputURL = WorkspacePaths.shellWorkspaceInputRoot
            .appendingPathComponent("default", isDirectory: false)
            .appendingPathExtension("input")
        if manager.fileExists(atPath: WorkspacePaths.shellInputFile.path) {
            try? manager.copyItem(at: WorkspacePaths.shellInputFile, to: inputURL)
        }

        let scriptURL = WorkspacePaths.shellWorkspaceScriptRoot
            .appendingPathComponent("default", isDirectory: false)
            .appendingPathExtension("sh")
        ensureFileExists(at: scriptURL, defaultText: "")
    }
}
