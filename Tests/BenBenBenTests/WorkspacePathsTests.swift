import Foundation
import XCTest
@testable import BenBenBen

final class WorkspacePathsTests: XCTestCase {
    func testWorkspaceRootUsesCurrentHomeDirectory() {
        XCTAssertEqual(
            WorkspacePaths.root.path,
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("keyoti", isDirectory: true)
                .path
        )
    }
}
