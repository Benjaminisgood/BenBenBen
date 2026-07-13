import AppKit
import CoreGraphics

struct NotchLayout: Equatable {
    let notchSize: NSSize
    let panelSize: NSSize
    let topOffset: CGFloat
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }

        return CGDirectDisplayID(number.uint32Value)
    }

    var isBuiltInDisplay: Bool {
        guard let displayID else { return false }
        return CGDisplayIsBuiltin(displayID) != 0
    }

    var measuredNotchSize: NSSize {
        guard #available(macOS 12.0, *), safeAreaInsets.top > 0 else {
            return .zero
        }

        guard let leftArea = auxiliaryTopLeftArea, let rightArea = auxiliaryTopRightArea else {
            return .zero
        }

        let notchWidth = frame.width - leftArea.width - rightArea.width
        guard notchWidth > 0, notchWidth < frame.width else {
            return .zero
        }

        return NSSize(width: notchWidth, height: safeAreaInsets.top)
    }
}

enum NotchGeometry {
    private static let fallbackScreenFrame = NSRect(x: 0, y: 0, width: 1440, height: 900)
    private static let fallbackNotchSize = NSSize(width: 210, height: 32)
    private static let horizontalMargin: CGFloat = 16
    private static let verticalMargin: CGFloat = 16

    @MainActor
    static func targetScreen() -> NSScreen? {
        NSScreen.screens.first(where: \.isBuiltInDisplay)
            ?? NSScreen.screens.first { $0.measuredNotchSize != .zero }
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    @MainActor
    static func layout(for screen: NSScreen?) -> NotchLayout {
        guard let screen else {
            return layout(
                screenFrame: fallbackScreenFrame,
                visibleFrame: fallbackScreenFrame,
                measuredNotchSize: .zero
            )
        }

        return layout(
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            measuredNotchSize: screen.measuredNotchSize
        )
    }

    static func layout(
        screenFrame: NSRect,
        visibleFrame: NSRect,
        measuredNotchSize: NSSize
    ) -> NotchLayout {
        let screenBounds = validScreenFrame(screenFrame)
        let visibleBounds = validVisibleFrame(visibleFrame, in: screenBounds)
        let notch = validNotchSize(measuredNotchSize) ?? fallbackNotchSize

        // The controller centers the panel on screenBounds.midX. Account for a
        // left or right Dock so that the centered panel still fits visibleBounds.
        let centeredWidth = 2 * min(
            screenBounds.midX - visibleBounds.minX,
            visibleBounds.maxX - screenBounds.midX
        )
        let availableWidth = max(
            1,
            min(visibleBounds.width, max(0, centeredWidth)) - horizontalMargin * 2
        )
        let availableHeight = max(1, visibleBounds.height - verticalMargin)

        // Ben龙 now has one permanent footprint. It neither widens nor expands
        // on hover; only unusually constrained displays may shrink it to fit.
        let panelSize = NSSize(
            width: min(186, availableWidth),
            height: min(140, availableHeight)
        )

        return NotchLayout(
            notchSize: notch,
            panelSize: panelSize,
            topOffset: 0
        )
    }

    private static func validScreenFrame(_ frame: NSRect) -> NSRect {
        guard frame.width.isFinite,
              frame.height.isFinite,
              frame.width > 0,
              frame.height > 0 else {
            return fallbackScreenFrame
        }
        return frame
    }

    private static func validVisibleFrame(_ frame: NSRect, in screenFrame: NSRect) -> NSRect {
        guard frame.width.isFinite,
              frame.height.isFinite,
              frame.width > 0,
              frame.height > 0 else {
            return screenFrame
        }

        let intersection = frame.intersection(screenFrame)
        return intersection.isNull || intersection.isEmpty ? screenFrame : intersection
    }

    private static func validNotchSize(_ size: NSSize) -> NSSize? {
        guard size.width.isFinite,
              size.height.isFinite,
              size.width > 0,
              size.height > 0 else {
            return nil
        }
        return size
    }

}
