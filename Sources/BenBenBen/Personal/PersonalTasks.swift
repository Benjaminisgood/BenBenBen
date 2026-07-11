import Foundation

enum PersonalTaskTag: String, CaseIterable, Codable, Hashable, Sendable {
    case work
    case study
    case life
}

enum PersonalTaskSourceSyntax: String, Codable, Hashable, Sendable {
    case checkbox
    case directive
}

struct PersonalTaskOccurrence: Identifiable, Hashable, Sendable {
    let sourcePath: String
    let lineNumber: Int
    let lineHash: String
    let rawLine: String
    let title: String
    let isCompleted: Bool
    let dueDate: Date?
    let dueDateText: String?
    let tags: [PersonalTaskTag]
    let sourceSyntax: PersonalTaskSourceSyntax

    var id: String { "\(sourcePath):\(lineNumber):\(lineHash)" }
    var sourceURL: URL { URL(fileURLWithPath: sourcePath, isDirectory: false) }
}

struct PersonalTaskDraft: Equatable, Sendable {
    var title: String
    var dueDate: Date?
    var tags: [PersonalTaskTag]

    init(title: String, dueDate: Date? = nil, tags: [PersonalTaskTag] = []) {
        self.title = title
        self.dueDate = dueDate
        self.tags = tags
    }
}

enum PersonalWorkspaceMutationError: LocalizedError, Equatable {
    case emptyTaskTitle
    case lockedFile(String)
    case missingSource(String)
    case missingLine(path: String, line: Int)
    case sourceChanged(path: String, line: Int)
    case unsupportedTaskSyntax

    var errorDescription: String? {
        switch self {
        case .emptyTaskTitle:
            return "Task title cannot be empty."
        case .lockedFile(let path):
            return "Change blocked because the file is locked: \(path)"
        case .missingSource(let path):
            return "Task source does not exist: \(path)"
        case .missingLine(let path, let line):
            return "Task source no longer has line \(line): \(path)"
        case .sourceChanged(let path, let line):
            return "Task source changed at line \(line); refresh before completing it: \(path)"
        case .unsupportedTaskSyntax:
            return "The task line is no longer a supported checkbox or directive."
        }
    }
}

enum PersonalTaskParser {
    private static let checkboxPattern = #"^\s*[-*+]\s+\[([ xX])\]\s*(.*)$"#
    private static let directivePattern = #"^\s*(TODO:|TODO：|todo:|待完成:|note：|NOTE：|注意：)\s*(.*)$"#
    private static let dueDatePattern = #"📅\s*(\d{4}-\d{2}-\d{2})"#
    private static let tagPattern = #"#(work|study|life)\b"#

    static func parseFile(at url: URL) throws -> [PersonalTaskOccurrence] {
        let content = try String(contentsOf: url, encoding: .utf8)
        return parse(content: content, sourceURL: url)
    }

    static func parse(content: String, sourceURL: URL) -> [PersonalTaskOccurrence] {
        content
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .compactMap { offset, rawSubstring in
                parseLine(
                    exactLine: String(rawSubstring),
                    lineNumber: offset + 1,
                    sourceURL: sourceURL
                )
            }
    }

    static func parseLine(
        exactLine: String,
        lineNumber: Int,
        sourceURL: URL
    ) -> PersonalTaskOccurrence? {
        let displayLine = exactLine.hasSuffix("\r") ? String(exactLine.dropLast()) : exactLine
        let fullRange = NSRange(displayLine.startIndex..<displayLine.endIndex, in: displayLine)

        if let expression = try? NSRegularExpression(pattern: checkboxPattern),
           let match = expression.firstMatch(in: displayLine, range: fullRange),
           let state = capture(1, from: match, in: displayLine),
           let payload = capture(2, from: match, in: displayLine) {
            return makeOccurrence(
                exactLine: exactLine,
                displayLine: displayLine,
                payload: payload,
                completed: state.lowercased() == "x",
                syntax: .checkbox,
                lineNumber: lineNumber,
                sourceURL: sourceURL
            )
        }

        if let expression = try? NSRegularExpression(pattern: directivePattern),
           let match = expression.firstMatch(in: displayLine, range: fullRange),
           let payload = capture(2, from: match, in: displayLine) {
            return makeOccurrence(
                exactLine: exactLine,
                displayLine: displayLine,
                payload: payload,
                completed: false,
                syntax: .directive,
                lineNumber: lineNumber,
                sourceURL: sourceURL
            )
        }

        return nil
    }

