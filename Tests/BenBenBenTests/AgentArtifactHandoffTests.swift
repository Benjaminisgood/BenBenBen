import Foundation
import XCTest
@testable import BenBenBen

final class AgentArtifactHandoffTests: XCTestCase {
    func testSnapshotFindsNewAndModifiedArtifacts() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BenBenBenArtifacts-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let existing = root.appendingPathComponent("existing.html")
        try "old".write(to: existing, atomically: true, encoding: .utf8)
        let locations = [(kind: AgentArtifactKind.html, roots: [root])]
        let baseline = AgentArtifactSnapshot.capture(locations: locations)

        try "updated with more content".write(to: existing, atomically: true, encoding: .utf8)
        let created = root.appendingPathComponent("practice.html")
        try "<button>Practice</button>".write(to: created, atomically: true, encoding: .utf8)

        let current = AgentArtifactSnapshot.capture(locations: locations)
        let changes = current.changes(since: baseline)

        XCTAssertEqual(Set(changes.map { $0.url.lastPathComponent }), ["existing.html", "practice.html"])
        XCTAssertTrue(changes.allSatisfy { $0.kind == .html })
    }

    func testOperatingContractUsesLiveSharedRootsAndHandoffMarker() {
        let prompt = AgentOperatingContract.prompt("根据最近的笔记生成练习题")

        XCTAssertTrue(prompt.contains(WorkspacePaths.htmlRoot.path))
        XCTAssertTrue(prompt.contains(WorkspacePaths.markdownRoot.path))
        XCTAssertTrue(prompt.contains("BENBENBEN_ARTIFACT:"))
        XCTAssertTrue(prompt.contains("recently modified Markdown"))
    }
}
