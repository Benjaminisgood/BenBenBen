import AppKit
import XCTest
@testable import BenBenBen

final class NotchGeometryTests: XCTestCase {
    func testBuiltInNotchUsesOneFixedPanelSize() {
        let screenFrame = NSRect(x: 0, y: 0, width: 1512, height: 982)
        let visibleFrame = NSRect(x: 0, y: 40, width: 1512, height: 918)
        let measuredNotch = NSSize(width: 210, height: 32)

        let layout = NotchGeometry.layout(
            screenFrame: screenFrame,
            visibleFrame: visibleFrame,
            measuredNotchSize: measuredNotch
        )

        XCTAssertEqual(layout.notchSize, measuredNotch)
        XCTAssertEqual(layout.panelSize, NSSize(width: 186, height: 140))
        XCTAssertLessThanOrEqual(layout.panelSize.width, visibleFrame.width)
        XCTAssertLessThanOrEqual(layout.panelSize.height, visibleFrame.height)
        XCTAssertEqual(layout.topOffset, 0)
    }

    func testNoNotchUsesFallbackGeometry() {
        let screenFrame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let visibleFrame = NSRect(x: 0, y: 0, width: 1440, height: 875)

        let layout = NotchGeometry.layout(
            screenFrame: screenFrame,
            visibleFrame: visibleFrame,
            measuredNotchSize: .zero
        )

        XCTAssertEqual(layout.notchSize, NSSize(width: 210, height: 32))
        XCTAssertEqual(layout.panelSize, NSSize(width: 186, height: 140))
    }

    func testNarrowVisibleFrameShrinksFixedPanelInsideAvailableArea() {
        let screenFrame = NSRect(x: 0, y: 0, width: 240, height: 320)
        let visibleFrame = NSRect(x: 20, y: 40, width: 200, height: 256)

        let layout = NotchGeometry.layout(
            screenFrame: screenFrame,
            visibleFrame: visibleFrame,
            measuredNotchSize: NSSize(width: 210, height: 32)
        )

        XCTAssertEqual(layout.panelSize, NSSize(width: 168, height: 140))
        XCTAssertLessThanOrEqual(layout.panelSize.width, visibleFrame.width)
        XCTAssertLessThanOrEqual(layout.panelSize.height, visibleFrame.height)

        let panelMinX = screenFrame.midX - layout.panelSize.width / 2
        let panelMaxX = screenFrame.midX + layout.panelSize.width / 2
        XCTAssertGreaterThanOrEqual(panelMinX, visibleFrame.minX)
        XCTAssertLessThanOrEqual(panelMaxX, visibleFrame.maxX)
        XCTAssertGreaterThanOrEqual(
            screenFrame.maxY - layout.panelSize.height,
            visibleFrame.minY
        )
        XCTAssertEqual(layout.topOffset, 0)
    }
}
