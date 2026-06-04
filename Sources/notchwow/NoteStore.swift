import AppKit
import Combine
import Foundation

struct NoteTab: Identifiable, Codable, Equatable {
    var id: UUID
    var text: String
    var createdAt: Date
    var selectionLocation: Int?
    var selectionLength: Int?
    var filePath: String?

    init(id: UUID = UUID(), text: String = "", createdAt: Date = Date(), filePath: String? = nil) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.filePath = filePath
        selectionLocation = 0
        selectionLength = 0
    }

    var fileURL: URL? {
        filePath.map { URL(fileURLWithPath: $0) }
    }

    var fileName: String {
        fileURL?.lastPathComponent ?? "\(title).md"
    }

    var title: String {
        Self.firstHeadingTitle(in: text)
            ?? fileURL?.deletingPathExtension().lastPathComponent
            ?? "Untitled"
    }

    static func firstHeadingTitle(in text: String) -> String? {
        guard let firstLine = text.components(separatedBy: .newlines).first else { return nil }
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("# ") else { return nil }

        let title = trimmed
            .dropFirst(2)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return title.isEmpty ? nil : title
    }
}

@MainActor
final class NoteStore: ObservableObject {
    @Published private(set) var tabs: [NoteTab]
    @Published private(set) var activeTabID: UUID
    @Published var searchQuery = ""
    @Published private(set) var lastError: String?

    private static let textKey = "notchwow.text"
    private static let legacyTextKey = "notchNotes.text"
    private static let activeFilePathKey = "notchwow.activeFilePath"
    private static let legacyActiveFilePathKey = "notchNotes.activeFilePath"
    private var markdownRoot: URL
    private var syncTimer: Timer?
    private var isWritingToDisk = false

    init(markdownRoot: URL = WorkspacePaths.markdownRoot) {
        WorkspacePaths.ensureDirectories()
        self.markdownRoot = markdownRoot.standardizedFileURL

        let legacyText = AppDefaults.string(forKey: Self.textKey, migrating: Self.legacyTextKey)
        let seededText = legacyText?.isEmpty == false ? legacyText! : "# Untitled\n\n"
        let initialTabs = Self.availableMarkdownTabs(from: self.markdownRoot, seedText: seededText)

        tabs = initialTabs

        let activePath = AppDefaults.string(forKey: Self.activeFilePathKey, migrating: Self.legacyActiveFilePathKey)
        activeTabID = activePath.flatMap { path in
            initialTabs.first(where: { $0.filePath == path })?.id
        } ?? initialTabs[0].id

        save()
        startDiskSync()
    }

    var text: String {
        tabs[activeIndex].text
    }

    var activeTab: NoteTab {
        tabs[activeIndex]
    }

    var wikiLinkResolver: MarkdownNoteWikiLinkResolver {
        MarkdownNoteWikiLinkResolver(index: MarkdownNoteLinkIndex(tabs: tabs, markdownRoot: markdownRoot))
    }

