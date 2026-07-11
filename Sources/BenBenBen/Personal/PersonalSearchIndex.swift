import Foundation
import SQLite3

struct PersonalSearchResult: Identifiable, Hashable, Sendable {
    let path: String
    let kind: PersonalWorkspaceKind
    let line: Int
    let snippet: String
    let score: Double

    var id: String { "\(path):\(line)" }
    var fileURL: URL { URL(fileURLWithPath: path, isDirectory: false) }
}

struct PersonalIndexRefreshSummary: Equatable, Sendable {
    var inserted = 0
    var updated = 0
    var removed = 0
    var unchanged = 0
    var skipped = 0

    var indexedFileCount: Int { inserted + updated + unchanged }
}

enum PersonalSearchIndexError: LocalizedError {
    case sqlite(String)

    var errorDescription: String? {
        switch self {
        case .sqlite(let message):
            return "Personal search index failed: \(message)"
        }
    }
}

/// Lifetime wrapper for SQLite's non-Sendable C handle. The enclosing index
/// actor is the only code that accesses `pointer`; the wrapper exists so handle
/// cleanup does not cross actor isolation from the actor's `deinit`.
private final class PersonalSQLiteConnection: @unchecked Sendable {
    var pointer: OpaquePointer?

    deinit {
        close()
    }

    func close() {
        guard let pointer else { return }
        sqlite3_close(pointer)
        self.pointer = nil
    }
}

