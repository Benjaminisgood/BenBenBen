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
    static let integratedBenshellRoot = sourceRoot
        .appendingPathComponent("Scripts", isDirectory: true)
        .appendingPathComponent("benshell", isDirectory: true)
    static let legacyBenshellRoot = homeDirectory
        .appendingPathComponent("Desktop", isDirectory: true)
        .appendingPathComponent("Benshell", isDirectory: true)
    static let runtimeRoot: URL = {
        let manager = FileManager.default
        let runtimeCandidates = [installedRuntimeRoot, bundledRuntimeRoot, repositoryRuntimeRoot]
            .compactMap { $0 }
        for runtimeRoot in runtimeCandidates {
            if manager.fileExists(atPath: runtimeRoot.appendingPathComponent("manifest.json").path),
               manager.fileExists(atPath: runtimeRoot.appendingPathComponent("Benshell/zsh/init.zsh").path) {
                return runtimeRoot
            }
        }
        return repositoryRuntimeRoot
    }()
    static let benshellRoot: URL = {
        let manager = FileManager.default
        let runtimeBenshell = runtimeRoot.appendingPathComponent("Benshell", isDirectory: true)
        if manager.fileExists(atPath: runtimeBenshell.appendingPathComponent("zsh/init.zsh").path) {
            return runtimeBenshell
        }
        if manager.fileExists(atPath: integratedBenshellRoot.appendingPathComponent("zsh/init.zsh").path) {
            return integratedBenshellRoot
        }
        return legacyBenshellRoot
    }()
    static let runtimeCLI = runtimeRoot.appendingPathComponent("bin/benbenben", isDirectory: false)
    static let mcpHelper = runtimeRoot.appendingPathComponent("bin/benbenben-mcp", isDirectory: false)
    static let benshellInitScript = benshellRoot.appendingPathComponent("zsh/init.zsh", isDirectory: false)
    static let condaRoot = homeDirectory.appendingPathComponent("miniforge3", isDirectory: true)
    static let condaExecutable = condaRoot.appendingPathComponent("bin/conda", isDirectory: false)
    static let condaPythonExecutable = condaRoot.appendingPathComponent("bin/python", isDirectory: false)
    static let markdownRoot = root.appendingPathComponent("mds", isDirectory: true)
    static let htmlRoot = root.appendingPathComponent("html", isDirectory: true)
    static let markdownAttachments = markdownRoot.appendingPathComponent("attachments", isDirectory: true)
    static let pythonRoot = root.appendingPathComponent("pys", isDirectory: true)
    static let pythonOutputFile = pythonRoot.appendingPathComponent("transcript.log", isDirectory: false)
    static let shellRoot = root.appendingPathComponent("shs", isDirectory: true)
    static let shellWorkspaceRoot = shellRoot.appendingPathComponent("workspaces", isDirectory: true)
    static let shellWorkspaceInputRoot = shellRoot.appendingPathComponent("workspace-inputs", isDirectory: true)
    static let shellWorkspaceScriptRoot = shellRoot.appendingPathComponent("workspace-scripts", isDirectory: true)
    static let shellInputFile = shellRoot.appendingPathComponent("last-command.txt", isDirectory: false)
    static let shellOutputFile = shellRoot.appendingPathComponent("transcript.txt", isDirectory: false)
    static let appleScriptRoot = root.appendingPathComponent("applescripts", isDirectory: true)
    static let appleScriptInputFile = appleScriptRoot.appendingPathComponent("last-command.txt", isDirectory: false)
    static let appleScriptOutputFile = appleScriptRoot.appendingPathComponent("transcript.log", isDirectory: false)
    static let launchdRoot = root.appendingPathComponent("launchds", isDirectory: true)

    static func ensureDirectories() {
        let manager = FileManager.default
        [
            root,
            markdownRoot,
            htmlRoot,
            markdownAttachments,
            pythonRoot,
            shellRoot,
            shellWorkspaceRoot,
            shellWorkspaceInputRoot,
            shellWorkspaceScriptRoot,
            appleScriptRoot,
            launchdRoot
        ].forEach { url in
            try? manager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    static func sanitizedFileStem(_ rawName: String, fallback: String = "Untitled") -> String {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? fallback : trimmed
        let invalidCharacters = CharacterSet(charactersIn: "/\\:?%*|\"<>")
            .union(.newlines)
            .union(.controlCharacters)

        let cleaned = name
            .components(separatedBy: invalidCharacters)
            .joined(separator: "-")
            .replacingOccurrences(of: #"[\s\t]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: ". ").union(.whitespacesAndNewlines))

        let limited = String(cleaned.prefix(96)).trimmingCharacters(in: .whitespacesAndNewlines)
        return limited.isEmpty ? fallback : limited
    }

    static func uniquedFileURL(
        stem: String,
        fileExtension: String,
        in directory: URL,
        excluding currentURL: URL? = nil
    ) -> URL {
        let manager = FileManager.default
        let cleanStem = sanitizedFileStem(stem)
        let normalizedExtension = fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        var index = 0

        while true {
            let suffix = index == 0 ? "" : " \(index + 1)"
            let filename = "\(cleanStem)\(suffix).\(normalizedExtension)"
            let candidate = directory.appendingPathComponent(filename, isDirectory: false)

            if let currentURL, candidate.standardizedFileURL.path == currentURL.standardizedFileURL.path {
                return candidate
            }

            if !manager.fileExists(atPath: candidate.path) {
                return candidate
            }

            index += 1
        }
    }
}
