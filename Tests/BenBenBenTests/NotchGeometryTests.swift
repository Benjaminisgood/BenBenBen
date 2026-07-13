import AppKit
import XCTest
@testable import BenBenBen

final class NotchGeometryTests: XCTestCase {
    func testBuiltInNotchUsesComfortableCompactAndBoundedExpandedSizes() {
        let screenFrame = NSRect(x: 0, y: 0, width: 1512, height: 982)
        let visibleFrame = NSRect(x: 0, y: 40, width: 1512, height: 918)
        let measuredNotch = NSSize(width: 210, height: 32)

        let layout = NotchGeometry.layout(
            screenFrame: screenFrame,
            visibleFrame: visibleFrame,
            measuredNotchSize: measuredNotch
        )

        XCTAssertEqual(layout.notchSize, measuredNotch)
        XCTAssertEqual(layout.compactSize.width, 254, accuracy: 0.001)
        XCTAssertEqual(layout.compactSize.height, 62, accuracy: 0.001)
        XCTAssertEqual(layout.expandedSize.width, 560, accuracy: 0.001)
        XCTAssertEqual(layout.expandedSize.height, 470, accuracy: 0.001)
        XCTAssertEqual(layout.expandedDetailSize.width, 820, accuracy: 0.001)
        XCTAssertEqual(layout.expandedDetailSize.height, 470, accuracy: 0.001)
        XCTAssertLessThanOrEqual(layout.expandedSize.width, visibleFrame.width)
        XCTAssertLessThanOrEqual(layout.expandedSize.height, visibleFrame.height)
        XCTAssertEqual(layout.compactTopOffset, 0)
        XCTAssertEqual(layout.expandedTopOffset, 0)
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
        XCTAssertGreaterThanOrEqual(layout.compactSize.width, 210)
        XCTAssertLessThanOrEqual(layout.compactSize.width, 270)
        XCTAssertGreaterThanOrEqual(layout.compactSize.height, 58)
        XCTAssertLessThanOrEqual(layout.compactSize.height, 68)
        XCTAssertEqual(layout.expandedSize, NSSize(width: 560, height: 470))
        XCTAssertEqual(layout.expandedDetailSize, NSSize(width: 820, height: 470))
    }

    func testNarrowVisibleFrameShrinksBothStatesInsideAvailableArea() {
        let screenFrame = NSRect(x: 0, y: 0, width: 360, height: 320)
        let visibleFrame = NSRect(x: 20, y: 40, width: 320, height: 256)

        let layout = NotchGeometry.layout(
            screenFrame: screenFrame,
            visibleFrame: visibleFrame,
            measuredNotchSize: NSSize(width: 210, height: 32)
        )

        XCTAssertEqual(layout.compactSize.width, 254, accuracy: 0.001)
        XCTAssertEqual(layout.expandedSize.width, 288, accuracy: 0.001)
        XCTAssertEqual(layout.expandedDetailSize.width, 288, accuracy: 0.001)
        XCTAssertEqual(layout.expandedSize.height, 240, accuracy: 0.001)
        XCTAssertLessThan(layout.compactSize.width, 270)
        XCTAssertLessThanOrEqual(layout.compactSize.width, visibleFrame.width)
        XCTAssertLessThanOrEqual(layout.compactSize.height, visibleFrame.height)
        XCTAssertLessThanOrEqual(layout.expandedSize.width, visibleFrame.width)
        XCTAssertLessThanOrEqual(layout.expandedSize.height, visibleFrame.height)

        let expandedMinX = screenFrame.midX - layout.expandedSize.width / 2
        let expandedMaxX = screenFrame.midX + layout.expandedSize.width / 2
        XCTAssertGreaterThanOrEqual(expandedMinX, visibleFrame.minX)
        XCTAssertLessThanOrEqual(expandedMaxX, visibleFrame.maxX)
        XCTAssertGreaterThanOrEqual(
            screenFrame.maxY - layout.expandedSize.height,
            visibleFrame.minY
        )
        XCTAssertEqual(layout.compactTopOffset, 0)
        XCTAssertEqual(layout.expandedTopOffset, 0)
    }

    func testCompactStageStartsVisibleContentBelowPhysicalNotch() {
        let centerY = CompactHomeStageGeometry.safeHomeCenterScreenY(
            homeHeight: 62,
            physicalNotchHeight: 32,
            mascotSize: 98,
            homeScale: 0.5
        )

        XCTAssertGreaterThan(centerY, 32)
        XCTAssertLessThanOrEqual(centerY, 58)
    }

    func testCompactStageUsesHomeProportionWithoutPhysicalNotch() {
        let centerY = CompactHomeStageGeometry.safeHomeCenterScreenY(
            homeHeight: 62,
            physicalNotchHeight: 0,
            mascotSize: 98,
            homeScale: 0.5
        )

        XCTAssertEqual(centerY, 42.16, accuracy: 0.001)
    }
}
