import Foundation

enum WorkspacePaths {
    static let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
    static let root = homeDirectory.appendingPathComponent("keyoti", isDirectory: true)
    static let sourceRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static let installedRuntimeRoot = homeDirectory
        .appendingPathComponent("Library/Application Support/BenBenBen/Runtime/current", isDirectory: true)
    static let bundledRuntimeRoot = Bundle.main.resourceURL?
        .appendingPathComponent("Runtime", isDirectory: true)
    static let repositoryRuntimeRoot = sourceRoot
        .appendingPathComponent("Runtime", isDirectory: true)
    static let runtimeRoot: URL = {
        let candidates = [bundledRuntimeRoot, repositoryRuntimeRoot, installedRuntimeRoot].compactMap { $0 }
        return candidates.first { candidate in
            FileManager.default.fileExists(atPath: candidate.appendingPathComponent("manifest.json").path)
                && FileManager.default.fileExists(
                    atPath: candidate.appendingPathComponent("Benshell/zsh/init.zsh").path
                )
        } ?? repositoryRuntimeRoot
    }()
    static let mcpHelper = runtimeRoot.appendingPathComponent("bin/benbenben-mcp", isDirectory: false)

    static let htmlRoot = root.appendingPathComponent("html", isDirectory: true)
    static let markdownRoot = root.appendingPathComponent("mds", isDirectory: true)
    static let pythonRoot = root.appendingPathComponent("pys", isDirectory: true)
    static let shellWorkspaceScriptRoot = root
        .appendingPathComponent("shs", isDirectory: true)
        .appendingPathComponent("workspace-scripts", isDirectory: true)
    static let appleScriptRoot = root.appendingPathComponent("applescripts", isDirectory: true)
    static let launchdRoot = root.appendingPathComponent("launchds", isDirectory: true)

    static func ensureDirectories() {
        let manager = FileManager.default
        [
            root,
            htmlRoot,
            markdownRoot,
            pythonRoot,
            shellWorkspaceScriptRoot,
            appleScriptRoot,
            launchdRoot
        ].forEach { url in
            try? manager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}
