import Foundation
import XCTest
@testable import BenBenBen

final class MarkdownNoteLinkIndexTests: XCTestCase {
    func testResolvesWikiLinksByTitleFileNameAndRelativePath() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let noteURL = root
            .appendingPathComponent("Areas", isDirectory: true)
            .appendingPathComponent("Project Note.md", isDirectory: false)
        let tab = NoteTab(
            text: "# Better Title\n\nBody",
            filePath: noteURL.path
        )
        let index = MarkdownNoteLinkIndex(tabs: [tab], markdownRoot: root)

        XCTAssertEqual(index.target(for: "Better Title")?.filePath, noteURL.path)
        XCTAssertEqual(index.target(for: "Project Note")?.filePath, noteURL.path)
        XCTAssertEqual(index.target(for: "Project Note.md")?.filePath, noteURL.path)
        XCTAssertEqual(index.target(for: "Areas/Project Note")?.filePath, noteURL.path)
        XCTAssertEqual(index.target(for: "Areas/Project Note.md")?.filePath, noteURL.path)
    }

    func testIgnoresHeadingAndBlockAnchorsWhenResolvingNoteTarget() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let noteURL = root.appendingPathComponent("Daily.md", isDirectory: false)
        let tab = NoteTab(text: "# Daily\n\nBody", filePath: noteURL.path)
        let index = MarkdownNoteLinkIndex(tabs: [tab], markdownRoot: root)

        XCTAssertEqual(index.target(for: "Daily#Agenda")?.filePath, noteURL.path)
        XCTAssertEqual(index.target(for: "Daily^block-id")?.filePath, noteURL.path)
    }
}
