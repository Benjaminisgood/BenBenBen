import Foundation

enum WorkspacePaths {
    static let root = URL(fileURLWithPath: "/Users/ben/keyoti", isDirectory: true)
    static let benshellRoot = URL(fileURLWithPath: "/Users/ben/Desktop/Benshell", isDirectory: true)
    static let benshellInitScript = benshellRoot.appendingPathComponent("zsh/init.zsh", isDirectory: false)
    static let condaRoot = URL(fileURLWithPath: "/Users/ben/miniforge3", isDirectory: true)
    static let condaExecutable = condaRoot.appendingPathComponent("bin/conda", isDirectory: false)
    static let markdownRoot = root.appendingPathComponent("mds", isDirectory: true)
    static let markdownAttachments = markdownRoot.appendingPathComponent("attachments", isDirectory: true)
    static let pythonRoot = root.appendingPathComponent("pys", isDirectory: true)
    static let pythonOutputFile = pythonRoot.appendingPathComponent("transcript.log", isDirectory: false)
    static let shellRoot = root.appendingPathComponent("shs", isDirectory: true)
    static let shellWorkspaceRoot = shellRoot.appendingPathComponent("workspaces", isDirectory: true)
    static let shellWorkspaceInputRoot = shellRoot.appendingPathComponent("workspace-inputs", isDirectory: true)
    static let shellWorkspaceScriptRoot = shellRoot.appendingPathComponent("workspace-scripts", isDirectory: true)
    static let shellInputFile = shellRoot.appendingPathComponent("last-command.txt", isDirectory: false)
    static let shellOutputFile = shellRoot.appendingPathComponent("transcript.txt", isDirectory: false)
    static let launchdRoot = root.appendingPathComponent("launchds", isDirectory: true)

    static func ensureDirectories() {
        let manager = FileManager.default
        [
            root,
            markdownRoot,
            markdownAttachments,
            pythonRoot,
            shellRoot,
            shellWorkspaceRoot,
            shellWorkspaceInputRoot,
            shellWorkspaceScriptRoot,
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
