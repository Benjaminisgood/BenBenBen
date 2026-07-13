import XCTest
@testable import BenBenBen

final class VoiceInteractionControllerTests: XCTestCase {
    func testReplySpeechRequiresActiveConversationAndEnabledPreference() {
        XCTAssertTrue(
            VoiceInteractionController.shouldSpeakReplies(
                conversationEnabled: true,
                preferenceEnabled: true
            )
        )
        XCTAssertFalse(
            VoiceInteractionController.shouldSpeakReplies(
                conversationEnabled: false,
                preferenceEnabled: true
            )
        )
        XCTAssertFalse(
            VoiceInteractionController.shouldSpeakReplies(
                conversationEnabled: true,
                preferenceEnabled: false
            )
        )
    }
}
