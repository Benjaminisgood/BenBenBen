import Combine
import Foundation

enum ShellCommandKind: String {
    case benshell
    case shellScript
    case appleScript
}

struct ShellCommandItem: Identifiable, Equatable {
    let id: String
    let group: String
    let title: String
    let command: String
    let summary: String
    let systemImage: String
    let kind: ShellCommandKind
}

struct ShellToolkit: Identifiable, Equatable {
    let id: String
    let name: String
    let systemImage: String
}

@MainActor
final class ShellCommandStore: ObservableObject {
    @Published private(set) var commands: [ShellCommandItem] = []
    @Published private(set) var selectedToolkitName: String

    private static let selectedToolkitKey = "notchwow.selectedShellToolkit"
    private static let legacySelectedToolkitKey = "notchNotes.selectedShellToolkit"
    private var benshellRootURL: URL

    init(benshellRootURL: URL = WorkspacePaths.benshellRoot) {
        self.benshellRootURL = benshellRootURL.standardizedFileURL
        selectedToolkitName = AppDefaults.string(forKey: Self.selectedToolkitKey, migrating: Self.legacySelectedToolkitKey)
            ?? "benshell"
        refresh()
    }

    var toolkits: [ShellToolkit] {
        let grouped = Dictionary(grouping: commands, by: \.group)
        return grouped.keys
            .sorted { lhs, rhs in
                Self.toolkitSortKey(lhs).localizedStandardCompare(Self.toolkitSortKey(rhs)) == .orderedAscending
            }
            .map { group in
                ShellToolkit(id: group, name: group, systemImage: Self.systemImage(for: group))
            }
    }

    var selectedToolkit: ShellToolkit {
        toolkits.first { $0.name == selectedToolkitName }
            ?? toolkits.first
            ?? ShellToolkit(id: "benshell", name: "benshell", systemImage: "terminal")
    }

    func refresh() {
        commands = Self.loadBenshellScriptCommands(benshellRootURL: benshellRootURL)
            + Self.loadLocalShellScriptCommands()
            + Self.loadAppleScriptCommands()
        if !toolkits.contains(where: { $0.name == selectedToolkitName }),
           let firstToolkit = toolkits.first {
            selectToolkit(firstToolkit.name)
        }
    }

    func useBenshellRoot(_ rootURL: URL) {
        let nextURL = rootURL.standardizedFileURL
        guard benshellRootURL.path != nextURL.path else { return }
        benshellRootURL = nextURL
        refresh()
    }

    func selectToolkit(_ name: String) {
        selectedToolkitName = name
        AppDefaults.set(name, forKey: Self.selectedToolkitKey, removing: Self.legacySelectedToolkitKey)
    }

