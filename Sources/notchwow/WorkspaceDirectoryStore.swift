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

    @Published var appleScriptDirectory: String {
        didSet {
            persistAppleScriptDirectory()
        }
    }

    @Published var launchdDirectory: String {
        didSet {
            persistLaunchdDirectory()
        }
    }

    @Published var benshellRootDirectory: String {
        didSet {
            persistBenshellRootDirectory()
        }
    }

    @Published var condaRootDirectory: String {
        didSet {
            persistCondaRootDirectory()
        }
    }

    private static let markdownWorkingDirectoryKey = "notchwow.markdownWorkingDirectory"
    private static let shellWorkingDirectoryKey = "notchwow.shellWorkingDirectory"
    private static let pythonProjectDirectoryKey = "notchwow.pythonProjectDirectory"
    private static let appleScriptDirectoryKey = "notchwow.appleScriptDirectory"
    private static let launchdDirectoryKey = "notchwow.launchdPath"
    private static let benshellRootDirectoryKey = "notchwow.benshellRootDirectory"
    private static let condaRootDirectoryKey = "notchwow.condaRootDirectory"
    private static let legacyMarkdownWorkingDirectoryKey = "notchNotes.markdownWorkingDirectory"
    private static let legacyShellWorkingDirectoryKey = "notchNotes.shellWorkingDirectory"
    private static let legacyPythonProjectDirectoryKey = "notchNotes.pythonProjectDirectory"
    private static let legacyAppleScriptDirectoryKey = "notchNotes.appleScriptDirectory"
    private static let legacyLaunchdDirectoryKey = "notchNotes.launchdPath"

    init() {
        markdownWorkingDirectory = AppDefaults.string(forKey: Self.markdownWorkingDirectoryKey, migrating: Self.legacyMarkdownWorkingDirectoryKey)
            ?? WorkspacePaths.markdownRoot.path
        let savedShellWorkingDirectory = AppDefaults.string(forKey: Self.shellWorkingDirectoryKey, migrating: Self.legacyShellWorkingDirectoryKey)
        if savedShellWorkingDirectory.map(Self.normalizedPath) == WorkspacePaths.root.standardizedFileURL.path {
            shellWorkingDirectory = WorkspacePaths.shellRoot.path
            AppDefaults.set(Self.normalizedPath(WorkspacePaths.shellRoot.path), forKey: Self.shellWorkingDirectoryKey, removing: Self.legacyShellWorkingDirectoryKey)
        } else {
            shellWorkingDirectory = savedShellWorkingDirectory ?? WorkspacePaths.shellRoot.path
        }
        pythonProjectDirectory = AppDefaults.string(forKey: Self.pythonProjectDirectoryKey, migrating: Self.legacyPythonProjectDirectoryKey)
            ?? WorkspacePaths.pythonRoot.path
        appleScriptDirectory = AppDefaults.string(forKey: Self.appleScriptDirectoryKey, migrating: Self.legacyAppleScriptDirectoryKey)
            ?? WorkspacePaths.appleScriptRoot.path
        launchdDirectory = AppDefaults.string(forKey: Self.launchdDirectoryKey, migrating: Self.legacyLaunchdDirectoryKey)
            ?? WorkspacePaths.launchdRoot.path
        let savedBenshellRoot = AppDefaults.string(forKey: Self.benshellRootDirectoryKey)
        if savedBenshellRoot.map(Self.normalizedPath) == WorkspacePaths.legacyBenshellRoot.standardizedFileURL.path {
            benshellRootDirectory = WorkspacePaths.benshellRoot.path
            AppDefaults.set(Self.normalizedPath(WorkspacePaths.benshellRoot.path), forKey: Self.benshellRootDirectoryKey)
        } else {
            benshellRootDirectory = savedBenshellRoot ?? WorkspacePaths.benshellRoot.path
        }
        condaRootDirectory = AppDefaults.string(forKey: Self.condaRootDirectoryKey)
            ?? WorkspacePaths.condaRoot.path
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

    var appleScriptDirectoryURL: URL {
        validatedDirectoryURL(appleScriptDirectory, fallback: WorkspacePaths.appleScriptRoot)
    }

    var launchdDirectoryURL: URL {
        validatedDirectoryURL(launchdDirectory, fallback: WorkspacePaths.launchdRoot)
    }

    var benshellRootDirectoryURL: URL {
        configuredDirectoryURL(benshellRootDirectory, fallback: WorkspacePaths.benshellRoot)
    }

    var benshellInitScriptURL: URL {
        benshellRootDirectoryURL.appendingPathComponent("zsh/init.zsh", isDirectory: false)
    }

    var condaRootDirectoryURL: URL {
        configuredDirectoryURL(condaRootDirectory, fallback: WorkspacePaths.condaRoot)
    }

    var condaPythonExecutableURL: URL {
        condaRootDirectoryURL.appendingPathComponent("bin/python", isDirectory: false)
    }

    var benshellIntegrationMessage: String? {
        guard directoryExists(benshellRootDirectoryURL) else {
            return "Benshell root not found"
        }
        guard FileManager.default.fileExists(atPath: benshellInitScriptURL.path) else {
            return "Benshell init script not found"
        }
        return nil
    }

    var condaIntegrationMessage: String? {
        guard directoryExists(condaRootDirectoryURL) else {
            return "Conda root not found"
        }
        return nil
    }

    // MARK: - Finder

    func openMarkdownWorkingDirectory() {
        NSWorkspace.shared.open(markdownWorkingDirectoryURL)
    }

    func openShellWorkingDirectory() {
        NSWorkspace.shared.open(shellWorkingDirectoryURL)
    }

    func openPythonProjectDirectory() {
        NSWorkspace.shared.open(pythonProjectDirectoryURL)
    }

    func openAppleScriptDirectory() {
        NSWorkspace.shared.open(appleScriptDirectoryURL)
    }

    func openLaunchdDirectory() {
        NSWorkspace.shared.open(launchdDirectoryURL)
    }

    func openBenshellRootDirectory() {
        NSWorkspace.shared.open(benshellRootDirectoryURL)
    }

    func openCondaRootDirectory() {
        NSWorkspace.shared.open(condaRootDirectoryURL)
    }

    // MARK: - VS Code

    func openMarkdownWorkingDirectoryInVSCode() {
        openInVSCode(markdownWorkingDirectoryURL)
    }

    func openShellWorkingDirectoryInVSCode() {
        openInVSCode(shellWorkingDirectoryURL)
    }

    func openPythonProjectDirectoryInVSCode() {
        openInVSCode(pythonProjectDirectoryURL)
    }

    func openAppleScriptDirectoryInVSCode() {
        openInVSCode(appleScriptDirectoryURL)
    }

    func openLaunchdDirectoryInVSCode() {
        openInVSCode(launchdDirectoryURL)
    }

    func openBenshellRootDirectoryInVSCode() {
        openInVSCode(benshellRootDirectoryURL)
    }

    func openCondaRootDirectoryInVSCode() {
        openInVSCode(condaRootDirectoryURL)
    }

    func openFileInVSCode(_ fileURL: URL) {
        openInVSCode(fileURL)
    }

    // MARK: - Terminal

    func openMarkdownWorkingDirectoryInTerminal() {
        openInTerminal(markdownWorkingDirectoryURL)
    }

    func openShellWorkingDirectoryInTerminal() {
        openInTerminal(shellWorkingDirectoryURL)
    }

    func openPythonProjectDirectoryInTerminal() {
        openInTerminal(pythonProjectDirectoryURL)
    }

    func openAppleScriptDirectoryInTerminal() {
        openInTerminal(appleScriptDirectoryURL)
    }

    func openLaunchdDirectoryInTerminal() {
        openInTerminal(launchdDirectoryURL)
    }

    func openBenshellRootDirectoryInTerminal() {
        openInTerminal(benshellRootDirectoryURL)
    }

    func openCondaRootDirectoryInTerminal() {
        openInTerminal(condaRootDirectoryURL)
    }

    // MARK: - Private

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

    private func openInTerminal(_ directoryURL: URL) {
        _ = TerminalAppBridge.openNewWindow(workingDirectory: directoryURL.path)
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
        AppDefaults.set(Self.normalizedPath(markdownWorkingDirectory), forKey: Self.markdownWorkingDirectoryKey, removing: Self.legacyMarkdownWorkingDirectoryKey)
    }

    private func persistShellWorkingDirectory() {
        AppDefaults.set(Self.normalizedPath(shellWorkingDirectory), forKey: Self.shellWorkingDirectoryKey, removing: Self.legacyShellWorkingDirectoryKey)
    }

    private func persistPythonProjectDirectory() {
        AppDefaults.set(Self.normalizedPath(pythonProjectDirectory), forKey: Self.pythonProjectDirectoryKey, removing: Self.legacyPythonProjectDirectoryKey)
    }

    private func persistAppleScriptDirectory() {
        AppDefaults.set(Self.normalizedPath(appleScriptDirectory), forKey: Self.appleScriptDirectoryKey, removing: Self.legacyAppleScriptDirectoryKey)
    }

    private func persistLaunchdDirectory() {
        AppDefaults.set(Self.normalizedPath(launchdDirectory), forKey: Self.launchdDirectoryKey, removing: Self.legacyLaunchdDirectoryKey)
    }

    private func persistBenshellRootDirectory() {
        AppDefaults.set(Self.normalizedPath(benshellRootDirectory), forKey: Self.benshellRootDirectoryKey)
    }

    private func persistCondaRootDirectory() {
        AppDefaults.set(Self.normalizedPath(condaRootDirectory), forKey: Self.condaRootDirectoryKey)
    }

    private nonisolated func configuredDirectoryURL(_ path: String, fallback: URL) -> URL {
        let normalized = Self.normalizedPath(path)
        guard !normalized.isEmpty else { return fallback }
        return URL(fileURLWithPath: normalized, isDirectory: true)
    }

    private nonisolated func directoryExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
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