/// A refreshable, derived full-text index. Source files remain the source of
/// truth; this database can be safely deleted and rebuilt at any time.
actor PersonalSearchIndex {
    private struct Metadata {
        let rowID: Int64
        let modifiedAt: Double
        let byteCount: Int64
        let contentHash: String
    }

    private struct Candidate {
        let url: URL
        let kind: PersonalWorkspaceKind
        let modifiedAt: Double
        let byteCount: Int64
    }

    private let databaseURL: URL
    private let maximumFileSize: Int
    private let connection = PersonalSQLiteConnection()

    private var database: OpaquePointer? {
        get { connection.pointer }
        set { connection.pointer = newValue }
    }

    init(databaseURL: URL, maximumFileSize: Int = 4 * 1_024 * 1_024) {
        self.databaseURL = databaseURL.standardizedFileURL
        self.maximumFileSize = maximumFileSize
    }

    func close() {
        connection.close()
    }

    @discardableResult
    func refresh(registry: WorkspaceRegistry, force: Bool = false) throws -> PersonalIndexRefreshSummary {
        try openIfNeeded()
        let candidates = discoverCandidates(in: registry)
        let candidatePaths = Set(candidates.map { $0.url.path })
        var summary = PersonalIndexRefreshSummary()

        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            for candidate in candidates {
                let path = candidate.url.path
                let existing = try metadata(for: path)

                if !force,
                   let existing,
                   existing.modifiedAt == candidate.modifiedAt,
                   existing.byteCount == candidate.byteCount {
                    summary.unchanged += 1
                    continue
                }

                guard candidate.byteCount <= maximumFileSize,
                      let data = try? Data(contentsOf: candidate.url, options: .mappedIfSafe),
                      !data.contains(0),
                      let content = String(data: data, encoding: .utf8) else {
                    if let existing {
                        try deleteDocument(path: path, rowID: existing.rowID)
                        summary.removed += 1
                    }
                    summary.skipped += 1
                    continue
                }

                let contentHash = PersonalContentHash.sha256(data)
                if let existing, existing.contentHash == contentHash {
                    try updateMetadata(
                        path: path,
                        kind: candidate.kind,
                        modifiedAt: candidate.modifiedAt,
                        byteCount: candidate.byteCount,
                        contentHash: contentHash,
                        rowID: existing.rowID
                    )
                    summary.unchanged += 1
                    continue
                }

                if let existing {
                    try replaceFTSRow(
                        rowID: existing.rowID,
                        path: path,
                        kind: candidate.kind,
                        content: content
                    )
                    try updateMetadata(
                        path: path,
                        kind: candidate.kind,
                        modifiedAt: candidate.modifiedAt,
                        byteCount: candidate.byteCount,
                        contentHash: contentHash,
                        rowID: existing.rowID
                    )
                    summary.updated += 1
                } else {
                    let rowID = try insertFTSRow(path: path, kind: candidate.kind, content: content)
                    try updateMetadata(
                        path: path,
                        kind: candidate.kind,
                        modifiedAt: candidate.modifiedAt,
                        byteCount: candidate.byteCount,
                        contentHash: contentHash,
                        rowID: rowID
                    )
                    summary.inserted += 1
                }
            }

            for (path, rowID) in try allIndexedPaths() where !candidatePaths.contains(path) {
                try deleteDocument(path: path, rowID: rowID)
                summary.removed += 1
            }

            try execute("COMMIT")
            return summary
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func search(_ query: String, limit: Int = 30) throws -> [PersonalSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, limit > 0 else { return [] }
        try openIfNeeded()

        let matchQuery = Self.ftsQuery(for: trimmed)
        let sql = """
            SELECT path, kind, content, bm25(personal_index_fts)
            FROM personal_index_fts
            WHERE personal_index_fts MATCH ?
            ORDER BY bm25(personal_index_fts), path
            LIMIT ?
            """

        return try withStatement(sql) { statement in
            try bind(trimmedText: matchQuery, at: 1, in: statement)
            sqlite3_bind_int(statement, 2, Int32(min(limit, 200)))
            var results: [PersonalSearchResult] = []

            while sqlite3_step(statement) == SQLITE_ROW {
                let path = columnText(statement, index: 0)
                let kind = PersonalWorkspaceKind(rawValue: columnText(statement, index: 1)) ?? .markdown
                let content = columnText(statement, index: 2)
                let score = sqlite3_column_double(statement, 3)
                let match = Self.bestLine(in: content, query: trimmed)
                results.append(PersonalSearchResult(
                    path: path,
                    kind: kind,
                    line: match.line,
                    snippet: match.snippet,
                    score: score
                ))
            }
            try requireDone(statement)
            return results
        }
    }

    private func discoverCandidates(in registry: WorkspaceRegistry) -> [Candidate] {
        let resourceKeys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        var byPath: [String: Candidate] = [:]

        for location in registry.indexedLocations {
            guard let enumerator = FileManager.default.enumerator(
                at: location.url,
                includingPropertiesForKeys: resourceKeys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let fileURL as URL in enumerator {
                guard Self.supports(fileURL, for: location.kind),
                      let values = try? fileURL.resourceValues(forKeys: Set(resourceKeys)),
                      values.isRegularFile == true else { continue }

                let candidate = Candidate(
                    url: fileURL.standardizedFileURL,
                    kind: location.kind,
                    modifiedAt: values.contentModificationDate?.timeIntervalSince1970 ?? 0,
                    byteCount: Int64(values.fileSize ?? 0)
                )
                byPath[candidate.url.path] = candidate
            }
        }

        return byPath.values.sorted { $0.url.path < $1.url.path }
    }

    private static func supports(_ url: URL, for kind: PersonalWorkspaceKind) -> Bool {
        let fileExtension = url.pathExtension.lowercased()
        switch kind {
        case .markdown:
            return ["md", "markdown", "txt"].contains(fileExtension)
        case .shell:
            return ["sh", "bash", "zsh", "command", "md", "txt"].contains(fileExtension)
        case .python:
            return ["py", "pyi", "toml", "json", "yaml", "yml", "md", "txt"].contains(fileExtension)
        case .appleScript:
            return ["applescript", "js", "md", "txt"].contains(fileExtension)
        case .launchd:
            return ["plist", "json", "yaml", "yml", "md", "txt"].contains(fileExtension)
        }
    }

    private static func ftsQuery(for query: String) -> String {
        let terms = query
            .split(whereSeparator: { $0.isWhitespace })
            .map { term in
                let escaped = term.replacingOccurrences(of: "\"", with: "\"\"")
                return "\"\(escaped)\"*"
            }
        return terms.joined(separator: " AND ")
    }

    private static func bestLine(in content: String, query: String) -> (line: Int, snippet: String) {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        let normalizedQuery = query.lowercased()
        let terms = normalizedQuery.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var bestIndex = 0
        var bestScore = Int.min

        for (index, line) in lines.enumerated() {
            let normalizedLine = line.lowercased()
            var score = terms.reduce(0) { $0 + (normalizedLine.contains($1) ? 10 : 0) }
            if normalizedLine.contains(normalizedQuery) {
                score += 100
            }
            if score > bestScore {
                bestScore = score
                bestIndex = index
            }
        }

        let rawSnippet = lines.indices.contains(bestIndex)
            ? String(lines[bestIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
        let snippet = rawSnippet.count > 280
            ? String(rawSnippet.prefix(277)) + "..."
            : rawSnippet
        return (bestIndex + 1, snippet)
    }

    private func openIfNeeded() throws {
        guard database == nil else { return }
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var opened: OpaquePointer?
        let result = sqlite3_open_v2(
            databaseURL.path,
            &opened,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard result == SQLITE_OK, let opened else {
            let message = opened.map { String(cString: sqlite3_errmsg($0)) } ?? "Could not open SQLite database"
            if let opened { sqlite3_close(opened) }
            throw PersonalSearchIndexError.sqlite(message)
        }
        database = opened

        do {
            try execute("PRAGMA journal_mode=WAL")
            try execute("PRAGMA synchronous=NORMAL")
            try execute("""
                CREATE TABLE IF NOT EXISTS personal_index_metadata (
                    path TEXT PRIMARY KEY,
                    kind TEXT NOT NULL,
                    modified_at REAL NOT NULL,
                    byte_count INTEGER NOT NULL,
                    content_hash TEXT NOT NULL,
                    row_id INTEGER NOT NULL UNIQUE
                )
                """)
            try execute("""
                CREATE VIRTUAL TABLE IF NOT EXISTS personal_index_fts
                USING fts5(path UNINDEXED, kind UNINDEXED, content, tokenize='unicode61')
                """)
        } catch {
            sqlite3_close(opened)
            database = nil
            throw error
        }
    }

    private func metadata(for path: String) throws -> Metadata? {
        try withStatement(
            "SELECT row_id, modified_at, byte_count, content_hash FROM personal_index_metadata WHERE path = ?"
        ) { statement in
            try bind(trimmedText: path, at: 1, in: statement)
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return nil }
            guard result == SQLITE_ROW else { throw sqliteError() }
            return Metadata(
                rowID: sqlite3_column_int64(statement, 0),
                modifiedAt: sqlite3_column_double(statement, 1),
                byteCount: sqlite3_column_int64(statement, 2),
                contentHash: columnText(statement, index: 3)
            )
        }
    }

    private func allIndexedPaths() throws -> [(String, Int64)] {
        try withStatement("SELECT path, row_id FROM personal_index_metadata") { statement in
            var values: [(String, Int64)] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                values.append((columnText(statement, index: 0), sqlite3_column_int64(statement, 1)))
            }
            try requireDone(statement)
            return values
        }
    }

    private func insertFTSRow(path: String, kind: PersonalWorkspaceKind, content: String) throws -> Int64 {
        try withStatement("INSERT INTO personal_index_fts(path, kind, content) VALUES (?, ?, ?)") { statement in
            try bind(trimmedText: path, at: 1, in: statement)
            try bind(trimmedText: kind.rawValue, at: 2, in: statement)
            try bind(trimmedText: content, at: 3, in: statement)
            try requireDoneAfterStep(statement)
        }
        guard let database else { throw PersonalSearchIndexError.sqlite("Database is closed") }
        return sqlite3_last_insert_rowid(database)
    }

    private func replaceFTSRow(
        rowID: Int64,
        path: String,
        kind: PersonalWorkspaceKind,
        content: String
    ) throws {
        try withStatement("DELETE FROM personal_index_fts WHERE rowid = ?") { statement in
            sqlite3_bind_int64(statement, 1, rowID)
            try requireDoneAfterStep(statement)
        }
        try withStatement("INSERT INTO personal_index_fts(rowid, path, kind, content) VALUES (?, ?, ?, ?)") { statement in
            sqlite3_bind_int64(statement, 1, rowID)
            try bind(trimmedText: path, at: 2, in: statement)
            try bind(trimmedText: kind.rawValue, at: 3, in: statement)
            try bind(trimmedText: content, at: 4, in: statement)
            try requireDoneAfterStep(statement)
        }
    }

    private func updateMetadata(
        path: String,
        kind: PersonalWorkspaceKind,
        modifiedAt: Double,
        byteCount: Int64,
        contentHash: String,
        rowID: Int64
    ) throws {
        let sql = """
            INSERT INTO personal_index_metadata(path, kind, modified_at, byte_count, content_hash, row_id)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(path) DO UPDATE SET
                kind = excluded.kind,
                modified_at = excluded.modified_at,
                byte_count = excluded.byte_count,
                content_hash = excluded.content_hash,
                row_id = excluded.row_id
            """
        try withStatement(sql) { statement in
            try bind(trimmedText: path, at: 1, in: statement)
            try bind(trimmedText: kind.rawValue, at: 2, in: statement)
            sqlite3_bind_double(statement, 3, modifiedAt)
            sqlite3_bind_int64(statement, 4, byteCount)
            try bind(trimmedText: contentHash, at: 5, in: statement)
            sqlite3_bind_int64(statement, 6, rowID)
            try requireDoneAfterStep(statement)
        }
    }

    private func deleteDocument(path: String, rowID: Int64) throws {
        try withStatement("DELETE FROM personal_index_fts WHERE rowid = ?") { statement in
            sqlite3_bind_int64(statement, 1, rowID)
            try requireDoneAfterStep(statement)
        }
        try withStatement("DELETE FROM personal_index_metadata WHERE path = ?") { statement in
            try bind(trimmedText: path, at: 1, in: statement)
            try requireDoneAfterStep(statement)
        }
    }

    private func execute(_ sql: String) throws {
        guard let database else { throw PersonalSearchIndexError.sqlite("Database is closed") }
        var errorPointer: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &errorPointer) == SQLITE_OK else {
            let message = errorPointer.map { String(cString: $0) }
                ?? String(cString: sqlite3_errmsg(database))
            sqlite3_free(errorPointer)
            throw PersonalSearchIndexError.sqlite(message)
        }
    }

    private func withStatement<T>(
        _ sql: String,
        body: (OpaquePointer) throws -> T
    ) throws -> T {
        guard let database else { throw PersonalSearchIndexError.sqlite("Database is closed") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw sqliteError() }
        defer { sqlite3_finalize(statement) }
        return try body(statement)
    }

    private func bind(trimmedText text: String, at index: Int32, in statement: OpaquePointer) throws {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        guard sqlite3_bind_text(statement, index, text, -1, transient) == SQLITE_OK else {
            throw sqliteError()
        }
    }

    private func columnText(_ statement: OpaquePointer, index: Int32) -> String {
        guard let value = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: value)
    }

    private func requireDoneAfterStep(_ statement: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else { throw sqliteError() }
    }

    private func requireDone(_ statement: OpaquePointer) throws {
        guard sqlite3_errcode(database) == SQLITE_OK || sqlite3_errcode(database) == SQLITE_DONE else {
            throw sqliteError()
        }
    }

    private func sqliteError() -> PersonalSearchIndexError {
        guard let database else { return .sqlite("Database is closed") }
        return .sqlite(String(cString: sqlite3_errmsg(database)))
    }
}