    func filteredCommands(matching query: String) -> [ShellCommandItem] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }

        return commands.filter { item in
            item.title.localizedCaseInsensitiveContains(trimmedQuery)
                || item.command.localizedCaseInsensitiveContains(trimmedQuery)
                || item.summary.localizedCaseInsensitiveContains(trimmedQuery)
                || item.group.localizedCaseInsensitiveContains(trimmedQuery)
        }
    }

    func filteredCommands(in toolkitName: String, matching query: String) -> [ShellCommandItem] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return commands.filter { $0.group == toolkitName }
        }

        return commands.filter { item in
            item.group == toolkitName
                && (
                    item.title.localizedCaseInsensitiveContains(trimmedQuery)
                    || item.command.localizedCaseInsensitiveContains(trimmedQuery)
                    || item.summary.localizedCaseInsensitiveContains(trimmedQuery)
                )
        }
    }

    private nonisolated static func loadBenshellScriptCommands(benshellRootURL: URL) -> [ShellCommandItem] {
        let scriptsRoot = benshellRootURL.appendingPathComponent("scripts", isDirectory: true)
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: scriptsRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .isExecutableKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls
            .filter { url in
                guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isExecutableKey]) else {
                    return false
                }

                return values.isDirectory != true && values.isExecutable == true
            }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .flatMap(parseScriptCommands)
    }

    private nonisolated static func parseScriptCommands(from url: URL) -> [ShellCommandItem] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }

        let scriptName = url.lastPathComponent
        var items: [ShellCommandItem] = []
        var isInCommandsBlock = false

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed == "Commands:" || trimmed == "Controller commands:" {
                isInCommandsBlock = true
                continue
            }

            guard isInCommandsBlock else { continue }

            if trimmed.isEmpty {
                break
            }

            guard line.first?.isWhitespace == true,
                  let parsed = parseCommandLine(trimmed) else {
                break
            }

            let command = normalizedCommand(scriptName: scriptName, signature: parsed.signature)
            items.append(ShellCommandItem(
                id: "script-\(scriptName)-\(parsed.signature)",
                group: scriptName,
                title: "\(scriptName) \(parsed.signature)",
                command: command,
                summary: parsed.summary,
                systemImage: systemImage(for: scriptName),
                kind: .benshell
            ))
        }

        if items.isEmpty {
            items.append(ShellCommandItem(
                id: "script-\(scriptName)-help",
                group: scriptName,
                title: "\(scriptName) help",
                command: "\(scriptName) help",
                summary: "Show available commands",
                systemImage: systemImage(for: scriptName),
                kind: .benshell
            ))
        }

        return items
    }

    private nonisolated static func parseCommandLine(_ line: String) -> (signature: String, summary: String)? {
        let normalized = line.replacingOccurrences(
            of: #"\s{2,}"#,
            with: "\t",
            options: .regularExpression
        )
        let parts = normalized.split(separator: "\t", maxSplits: 1).map(String.init)
        guard let signature = parts.first, !signature.isEmpty else { return nil }

        return (
            signature: signature,
            summary: parts.count > 1 ? parts[1] : ""
        )
    }

    private nonisolated static func normalizedCommand(scriptName: String, signature: String) -> String {
        let runnableSignature = signature
            .replacingOccurrences(of: #"\s+\[[^\]]+\]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+\.\.\."#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if runnableSignature.isEmpty {
            return scriptName
        }

        return "\(scriptName) \(runnableSignature)"
    }

    private nonisolated static func loadLocalShellScriptCommands() -> [ShellCommandItem] {
        loadRunnableFiles(
            in: WorkspacePaths.shellWorkspaceScriptRoot,
            fileExtension: "sh",
            group: "Shell scripts",
            systemImage: "dollarsign.square",
            kind: .shellScript
        ) { url in
            "/bin/zsh \(url.path.shellEscaped)"
        }
    }

    private nonisolated static func loadAppleScriptCommands() -> [ShellCommandItem] {
        loadRunnableFiles(
            in: WorkspacePaths.appleScriptRoot,
            fileExtension: "applescript",
            group: "AppleScripts",
            systemImage: "command.square",
            kind: .appleScript
        ) { url in
            AppleScriptCommand.runFile(url.path)
        }
    }

    private nonisolated static func loadRunnableFiles(
        in rootURL: URL,
        fileExtension: String,
        group: String,
        systemImage: String,
        kind: ShellCommandKind,
        command: (URL) -> String
    ) -> [ShellCommandItem] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls
            .filter { $0.pathExtension.lowercased() == fileExtension.lowercased() }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map { url in
                let title = url.deletingPathExtension().lastPathComponent
                return ShellCommandItem(
                    id: "\(kind.rawValue)-\(url.path)",
                    group: group,
                    title: title,
                    command: command(url),
                    summary: url.path,
                    systemImage: systemImage,
                    kind: kind
                )
            }
    }

    private nonisolated static func systemImage(for scriptName: String) -> String {
        switch scriptName {
        case "Shell scripts": return "dollarsign.square"
        case "AppleScripts": return "command.square"
        case "benshell": return "checkmark.seal"
        case "bensync": return "arrow.triangle.2.circlepath"
        case "nanobot": return "bolt"
        case "deeptutor": return "graduationcap"
        case "papis": return "books.vertical"
        case "taptap": return "waveform.path.ecg"
        default: return "terminal"
        }
    }

    private nonisolated static func toolkitSortKey(_ name: String) -> String {
        switch name {
        case "Shell scripts": return "00-\(name)"
        case "AppleScripts": return "01-\(name)"
        case "benshell": return "02-\(name)"
        case "nanobot": return "03-\(name)"
        case "deeptutor": return "04-\(name)"
        case "taptap": return "05-\(name)"
        default: return "10-\(name)"
        }
    }
}
