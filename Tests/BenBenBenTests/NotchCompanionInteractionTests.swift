import XCTest
@testable import BenBenBen

@MainActor
final class NotchCompanionInteractionTests: XCTestCase {
    func testBeginningNewTaskPersistsIntentAndRequestsComposerFocus() {
        let state = NotchCompanionInteractionState()

        state.beginNewTask()
        state.requestComposerFocus()

        XCTAssertTrue(state.isComposingNewTask)
        XCTAssertEqual(state.composerFocusRevision, 1)
    }
}
