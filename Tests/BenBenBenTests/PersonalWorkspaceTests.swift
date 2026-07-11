import Foundation
import XCTest
@testable import BenBenBen

final class PersonalWorkspaceTests: XCTestCase {
    func testWorkspaceRegistryMapsEveryPersonalRoot() {
        let root = URL(fileURLWithPath: "/tmp/benbenben-personal-root", isDirectory: true)
        let registry = WorkspaceRegistry(root: root)

        XCTAssertEqual(registry.markdownRoot.path, "/tmp/benbenben-personal-root/mds")
        XCTAssertEqual(registry.shellScriptRoot.path, "/tmp/benbenben-personal-root/shs/workspace-scripts")
        XCTAssertEqual(registry.pythonRoot.path, "/tmp/benbenben-personal-root/pys")
        XCTAssertEqual(registry.appleScriptRoot.path, "/tmp/benbenben-personal-root/applescripts")
        XCTAssertEqual(registry.launchdRoot.path, "/tmp/benbenben-personal-root/launchds")
        XCTAssertEqual(registry.inboxURL.path, "/tmp/benbenben-personal-root/mds/Inbox.md")
        XCTAssertEqual(Set(registry.indexedLocations.map(\.kind)), Set(PersonalWorkspaceKind.allCases))
    }

    func testTaskParserRecognizesCheckboxesDirectivesDatesAndTags() throws {
        let sourceURL = URL(fileURLWithPath: "/tmp/Tasks.md")
        let content = """
            - [ ] Ship personal workspace 📅 2026-07-12 #work #life
            * [x] Read the paper #study
            TODO: first
            TODO：second
            todo: third
            待完成: fourth
            note：fifth
            NOTE：sixth
            注意：seventh
            Ordinary prose
            """

        let tasks = PersonalTaskParser.parse(content: content, sourceURL: sourceURL)

        XCTAssertEqual(tasks.count, 9)
        XCTAssertEqual(tasks[0].title, "Ship personal workspace")
        XCTAssertEqual(tasks[0].dueDateText, "2026-07-12")
        XCTAssertEqual(tasks[0].tags, [.life, .work])
        XCTAssertFalse(tasks[0].isCompleted)
        XCTAssertTrue(tasks[1].isCompleted)
        XCTAssertEqual(tasks.dropFirst(2).map(\.sourceSyntax), Array(repeating: .directive, count: 7))
    }

    func testInboxCaptureAndCompletionPreserveTaskMetadata() throws {
        let fixture = try TemporaryPersonalWorkspace()
        defer { fixture.remove() }
        let service = PersonalTaskService(registry: fixture.registry)
        let dueDate = try XCTUnwrap(Self.date("2026-08-01"))

        let captured = try service.capture(PersonalTaskDraft(
            title: "  Prepare\nweekly   review ",
            dueDate: dueDate,
            tags: [.work, .work, .study]
        ))

        XCTAssertEqual(captured.title, "Prepare weekly review")
        XCTAssertEqual(captured.dueDateText, "2026-08-01")
        XCTAssertEqual(captured.tags, [.study, .work])
        XCTAssertEqual(captured.lineNumber, 1)
        XCTAssertEqual(
            try String(contentsOf: fixture.registry.inboxURL, encoding: .utf8),
            "- [ ] Prepare weekly review 📅 2026-08-01 #study #work\n"
        )

        let completed = try service.complete(captured)
        XCTAssertTrue(completed.isCompleted)
        XCTAssertEqual(completed.title, captured.title)
        XCTAssertEqual(completed.dueDateText, captured.dueDateText)
        XCTAssertTrue(
            try String(contentsOf: fixture.registry.inboxURL, encoding: .utf8)
                .hasPrefix("- [x] Prepare weekly review")
        )
    }

    func testCompletionRejectsStaleLineHash() throws {
        let fixture = try TemporaryPersonalWorkspace()
        defer { fixture.remove() }
        try FileManager.default.createDirectory(at: fixture.registry.markdownRoot, withIntermediateDirectories: true)
        let fileURL = fixture.registry.markdownRoot.appendingPathComponent("Project.md")
        try Data("- [ ] Original task\n".utf8).write(to: fileURL)
        let task = try XCTUnwrap(PersonalTaskParser.parseFile(at: fileURL).first)
        try Data("- [ ] Externally changed task\n".utf8).write(to: fileURL)

        XCTAssertThrowsError(try PersonalTaskService(registry: fixture.registry).complete(task)) { error in
            XCTAssertEqual(
                error as? PersonalWorkspaceMutationError,
                .sourceChanged(path: fileURL.path, line: 1)
            )
        }
    }

