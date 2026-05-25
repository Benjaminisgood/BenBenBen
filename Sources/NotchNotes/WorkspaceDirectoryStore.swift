import Combine
import AppKit
import Foundation

@MainActor
final class WorkspaceDirectoryStore: ObservableObject {
    @Published var markdownWorkingDirectory: String {
        didSet {
            persistMarkdownWorkingDirectory()
        }
    }

    @Published var shellWorkingDirectory: String {
        didSet {
            persistShellWorkingDirectory()
        }
    }

    @Published var pythonProjectDirectory: String {
        didSet {
            persistPythonProjectDirectory()
        }
    }

    private static let markdownWorkingDirectoryKey = "notchNotes.markdownWorkingDirectory"
    private static let shellWorkingDirectoryKey = "notchNotes.shellWorkingDirectory"
    private static let pythonProjectDirectoryKey = "notchNotes.pythonProjectDirectory"

    init() {
        markdownWorkingDirectory = UserDefaults.standard.string(forKey: Self.markdownWorkingDirectoryKey)
            ?? WorkspacePaths.markdownRoot.path
        let savedShellWorkingDirectory = UserDefaults.standard.string(forKey: Self.shellWorkingDirectoryKey)
        if savedShellWorkingDirectory.map(Self.normalizedPath) == WorkspacePaths.root.standardizedFileURL.path {
            shellWorkingDirectory = WorkspacePaths.shellRoot.path
            UserDefaults.standard.set(Self.normalizedPath(WorkspacePaths.shellRoot.path), forKey: Self.shellWorkingDirectoryKey)
        } else {
            shellWorkingDirectory = savedShellWorkingDirectory ?? WorkspacePaths.shellRoot.path
        }
        pythonProjectDirectory = UserDefaults.standard.string(forKey: Self.pythonProjectDirectoryKey)
            ?? WorkspacePaths.pythonRoot.path
    }

    var markdownWorkingDirectoryURL: URL {
        validatedDirectoryURL(markdownWorkingDirectory, fallback: WorkspacePaths.markdownRoot)
    }

    var shellWorkingDirectoryURL: URL {
        validatedDirectoryURL(shellWorkingDirectory, fallback: WorkspacePaths.shellRoot)
    }

    var pythonProjectDirectoryURL: URL {
        validatedDirectoryURL(pythonProjectDirectory, fallback: WorkspacePaths.pythonRoot)
    }

    func openMarkdownWorkingDirectory() {
        NSWorkspace.shared.open(markdownWorkingDirectoryURL)
    }

    func openMarkdownWorkingDirectoryInVSCode() {
        openInVSCode(markdownWorkingDirectoryURL)
    }

    func openShellWorkingDirectory() {
        NSWorkspace.shared.open(shellWorkingDirectoryURL)
    }

    func openShellWorkingDirectoryInVSCode() {
        openInVSCode(shellWorkingDirectoryURL)
    }

    func openPythonProjectDirectory() {
        NSWorkspace.shared.open(pythonProjectDirectoryURL)
    }

    func openPythonProjectDirectoryInVSCode() {
        openInVSCode(pythonProjectDirectoryURL)
    }

    private func openInVSCode(_ directoryURL: URL) {
        if let applicationURL = Self.visualStudioCodeApplicationURL() {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.open(
                [directoryURL],
                withApplicationAt: applicationURL,
                configuration: configuration
            )
            return
        }

        if let url = Self.visualStudioCodeFileURL(for: directoryURL) {
            NSWorkspace.shared.open(url)
        }
    }

    private static func visualStudioCodeApplicationURL() -> URL? {
        [
            "com.microsoft.VSCode",
            "com.microsoft.VSCodeInsiders"
        ].compactMap { bundleIdentifier in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        }.first
    }

    private static func visualStudioCodeFileURL(for directoryURL: URL) -> URL? {
        var components = URLComponents()
        components.scheme = "vscode"
        components.host = "file"
        components.path = directoryURL.standardizedFileURL.path
        return components.url
    }

    private func persistMarkdownWorkingDirectory() {
        UserDefaults.standard.set(Self.normalizedPath(markdownWorkingDirectory), forKey: Self.markdownWorkingDirectoryKey)
    }

    private func persistShellWorkingDirectory() {
        UserDefaults.standard.set(Self.normalizedPath(shellWorkingDirectory), forKey: Self.shellWorkingDirectoryKey)
    }

    private func persistPythonProjectDirectory() {
        UserDefaults.standard.set(Self.normalizedPath(pythonProjectDirectory), forKey: Self.pythonProjectDirectoryKey)
    }

    private nonisolated func validatedDirectoryURL(_ path: String, fallback: URL) -> URL {
        let normalized = Self.normalizedPath(path)
        guard !normalized.isEmpty else { return fallback }

        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: normalized, isDirectory: &isDirectory),
           isDirectory.boolValue {
            return URL(fileURLWithPath: normalized, isDirectory: true)
        }

        try? FileManager.default.createDirectory(
            atPath: normalized,
            withIntermediateDirectories: true
        )

        if FileManager.default.fileExists(atPath: normalized, isDirectory: &isDirectory),
           isDirectory.boolValue {
            return URL(fileURLWithPath: normalized, isDirectory: true)
        }

        return fallback
    }

    private nonisolated static func normalizedPath(_ path: String) -> String {
        let expandedPath = (path as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expandedPath, isDirectory: true).standardizedFileURL.path
    }
}
