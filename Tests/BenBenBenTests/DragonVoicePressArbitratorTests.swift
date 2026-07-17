import XCTest
@testable import BenBenBen

final class DragonVoicePressArbitratorTests: XCTestCase {
    func testShortPressAllowsConversationToggle() {
        var arbitrator = DragonVoicePressArbitrator()

        XCTAssertEqual(arbitrator.begin(hasPendingTranscript: false), .scheduleHold)
        XCTAssertEqual(arbitrator.release(), .none)
        XCTAssertTrue(arbitrator.consumeTap())
    }

    func testLongPressStartsAndStopsOneShotWithoutTogglingConversation() {
        var arbitrator = DragonVoicePressArbitrator()

        XCTAssertEqual(arbitrator.begin(hasPendingTranscript: false), .scheduleHold)
        XCTAssertEqual(
            arbitrator.holdThresholdReached(conversationEnabled: false),
            .startOneShotRecording
        )
        XCTAssertEqual(arbitrator.release(), .stopOneShotRecording)
        XCTAssertFalse(arbitrator.consumeTap())
    }

    func testLongPressDoesNotDisableActiveConversation() {
        var arbitrator = DragonVoicePressArbitrator()

        XCTAssertEqual(arbitrator.begin(hasPendingTranscript: false), .scheduleHold)
        XCTAssertEqual(arbitrator.holdThresholdReached(conversationEnabled: true), .none)
        XCTAssertEqual(arbitrator.release(), .none)
        XCTAssertFalse(arbitrator.consumeTap())
    }

    func testPressCancelsPendingTranscriptWithoutTogglingConversation() {
        var arbitrator = DragonVoicePressArbitrator()

        XCTAssertEqual(
            arbitrator.begin(hasPendingTranscript: true),
            .cancelPendingTranscript
        )
        XCTAssertEqual(arbitrator.release(), .none)
        XCTAssertFalse(arbitrator.consumeTap())
    }
}
