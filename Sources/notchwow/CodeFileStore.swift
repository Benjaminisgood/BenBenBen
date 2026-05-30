import Combine
import Foundation

struct CodeFile: Identifiable, Equatable {
    var id = UUID()
    var text: String
    var filePath: String
    var createdAt: Date

    var fileURL: URL {
        URL(fileURLWithPath: filePath)
    }

    var fileName: String {
        fileURL.lastPathComponent
    }
}

@MainActor
final class CodeFileStore: ObservableObject {
    @Published private(set) var files: [CodeFile]
    @Published private(set) var activeFileID: UUID
    @Published var searchQuery = ""

    private let rootURL: URL
    private let fileExtension: String
    private let defaultTemplate: String
    private let commentPrefix: String
    private let defaultStem = "scratch"
    private var syncTimer: Timer?
    private var isWritingToDisk = false

    init(rootURL: URL, fileExtension: String, defaultTemplate: String, commentPrefix: String = "# ") {
        self.rootURL = rootURL
        self.fileExtension = fileExtension
        self.defaultTemplate = defaultTemplate
        self.commentPrefix = commentPrefix
        try? FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let loadedFiles = Self.availableFiles(
            from: rootURL,
            fileExtension: fileExtension,
            defaultTemplate: defaultTemplate,
            defaultStem: defaultStem
        )
        files = loadedFiles
        activeFileID = loadedFiles[0].id
        startDiskSync()
    }

    var text: String {
        files[activeIndex].text
    }

    var activeFile: CodeFile {
        files[activeIndex]
    }

    var filteredFiles: [CodeFile] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return files }

        return files.filter {
            $0.fileName.localizedCaseInsensitiveContains(query)
        }
    }

    func updateText(_ nextText: String) {
        files[activeIndex].text = nextText
        persistActiveFile()
    }

    func addFile() {
        let file = Self.persistNewFile(
            text: defaultTemplate,
            rootURL: rootURL,
            fileExtension: fileExtension,
            stem: defaultStem
        )
        files.append(file)
        activeFileID = file.id
        searchQuery = ""
    }

    func selectFile(_ id: UUID) {
        guard files.contains(where: { $0.id == id }) else { return }
        activeFileID = id
    }

    func syncFromDisk() {
        guard !isWritingToDisk else { return }
        let activePath = files.first { $0.id == activeFileID }?.filePath
        let diskFiles = Self.availableFiles(
            from: rootURL,
            fileExtension: fileExtension,
            defaultTemplate: defaultTemplate,
            defaultStem: defaultStem
        )

        var existingByPath: [String: CodeFile] = [:]
        files.forEach { existingByPath[$0.filePath] = $0 }
        let mergedFiles = diskFiles.map { diskFile -> CodeFile in
            guard var existing = existingByPath[diskFile.filePath] else {
                return diskFile
            }

            existing.text = diskFile.text
            existing.createdAt = diskFile.createdAt
            return existing
        }

        guard mergedFiles != files else { return }

        files = mergedFiles
        activeFileID = activePath.flatMap { path in
            mergedFiles.first(where: { $0.filePath == path })?.id
        } ?? mergedFiles[0].id
    }

    private var activeIndex: Int {
        files.firstIndex { $0.id == activeFileID } ?? 0
    }

    func persistActiveFile() {
        isWritingToDisk = true
        defer { isWritingToDisk = false }

        guard files.indices.contains(activeIndex) else { return }
        var file = files[activeIndex]

        // Auto-rename based on first comment title (skip shebang)
        if let title = Self.firstCommentTitle(in: file.text, commentPrefix: commentPrefix) {
            let desiredURL = WorkspacePaths.uniquedFileURL(
                stem: title,
                fileExtension: fileExtension,
                in: rootURL,
                excluding: file.fileURL
            )
            if desiredURL.standardizedFileURL.path != file.fileURL.standardizedFileURL.path,
               FileManager.default.fileExists(atPath: file.filePath) {
                try? FileManager.default.moveItem(at: file.fileURL, to: desiredURL)
                file.filePath = desiredURL.path
                files[activeIndex] = file
            }
        }

        try? file.text.write(to: file.fileURL, atomically: true, encoding: .utf8)
    }

    /// Extracts a title from the first comment line matching the given prefix, skipping shebang lines.
    static func firstCommentTitle(in text: String, commentPrefix: String = "# ") -> String? {
        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Skip empty lines and shebang
            if trimmed.isEmpty || trimmed.hasPrefix("#!") { continue }
            // First comment matching prefix is the title
            if trimmed.hasPrefix(commentPrefix) {
                let title = String(trimmed.dropFirst(commentPrefix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return title.isEmpty ? nil : title
            }
            // Any other non-comment line means no title
            return nil
        }
        return nil
    }

    private func startDiskSync() {
        syncTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.syncFromDisk()
            }
        }
    }

    private static func loadFiles(from rootURL: URL, fileExtension: String) -> [CodeFile] {
        let manager = FileManager.default
        try? manager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        guard let urls = try? manager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return urls
            .filter { $0.pathExtension.lowercased() == fileExtension.lowercased() }
            .map { url in
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                let text = (try? String(contentsOf: url, encoding: .utf8))
                    ?? (try? String(contentsOf: url))
                    ?? ""
                return CodeFile(
                    text: text,
                    filePath: url.path,
                    createdAt: values?.contentModificationDate ?? Date()
                )
            }
            .sorted {
                $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending
            }
    }

    private static func availableFiles(
        from rootURL: URL,
        fileExtension: String,
        defaultTemplate: String,
        defaultStem: String
    ) -> [CodeFile] {
        let loadedFiles = loadFiles(from: rootURL, fileExtension: fileExtension)
        guard loadedFiles.isEmpty else { return loadedFiles }

        return [persistNewFile(
            text: defaultTemplate,
            rootURL: rootURL,
            fileExtension: fileExtension,
            stem: defaultStem
        )]
    }

    private static func persistNewFile(
        text: String,
        rootURL: URL,
        fileExtension: String,
        stem: String
    ) -> CodeFile {
        let url = WorkspacePaths.uniquedFileURL(
            stem: stem,
            fileExtension: fileExtension,
            in: rootURL
        )
        try? text.write(to: url, atomically: true, encoding: .utf8)
        return CodeFile(text: text, filePath: url.path, createdAt: Date())
    }
}
