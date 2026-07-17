import XCTest
@testable import BenBenBen

@MainActor
final class MascotModelTests: XCTestCase {
    func testRepeatedBusinessStateDoesNotRestartPresentationAnimation() {
        let model = MascotModel()

        model.setListening(true)
        let firstRevision = model.presentationRevision
        model.setListening(true)

        XCTAssertEqual(model.state, .listening)
        XCTAssertEqual(model.presentedState, .listening)
        XCTAssertEqual(model.presentedMotion, .listeningPerk)
        XCTAssertEqual(model.presentationRevision, firstRevision)
    }

    func testVoiceConversationStopsAmbientPlayUntilPausedAgain() {
        let model = MascotModel()

        XCTAssertTrue(model.isAmbientBehaviorRunning)

        model.setAwake(true)

        XCTAssertTrue(model.isAwake)
        XCTAssertFalse(model.isAmbientBehaviorRunning)
        XCTAssertEqual(model.state, .idle)
        XCTAssertEqual(model.presentedState, .idle)

        model.setAwake(false)

        XCTAssertFalse(model.isAwake)
        XCTAssertTrue(model.isAmbientBehaviorRunning)
    }

    func testAmbientOnlyPosesAreNotBusinessStates() {
        let ambientPoses = MascotState.allCases.filter(\.isAmbientOnly)

        XCTAssertEqual(ambientPoses.count, 18)
        XCTAssertFalse(MascotState.idle.isAmbientOnly)
        XCTAssertFalse(MascotState.working.isAmbientOnly)
        XCTAssertTrue(MascotState.cameraReady.isAmbientOnly)
        XCTAssertTrue(MascotState.teaSip.isAmbientOnly)
        XCTAssertTrue(MascotState.stargaze.isAmbientOnly)
    }

    func testDragonClickCyclesRestingActionsWithoutChangingAwakeState() {
        let model = MascotModel()
        model.setAwake(true)

        model.cycleRestingAction()

        XCTAssertTrue(model.isAwake)
        XCTAssertEqual(model.state, .idle)
        XCTAssertEqual(model.presentedState, .cameraReady)

        model.cycleRestingAction()

        XCTAssertTrue(model.isAwake)
        XCTAssertEqual(model.state, .idle)
        XCTAssertEqual(model.presentedState, .walkLeft)
    }

    func testRestingActionDoesNotChangeConversationState() {
        let model = MascotModel()

        model.cycleRestingAction()

        XCTAssertFalse(model.isAwake)
        XCTAssertEqual(model.state, .idle)
        XCTAssertEqual(model.presentedState, .cameraReady)
    }

    func testDragonClickDoesNotOverrideBusinessState() {
        let model = MascotModel()
        model.setListening(true)
        let revision = model.presentationRevision

        model.cycleRestingAction()

        XCTAssertEqual(model.state, .listening)
        XCTAssertEqual(model.presentedState, .listening)
        XCTAssertEqual(model.presentationRevision, revision)
    }

    func testOperationalStatesProvideMultipleDedicatedMotions() {
        XCTAssertEqual(
            MascotState.listening.motionSequence,
            [.listeningPerk, .listeningNod, .listeningLean]
        )
        XCTAssertEqual(
            MascotState.thinking.motionSequence,
            [.thinkingPonder, .thinkingTrace, .thinkingIdea]
        )
        XCTAssertEqual(
            MascotState.working.motionSequence,
            [.workingFocus, .workingTap, .workingSprint]
        )
        XCTAssertEqual(MascotState.waitingApproval.motionSequence.count, 2)
        XCTAssertEqual(MascotState.success.motionSequence.count, 2)
        XCTAssertEqual(MascotState.error.motionSequence.count, 2)
        XCTAssertEqual(MascotState.sleep.motionSequence, [.offlineBreathing])
    }
}
