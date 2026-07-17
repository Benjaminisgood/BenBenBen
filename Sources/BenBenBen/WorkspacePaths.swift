import Foundation

enum WorkspacePaths {
    static let workspaceRootDefaultsKey = "benbenben.workspaceRoot"
    static let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
    static var root: URL {
        resolvedRoot(
            storedPath: UserDefaults.standard.string(forKey: workspaceRootDefaultsKey),
            homeDirectory: homeDirectory
        )
    }
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

    static var htmlRoot: URL { root.appendingPathComponent("html", isDirectory: true) }
    static var markdownRoot: URL { root.appendingPathComponent("mds", isDirectory: true) }
    static var pythonRoot: URL { root.appendingPathComponent("pys", isDirectory: true) }
    static var shellWorkspaceScriptRoot: URL { root
        .appendingPathComponent("shs", isDirectory: true)
        .appendingPathComponent("workspace-scripts", isDirectory: true) }
    static var appleScriptRoot: URL { root.appendingPathComponent("applescripts", isDirectory: true) }
    static var launchdRoot: URL { root.appendingPathComponent("launchds", isDirectory: true) }

    static func setRoot(_ url: URL?) {
        if let url {
            UserDefaults.standard.set(url.standardizedFileURL.path, forKey: workspaceRootDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: workspaceRootDefaultsKey)
        }
        ensureDirectories()
    }

    static func resolvedRoot(storedPath: String?, homeDirectory: URL) -> URL {
        guard let storedPath,
              !storedPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return homeDirectory.appendingPathComponent("keyoti", isDirectory: true)
        }
        let expanded = (storedPath as NSString).expandingTildeInPath
        let absolute = expanded.hasPrefix("/")
            ? expanded
            : homeDirectory.appendingPathComponent(expanded, isDirectory: true).path
        return URL(fileURLWithPath: absolute, isDirectory: true).standardizedFileURL
    }

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