    private static func makeOccurrence(
        exactLine: String,
        displayLine: String,
        payload: String,
        completed: Bool,
        syntax: PersonalTaskSourceSyntax,
        lineNumber: Int,
        sourceURL: URL
    ) -> PersonalTaskOccurrence {
        let dueDateText = firstCapture(pattern: dueDatePattern, in: payload)
        let dueDate = dueDateText.flatMap(PersonalTaskDate.parse)
        let tags = tagCaptures(in: payload)
        let title = cleanedTitle(from: payload)

        return PersonalTaskOccurrence(
            sourcePath: sourceURL.standardizedFileURL.path,
            lineNumber: lineNumber,
            lineHash: PersonalContentHash.sha256(exactLine),
            rawLine: displayLine,
            title: title,
            isCompleted: completed,
            dueDate: dueDate,
            dueDateText: dueDateText,
            tags: tags,
            sourceSyntax: syntax
        )
    }

    private static func cleanedTitle(from payload: String) -> String {
        var result = payload
        for pattern in [dueDatePattern, tagPattern] {
            guard let expression = try? NSRegularExpression(
                pattern: pattern,
                options: pattern == tagPattern ? [.caseInsensitive] : []
            ) else { continue }
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = expression.stringByReplacingMatches(in: result, range: range, withTemplate: "")
        }
        return result
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstCapture(pattern: String, in string: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                in: string,
                range: NSRange(string.startIndex..<string.endIndex, in: string)
              ) else { return nil }
        return capture(1, from: match, in: string)
    }

    private static func tagCaptures(in string: String) -> [PersonalTaskTag] {
        guard let expression = try? NSRegularExpression(pattern: tagPattern, options: [.caseInsensitive]) else {
            return []
        }
        let matches = expression.matches(
            in: string,
            range: NSRange(string.startIndex..<string.endIndex, in: string)
        )
        let tags = matches.compactMap { match -> PersonalTaskTag? in
            guard let value = capture(1, from: match, in: string) else { return nil }
            return PersonalTaskTag(rawValue: value.lowercased())
        }
        return Array(Set(tags)).sorted { $0.rawValue < $1.rawValue }
    }

    private static func capture(_ index: Int, from match: NSTextCheckingResult, in string: String) -> String? {
        guard index < match.numberOfRanges,
              let range = Range(match.range(at: index), in: string) else { return nil }
        return String(string[range])
    }
}

struct PersonalTaskService {
    typealias LockCheck = (URL) -> Bool

    let registry: WorkspaceRegistry
    private let isLocked: LockCheck

    init(
        registry: WorkspaceRegistry,
        isLocked: @escaping LockCheck = { FilePermissionLock.isLocked($0) }
    ) {
        self.registry = registry
        self.isLocked = isLocked
    }