    var filteredTabs: [NoteTab] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return tabs }

        return tabs.filter { tab in
            tab.title.localizedCaseInsensitiveContains(query)
                || tab.fileName.localizedCaseInsensitiveContains(query)
        }
    }

    func updateText(_ nextText: String) {
        tabs[activeIndex].text = nextText
        clampSelection(for: tabs[activeIndex].id)
        persistActiveTabToDisk(allowRename: true)
        save()
    }

    func clear() {
        updateText("")
        updateSelection(for: activeTabID, range: NSRange(location: 0, length: 0))
    }

    func addTab() {
        let tab = Self.persistNewTab(NoteTab(text: "# Untitled\n\n"), in: markdownRoot)
        tabs.append(tab)
        activeTabID = tab.id
        searchQuery = ""
        save()
    }

    func moveActiveTabToTrash() {
        guard let url = activeTab.fileURL else { return }
        NSWorkspace.shared.recycle([url]) { [weak self] _, error in
            Task { @MainActor in
                if let error {
                    self?.lastError = "Move to Trash failed: \(error.localizedDescription)"
                    return
                }
                self?.lastError = nil
                self?.syncFromDisk()
            }
        }
    }

    func selectTab(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeTabID = id
        save()
    }

    func openWikiLinkTarget(_ rawTarget: String) {
        let displayName = MarkdownNoteLinkIndex.displayName(from: rawTarget)
        let index = MarkdownNoteLinkIndex(tabs: tabs, markdownRoot: markdownRoot)
        guard let target = index.target(for: rawTarget),
              let linkedTab = tabs.first(where: { $0.filePath == target.filePath }) else {
            lastError = "Markdown note not found: \(displayName)"
            return
        }

        activeTabID = linkedTab.id
        searchQuery = ""
        lastError = nil
        save()
    }

    func useMarkdownRoot(_ root: URL) {
        let nextRoot = root.standardizedFileURL
        guard markdownRoot.standardizedFileURL.path != nextRoot.path else { return }

        if !tabs.isEmpty {
            persistActiveTabToDisk(allowRename: false)
        }

        markdownRoot = nextRoot
        searchQuery = ""
        reloadFromMarkdownRoot(seedLegacyText: false)
    }

    func updateSelection(for id: UUID, range: NSRange) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let clamped = clampedRange(range, text: tabs[index].text)
        tabs[index].selectionLocation = clamped.location
        tabs[index].selectionLength = clamped.length
        save()
    }

    func selectionRange(for id: UUID) -> NSRange {
        guard let tab = tabs.first(where: { $0.id == id }) else {
            return NSRange(location: 0, length: 0)
        }

        return clampedRange(
            NSRange(location: tab.selectionLocation ?? 0, length: tab.selectionLength ?? 0),
            text: tab.text
        )
    }

    func syncFromDisk() {
        guard !isWritingToDisk else { return }
        let activePath = tabs.first { $0.id == activeTabID }?.filePath
        let diskTabs = Self.availableMarkdownTabs(from: markdownRoot, seedText: "# Untitled\n\n")

        var existingByPath: [String: NoteTab] = [:]
        tabs.compactMap { tab -> (String, NoteTab)? in
            guard let filePath = tab.filePath else { return nil }
            return (filePath, tab)
        }
        .forEach { filePath, tab in
            existingByPath[filePath] = tab
        }

        let mergedTabs = diskTabs.map { diskTab -> NoteTab in
            guard var existing = diskTab.filePath.flatMap({ existingByPath[$0] }) else {
                return diskTab
            }

            existing.text = diskTab.text
            existing.createdAt = diskTab.createdAt
            return existing
        }

        guard mergedTabs != tabs else { return }

        tabs = mergedTabs
        if let activePath,
           let activeID = mergedTabs.first(where: { $0.filePath == activePath })?.id {
            activeTabID = activeID
        } else {
            activeTabID = mergedTabs[0].id
        }
        save()
    }

    private var activeIndex: Int {
        tabs.firstIndex { $0.id == activeTabID } ?? 0
    }

    private func reloadFromMarkdownRoot(seedLegacyText: Bool) {
        let seededText: String
        if seedLegacyText,
           let legacyText = AppDefaults.string(forKey: Self.textKey, migrating: Self.legacyTextKey),
           !legacyText.isEmpty {
            seededText = legacyText
        } else {
            seededText = "# Untitled\n\n"
        }
        let loadedTabs = Self.availableMarkdownTabs(from: markdownRoot, seedText: seededText)

        tabs = loadedTabs
        let activePath = AppDefaults.string(forKey: Self.activeFilePathKey, migrating: Self.legacyActiveFilePathKey)
        activeTabID = activePath.flatMap { path in
            loadedTabs.first(where: { $0.filePath == path })?.id
        } ?? loadedTabs[0].id
        save()
    }

    private func persistActiveTabToDisk(allowRename: Bool) {
        guard tabs.indices.contains(activeIndex) else { return }
        isWritingToDisk = true
        defer { isWritingToDisk = false }

        var tab = tabs[activeIndex]
        let currentURL = tab.fileURL
        let directoryURL = currentURL?.deletingLastPathComponent() ?? markdownRoot
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            lastError = "Could not create Markdown directory: \(error.localizedDescription)"
            return
        }

        let desiredURL: URL
        if allowRename, let title = NoteTab.firstHeadingTitle(in: tab.text) {
            desiredURL = WorkspacePaths.uniquedFileURL(
                stem: title,
                fileExtension: "md",
                in: directoryURL,
                excluding: currentURL
            )
        } else if let currentURL {
            desiredURL = currentURL
        } else {
            desiredURL = WorkspacePaths.uniquedFileURL(
                stem: tab.title,
                fileExtension: "md",
                in: markdownRoot
            )
        }

        if let currentURL,
           currentURL.standardizedFileURL.path != desiredURL.standardizedFileURL.path,
           FileManager.default.fileExists(atPath: currentURL.path) {
            do {
                try FileManager.default.moveItem(at: currentURL, to: desiredURL)
            } catch {
                lastError = "Could not rename Markdown file: \(error.localizedDescription)"
                return
            }
        }

        do {
            try tab.text.write(to: desiredURL, atomically: true, encoding: .utf8)
            tab.filePath = desiredURL.path
            tabs[activeIndex] = tab
            lastError = nil
        } catch {
            tabs[activeIndex] = tab
            lastError = "Could not save Markdown file: \(error.localizedDescription)"
        }
    }

    private func clampSelection(for id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let range = NSRange(location: tabs[index].selectionLocation ?? 0, length: tabs[index].selectionLength ?? 0)
        let clamped = clampedRange(range, text: tabs[index].text)
        tabs[index].selectionLocation = clamped.location
        tabs[index].selectionLength = clamped.length
    }

    private func clampedRange(_ range: NSRange, text: String) -> NSRange {
        let length = (text as NSString).length
        let location = min(max(range.location, 0), length)
        let selectionLength = min(max(range.length, 0), length - location)
        return NSRange(location: location, length: selectionLength)
    }

    private func save() {
        guard !tabs.isEmpty else { return }
        if let activePath = activeTab.filePath {
            AppDefaults.set(activePath, forKey: Self.activeFilePathKey, removing: Self.legacyActiveFilePathKey)
        }
        AppDefaults.set(text, forKey: Self.textKey, removing: Self.legacyTextKey)
    }

    private func startDiskSync() {
        syncTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.syncFromDisk()
            }
        }
    }

    private static func loadMarkdownTabs(from root: URL) -> [NoteTab] {
        let manager = FileManager.default
        try? manager.createDirectory(at: root, withIntermediateDirectories: true)
        guard let enumerator = manager.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var loadedTabs: [NoteTab] = []

        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
            if values?.isDirectory == true {
                if url.lastPathComponent == "attachments" {
                    enumerator.skipDescendants()
                }
                continue
            }

            guard ["md", "markdown"].contains(url.pathExtension.lowercased()) else { continue }
            let text = (try? String(contentsOf: url, encoding: .utf8))
                ?? (try? String(contentsOf: url))
                ?? ""
            loadedTabs.append(
                NoteTab(
                    text: text,
                    createdAt: values?.contentModificationDate ?? Date(),
                    filePath: url.path
                )
            )
        }

        return loadedTabs.sorted {
            $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending
        }
    }

    private static func availableMarkdownTabs(from root: URL, seedText: String) -> [NoteTab] {
        let loadedTabs = loadMarkdownTabs(from: root)
        guard loadedTabs.isEmpty else { return loadedTabs }

        return [persistNewTab(NoteTab(text: seedText), in: root)]
    }

    private static func persistNewTab(_ tab: NoteTab, in root: URL) -> NoteTab {
        var nextTab = tab
        let title = NoteTab.firstHeadingTitle(in: tab.text) ?? "Untitled"
        let url = WorkspacePaths.uniquedFileURL(stem: title, fileExtension: "md", in: root)
        try? tab.text.write(to: url, atomically: true, encoding: .utf8)
        nextTab.filePath = url.path
        return nextTab
    }
}