    func testDirectiveCompletionPreservesMetadataAndCRLF() throws {
        let fixture = try TemporaryPersonalWorkspace()
        defer { fixture.remove() }
        try FileManager.default.createDirectory(at: fixture.registry.markdownRoot, withIntermediateDirectories: true)
        let fileURL = fixture.registry.markdownRoot.appendingPathComponent("Directive.md")
        try Data("NOTE：remember the detail 📅 2026-09-03 #life\r\n".utf8).write(to: fileURL)
        let task = try XCTUnwrap(PersonalTaskParser.parseFile(at: fileURL).first)

        let completed = try PersonalTaskService(registry: fixture.registry).complete(task)

        XCTAssertTrue(completed.isCompleted)
        XCTAssertEqual(completed.title, "remember the detail")
        XCTAssertEqual(completed.dueDateText, "2026-09-03")
        XCTAssertEqual(completed.tags, [.life])
        XCTAssertEqual(
            try String(contentsOf: fileURL, encoding: .utf8),
            "- [x] remember the detail 📅 2026-09-03 #life\r\n"
        )
    }

    func testCompletionRespectsFilePermissionLock() throws {
        let fixture = try TemporaryPersonalWorkspace()
        defer { fixture.remove() }
        try FileManager.default.createDirectory(at: fixture.registry.markdownRoot, withIntermediateDirectories: true)
        let fileURL = fixture.registry.markdownRoot.appendingPathComponent("Locked.md")
        try Data("- [ ] Must remain unchanged\n".utf8).write(to: fileURL)
        let task = try XCTUnwrap(PersonalTaskParser.parseFile(at: fileURL).first)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: fileURL.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: fileURL.path) }

        XCTAssertTrue(FilePermissionLock.isLocked(fileURL))
        XCTAssertThrowsError(try PersonalTaskService(registry: fixture.registry).complete(task)) { error in
            XCTAssertEqual(error as? PersonalWorkspaceMutationError, .lockedFile(fileURL.path))
        }
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "- [ ] Must remain unchanged\n")
    }

    func testSQLiteIndexRefreshesIncrementallyAndReturnsLineSnippets() async throws {
        let fixture = try TemporaryPersonalWorkspace()
        try FileManager.default.createDirectory(at: fixture.registry.markdownRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: fixture.registry.pythonRoot, withIntermediateDirectories: true)
        let noteURL = fixture.registry.markdownRoot.appendingPathComponent("Knowledge.md")
        let pythonURL = fixture.registry.pythonRoot.appendingPathComponent("worker.py")
        try Data("# Header\nContext\nA searchable-nebula lives here.\n".utf8).write(to: noteURL)
        try Data("def run():\n    return 'searchable-nebula'\n".utf8).write(to: pythonURL)

        let index = PersonalSearchIndex(databaseURL: fixture.root.appendingPathComponent("Index/index.sqlite3"))
        var summary = try await index.refresh(registry: fixture.registry)
        XCTAssertEqual(summary.inserted, 2)
        XCTAssertEqual(summary.updated, 0)

        var results = try await index.search("searchable-nebula")
        XCTAssertEqual(results.count, 2)
        let noteResult = try XCTUnwrap(results.first { $0.path == noteURL.path })
        XCTAssertEqual(noteResult.line, 3)
        XCTAssertEqual(noteResult.snippet, "A searchable-nebula lives here.")

        summary = try await index.refresh(registry: fixture.registry)
        XCTAssertEqual(summary.unchanged, 2)
        XCTAssertEqual(summary.inserted, 0)

        try Data("# Header\nA newly-indexed-comet appears in a much longer replacement line.\n".utf8).write(to: noteURL)
        summary = try await index.refresh(registry: fixture.registry)
        XCTAssertEqual(summary.updated, 1)
        let oldResults = try await index.search("searchable-nebula")
        XCTAssertTrue(oldResults.allSatisfy { $0.path != noteURL.path })
        results = try await index.search("newly-indexed-comet")
        XCTAssertEqual(results.first?.line, 2)

        try FileManager.default.removeItem(at: pythonURL)
        summary = try await index.refresh(registry: fixture.registry)
        XCTAssertEqual(summary.removed, 1)

        await index.close()
        fixture.remove()
    }

    @MainActor
    func testPersonalWorkspaceStoreCoordinatesRefreshAndSearch() async throws {
        let fixture = try TemporaryPersonalWorkspace()
        defer { fixture.remove() }
        try FileManager.default.createDirectory(at: fixture.registry.markdownRoot, withIntermediateDirectories: true)
        let noteURL = fixture.registry.markdownRoot.appendingPathComponent("Store.md")
        try Data("Store facade can find lunar-workflow.\n".utf8).write(to: noteURL)
        let store = PersonalWorkspaceStore(
            registry: fixture.registry,
            databaseURL: fixture.root.appendingPathComponent("Index/store.sqlite3")
        )

        await store.refresh()
        XCTAssertNil(store.lastError)
        store.query = "lunar-workflow"
        await store.search()

        XCTAssertEqual(store.searchResults.first?.path, noteURL.path)
        XCTAssertEqual(store.searchResults.first?.line, 1)
    }

    private static func date(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }
}

private final class TemporaryPersonalWorkspace {
    let root: URL
    let registry: WorkspaceRegistry

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BenBenBenPersonalTests-\(UUID().uuidString)", isDirectory: true)
        registry = WorkspaceRegistry(root: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
