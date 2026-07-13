import Foundation

/// Visual-only scenes for the dragon's folded-notch home. These never change
/// the operational mascot state or the notch's expanded/collapsed state.
enum CompactHomeScene: String, CaseIterable, Sendable {
    case tucked
    case popOut
    case throwStar
    case talk
    case hide
    case peek3D

    var shortLabel: String {
        switch self {
        case .tucked: return "待在家里"
        case .popOut: return "跳出家的窗口"
        case .throwStar: return "扔出一颗星星"
        case .talk: return "冒泡说句话"
        case .hide: return "躲回刘海后面"
        case .peek3D: return "立体探出屏幕"
        }
    }
}

enum CompactHomeStageGeometry {
    static func safeHomeCenterScreenY(
        homeHeight: CGFloat,
        physicalNotchHeight: CGFloat,
        mascotSize: CGFloat,
        homeScale: CGFloat
    ) -> CGFloat {
        let syntheticHomeCenter = homeHeight * 0.68
        guard physicalNotchHeight > 0 else { return syntheticHomeCenter }

        // Keep a meaningful portion of the sprite below the opaque camera
        // housing before it crosses the black home's lower edge.
        let visibleBodyInset = mascotSize * homeScale * 0.30
        return min(
            homeHeight - 4,
            max(syntheticHomeCenter, physicalNotchHeight + visibleBodyInset)
        )
    }
}
