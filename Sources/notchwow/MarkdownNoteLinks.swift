import Foundation
import MarkdownEngine

struct MarkdownNoteLinkTarget: Equatable, Sendable {
    let id: String
    let title: String
    let fileName: String
    let filePath: String
}

struct MarkdownNoteLinkIndex: Sendable {
    private let targetsByKey: [String: MarkdownNoteLinkTarget]

    init(tabs: [NoteTab], markdownRoot: URL) {
        var targetsByKey: [String: MarkdownNoteLinkTarget] = [:]
        let root = markdownRoot.standardizedFileURL

        for tab in tabs {
            guard let filePath = tab.filePath else { continue }

            let url = URL(fileURLWithPath: filePath).standardizedFileURL
            let relativePath = Self.relativePath(for: url, markdownRoot: root)
            let id = relativePath ?? url.path
            let target = MarkdownNoteLinkTarget(
                id: id,
                title: tab.title,
                fileName: tab.fileName,
                filePath: url.path
            )

            for key in Self.lookupKeys(for: tab, url: url, relativePath: relativePath) {
                if targetsByKey[key] == nil {
                    targetsByKey[key] = target
                }
            }
        }

        self.targetsByKey = targetsByKey
    }

    func target(for rawTarget: String) -> MarkdownNoteLinkTarget? {
        for key in Self.candidateKeys(for: rawTarget) {
            if let target = targetsByKey[key] {
                return target
            }
        }
        return nil
    }

    static func displayName(from rawTarget: String) -> String {
        notePathPart(from: rawTarget)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func lookupKeys(for tab: NoteTab, url: URL, relativePath: String?) -> [String] {
        var rawKeys: [String] = [
            tab.title,
            tab.fileName,
            url.deletingPathExtension().lastPathComponent,
            url.path
        ]

        if let relativePath {
            rawKeys.append(relativePath)
            rawKeys.append(droppingMarkdownExtension(from: relativePath))
        }

        return uniqueNormalizedKeys(rawKeys)
    }

    private static func candidateKeys(for rawTarget: String) -> [String] {
        let notePath = notePathPart(from: rawTarget)
        return uniqueNormalizedKeys([
            notePath,
            droppingMarkdownExtension(from: notePath)
        ])
    }

    private static func relativePath(for url: URL, markdownRoot: URL) -> String? {
        let rootPath = markdownRoot.path
        let filePath = url.path
        guard filePath == rootPath || filePath.hasPrefix(rootPath + "/") else { return nil }
        guard filePath != rootPath else { return url.lastPathComponent }
        return String(filePath.dropFirst(rootPath.count + 1))
    }

    private static func notePathPart(from rawTarget: String) -> String {
        let trimmed = rawTarget
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")

        let withoutHeading = trimmed.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first
            .map(String.init)
            ?? trimmed
        return withoutHeading.split(separator: "^", maxSplits: 1, omittingEmptySubsequences: false).first
            .map(String.init)
            ?? withoutHeading
    }

    private static func droppingMarkdownExtension(from value: String) -> String {
        let lowercased = value.lowercased()
        if lowercased.hasSuffix(".markdown") {
            return String(value.dropLast(".markdown".count))
        }
        if lowercased.hasSuffix(".md") {
            return String(value.dropLast(".md".count))
        }
        return value
    }

    private static func uniqueNormalizedKeys(_ rawKeys: [String]) -> [String] {
        var seen: Set<String> = []
        var keys: [String] = []

        for rawKey in rawKeys {
            let normalized = normalize(rawKey)
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { continue }
            keys.append(normalized)
        }

        return keys
    }

    private static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
            .replacingOccurrences(of: #"/+"#, with: "/", options: .regularExpression)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

struct MarkdownNoteWikiLinkResolver: WikiLinkResolver {
    private let index: MarkdownNoteLinkIndex

    init(index: MarkdownNoteLinkIndex) {
        self.index = index
    }

    func resolve(displayName: String, range: NSRange) -> WikiLinkResolution? {
        guard let target = index.target(for: displayName) else { return nil }
        return WikiLinkResolution(id: target.id, exists: true)
    }
}
