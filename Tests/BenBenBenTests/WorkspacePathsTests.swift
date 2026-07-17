import Foundation
import XCTest
@testable import BenBenBen

final class WorkspacePathsTests: XCTestCase {
    func testWorkspaceRootDefaultsToKeyotiInCurrentHomeDirectory() {
        XCTAssertEqual(
            WorkspacePaths.resolvedRoot(
                storedPath: nil,
                homeDirectory: FileManager.default.homeDirectoryForCurrentUser
            ).path,
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("keyoti", isDirectory: true)
                .path
        )
    }

    func testWorkspaceRootAcceptsPersistedAbsoluteDirectory() {
        XCTAssertEqual(
            WorkspacePaths.resolvedRoot(
                storedPath: "/tmp/Ben workspace",
                homeDirectory: URL(fileURLWithPath: "/Users/test", isDirectory: true)
            ).path,
            "/tmp/Ben workspace"
        )
    }
}
