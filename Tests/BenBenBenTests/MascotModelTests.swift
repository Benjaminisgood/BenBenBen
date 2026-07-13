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
        XCTAssertEqual(model.presentationRevision, firstRevision)
    }
}