    func loadTasks() throws -> [PersonalTaskOccurrence] {
        guard let enumerator = FileManager.default.enumerator(
            at: registry.markdownRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var tasks: [PersonalTaskOccurrence] = []
        for case let url as URL in enumerator {
            guard ["md", "markdown"].contains(url.pathExtension.lowercased()),
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            tasks.append(contentsOf: try PersonalTaskParser.parseFile(at: url))
        }
        return tasks.sorted(by: Self.taskOrdering)
    }

    @discardableResult
    func capture(_ draft: PersonalTaskDraft) throws -> PersonalTaskOccurrence {
        let normalizedTitle = draft.title
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else {
            throw PersonalWorkspaceMutationError.emptyTaskTitle
        }

        let inboxURL = registry.inboxURL
        if FileManager.default.fileExists(atPath: inboxURL.path), isLocked(inboxURL) {
            throw PersonalWorkspaceMutationError.lockedFile(inboxURL.path)
        }
        try FileManager.default.createDirectory(
            at: registry.markdownRoot,
            withIntermediateDirectories: true
        )

        var components = ["- [ ] \(normalizedTitle)"]
        if let dueDate = draft.dueDate {
            components.append("📅 \(PersonalTaskDate.format(dueDate))")
        }
        let tags = Array(Set(draft.tags)).sorted { $0.rawValue < $1.rawValue }
        components.append(contentsOf: tags.map { "#\($0.rawValue)" })
        let taskLine = components.joined(separator: " ")

        let existing = (try? String(contentsOf: inboxURL, encoding: .utf8)) ?? ""
        let separator = existing.isEmpty || existing.hasSuffix("\n") ? "" : "\n"
        let updated = existing + separator + taskLine + "\n"

        if FileManager.default.fileExists(atPath: inboxURL.path), isLocked(inboxURL) {
            throw PersonalWorkspaceMutationError.lockedFile(inboxURL.path)
        }
        try Data(updated.utf8).write(to: inboxURL, options: .atomic)

        let lineNumber = existing.split(separator: "\n", omittingEmptySubsequences: false).count
            + (separator.isEmpty ? 0 : 1)
        guard let occurrence = PersonalTaskParser.parseLine(
            exactLine: taskLine,
            lineNumber: lineNumber,
            sourceURL: inboxURL
        ) else {
            throw PersonalWorkspaceMutationError.unsupportedTaskSyntax
        }
        return occurrence
    }

    @discardableResult
    func complete(_ task: PersonalTaskOccurrence) throws -> PersonalTaskOccurrence {
        let sourceURL = task.sourceURL
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw PersonalWorkspaceMutationError.missingSource(sourceURL.path)
        }
        guard !isLocked(sourceURL) else {
            throw PersonalWorkspaceMutationError.lockedFile(sourceURL.path)
        }

        let content = try String(contentsOf: sourceURL, encoding: .utf8)
        var lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let index = task.lineNumber - 1
        guard lines.indices.contains(index) else {
            throw PersonalWorkspaceMutationError.missingLine(path: sourceURL.path, line: task.lineNumber)
        }
        guard PersonalContentHash.sha256(lines[index]) == task.lineHash else {
            throw PersonalWorkspaceMutationError.sourceChanged(path: sourceURL.path, line: task.lineNumber)
        }
        if task.isCompleted { return task }

        let usesCarriageReturn = lines[index].hasSuffix("\r")
        var displayLine = usesCarriageReturn ? String(lines[index].dropLast()) : lines[index]
        switch task.sourceSyntax {
        case .checkbox:
            guard let stateRange = displayLine.range(of: #"\[ \]"#, options: .regularExpression) else {
                throw PersonalWorkspaceMutationError.unsupportedTaskSyntax
            }
            displayLine.replaceSubrange(stateRange, with: "[x]")
        case .directive:
            let pattern = #"^([\t ]*)(?:TODO:|TODO：|todo:|待完成:|note：|NOTE：|注意：)[\t ]*"#
            guard let expression = try? NSRegularExpression(pattern: pattern),
                  expression.firstMatch(
                    in: displayLine,
                    range: NSRange(displayLine.startIndex..<displayLine.endIndex, in: displayLine)
                  ) != nil else {
                throw PersonalWorkspaceMutationError.unsupportedTaskSyntax
            }
            let fullRange = NSRange(displayLine.startIndex..<displayLine.endIndex, in: displayLine)
            displayLine = expression.stringByReplacingMatches(
                in: displayLine,
                range: fullRange,
                withTemplate: "$1- [x] "
            )
        }
        lines[index] = displayLine + (usesCarriageReturn ? "\r" : "")

        guard !isLocked(sourceURL) else {
            throw PersonalWorkspaceMutationError.lockedFile(sourceURL.path)
        }
        try Data(lines.joined(separator: "\n").utf8).write(to: sourceURL, options: .atomic)

        guard let completed = PersonalTaskParser.parseLine(
            exactLine: lines[index],
            lineNumber: task.lineNumber,
            sourceURL: sourceURL
        ) else {
            throw PersonalWorkspaceMutationError.unsupportedTaskSyntax
        }
        return completed
    }

    private static func taskOrdering(_ lhs: PersonalTaskOccurrence, _ rhs: PersonalTaskOccurrence) -> Bool {
        if lhs.isCompleted != rhs.isCompleted { return !lhs.isCompleted }
        switch (lhs.dueDate, rhs.dueDate) {
        case let (left?, right?) where left != right:
            return left < right
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            if lhs.sourcePath != rhs.sourcePath { return lhs.sourcePath < rhs.sourcePath }
            return lhs.lineNumber < rhs.lineNumber
        }
    }
}

private enum PersonalTaskDate {
    static func parse(_ string: String) -> Date? {
        formatter().date(from: string)
    }

    static func format(_ date: Date) -> String {
        formatter().string(from: date)
    }

    private static func formatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}
