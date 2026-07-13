import AppKit
import SwiftUI

@MainActor
struct MascotView: View {
    let state: MascotState
    var size: CGFloat = 42
    var revision = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var motionPhase = false

    var body: some View {
        Group {
            if let image = imageForState {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
            } else {
                PixelBenDragon(state: state)
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(
            x: reduceMotion ? 1 : state.motionScaleX(phase: motionPhase),
            y: reduceMotion ? 1 : state.motionScaleY(phase: motionPhase),
            anchor: .bottom
        )
        .rotationEffect(
            .degrees(reduceMotion ? 0 : state.motionRotation(phase: motionPhase)),
            anchor: .bottom
        )
        .offset(
            x: reduceMotion ? 0 : state.motionOffsetX(phase: motionPhase),
            y: reduceMotion ? 0 : state.motionOffsetY(phase: motionPhase)
        )
        .animation(
            reduceMotion
                ? nil
                : .easeInOut(duration: state.motionDuration)
                    .repeatForever(autoreverses: true),
            value: motionPhase
        )
        .task(id: MotionTrigger(state: state, revision: revision, reduceMotion: reduceMotion)) {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                motionPhase = false
            }

            guard !reduceMotion else { return }
            await Task.yield()
            guard !Task.isCancelled else { return }
            motionPhase = true
        }
        .accessibilityLabel("Ben龙，\(state.shortLabel)")
    }

    private var imageForState: NSImage? {
        MascotImageCache.shared.image(for: state)
    }
}

private struct MotionTrigger: Equatable {
    let state: MascotState
    let revision: Int
    let reduceMotion: Bool
}

private extension MascotState {
    var motionDuration: Double {
        switch self {
        case .walkLeft, .walkRight: return 0.22
        case .cameraShutter: return 0.16
        case .working: return 0.42
        case .music: return 0.48
        case .stretch: return 0.70
        case .rest, .sleep, .cloudWatch, .stargaze: return 2.4
        case .bubbles: return 1.2
        default: return 1.7
        }
    }

    func motionScaleX(phase: Bool) -> CGFloat {
        switch self {
        case .cameraShutter: return phase ? 0.99 : 1.01
        case .stretch: return phase ? 1.018 : 0.99
        default: return 1
        }
    }

    func motionScaleY(phase: Bool) -> CGFloat {
        switch self {
        case .walkLeft, .walkRight: return phase ? 1.018 : 0.982
        case .stretch: return phase ? 1.045 : 0.985
        case .rest, .sleep: return phase ? 1.012 : 0.992
        case .daydream, .cloudWatch, .rain: return phase ? 1 : 0.992
        default: return phase ? 1.025 : 0.985
        }
    }

    func motionRotation(phase: Bool) -> Double {
        switch self {
        case .cameraReady: return phase ? 0.45 : -0.45
        case .cameraShutter: return phase ? -1.2 : 0.4
        case .teaSip: return phase ? -1.4 : -0.4
        case .music: return phase ? 1.4 : -1.4
        case .bubbles: return phase ? 0.8 : -0.8
        default: return 0
        }
    }

    func motionOffsetX(phase: Bool) -> CGFloat {
        switch self {
        case .walkLeft: return phase ? -2.6 : 1.0
        case .walkRight: return phase ? 2.6 : -1.0
        case .cameraShutter: return phase ? -1.2 : 0
        case .music: return phase ? 0.8 : -0.8
        case .bubbles: return phase ? 0.7 : -0.7
        default: return 0
        }
    }

    func motionOffsetY(phase: Bool) -> CGFloat {
        switch self {
        case .working: return phase ? -1.5 : 0
        case .walkLeft, .walkRight: return phase ? -1.4 : 0
        case .music: return phase ? -1.0 : 0
        case .stretch: return phase ? -1.8 : 0
        case .cameraShutter: return phase ? 0.7 : 0
        default: return 0
        }
    }
}

@MainActor
private final class MascotImageCache {
    static let shared = MascotImageCache()

    private let images = NSCache<NSString, NSImage>()
    private var missingAssetNames = Set<String>()

    func image(for state: MascotState) -> NSImage? {
        let assetName = state.assetName
        if let cached = images.object(forKey: assetName as NSString) {
            return cached
        }
        guard !missingAssetNames.contains(assetName) else { return nil }
        guard let url = Bundle.main.url(
            forResource: assetName,
            withExtension: "png",
            subdirectory: "Mascot"
        ), let image = NSImage(contentsOf: url) else {
            missingAssetNames.insert(assetName)
            return nil
        }

        images.setObject(image, forKey: assetName as NSString)
        return image
    }
}

private struct PixelBenDragon: View {
    let state: MascotState

    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width, proxy.size.height) / 100
            ZStack {
                Capsule()
                    .fill(Color(red: 0.22, green: 0.66, blue: 0.34))
                    .frame(width: 54 * scale, height: 17 * scale)
                    .rotationEffect(.degrees(-33))
                    .offset(x: -29 * scale, y: 24 * scale)

                Ellipse()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.48, green: 0.92, blue: 0.54),
                                Color(red: 0.19, green: 0.64, blue: 0.34)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 58 * scale, height: 68 * scale)
                    .offset(y: 18 * scale)

                Ellipse()
                    .fill(Color(red: 0.87, green: 0.95, blue: 0.64))
                    .frame(width: 30 * scale, height: 42 * scale)
                    .offset(y: 23 * scale)

                DragonHorn().fill(.orange.opacity(0.9))
                    .frame(width: 17 * scale, height: 22 * scale)
                    .rotationEffect(.degrees(-18))
                    .offset(x: -25 * scale, y: -31 * scale)
                DragonHorn().fill(.orange.opacity(0.9))
                    .frame(width: 17 * scale, height: 22 * scale)
                    .scaleEffect(x: -1)
                    .rotationEffect(.degrees(18))
                    .offset(x: 25 * scale, y: -31 * scale)

                Ellipse()
                    .fill(Color(red: 0.52, green: 0.94, blue: 0.58))
                    .frame(width: 70 * scale, height: 52 * scale)
                    .offset(y: -15 * scale)
                    .overlay {
                        DragonFace(state: state, scale: scale)
                            .offset(y: -15 * scale)
                    }

                Ellipse()
                    .fill(Color(red: 0.80, green: 0.94, blue: 0.60))
                    .frame(width: 40 * scale, height: 25 * scale)
                    .offset(x: -1 * scale, y: 2 * scale)

                Capsule().fill(Color(red: 0.30, green: 0.75, blue: 0.40))
                    .frame(width: 14 * scale, height: 38 * scale)
                    .rotationEffect(.degrees(20))
                    .offset(x: -34 * scale, y: 23 * scale)
                Capsule().fill(Color(red: 0.30, green: 0.75, blue: 0.40))
                    .frame(width: 14 * scale, height: 38 * scale)
                    .rotationEffect(.degrees(-20))
                    .offset(x: 34 * scale, y: 23 * scale)

                Capsule().fill(Color(red: 0.22, green: 0.61, blue: 0.32))
                    .frame(width: 22 * scale, height: 14 * scale)
                    .offset(x: -18 * scale, y: 45 * scale)
                Capsule().fill(Color(red: 0.22, green: 0.61, blue: 0.32))
                    .frame(width: 22 * scale, height: 14 * scale)
                    .offset(x: 18 * scale, y: 45 * scale)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .shadow(color: .green.opacity(0.28), radius: 8 * scale, y: 4 * scale)
        }
    }
}

private struct DragonHorn: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: 0))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY),
            control1: CGPoint(x: rect.midX, y: rect.height * 0.35),
            control2: CGPoint(x: rect.maxX, y: rect.height * 0.55)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct DragonFace: View {
    let state: MascotState
    let scale: CGFloat

    var body: some View {
        ZStack {
            if state == .sleep {
                Capsule().fill(.black.opacity(0.72)).frame(width: 13 * scale, height: 2.5 * scale)
                    .offset(x: -15 * scale, y: -2 * scale)
                Capsule().fill(.black.opacity(0.72)).frame(width: 13 * scale, height: 2.5 * scale)
                    .offset(x: 15 * scale, y: -2 * scale)
            } else {
                Circle().fill(.white).frame(width: 15 * scale, height: 17 * scale)
                    .overlay(Circle().fill(.black.opacity(0.8)).frame(width: 6 * scale, height: 8 * scale))
                    .offset(x: -15 * scale, y: -3 * scale)
                Circle().fill(.white).frame(width: 15 * scale, height: 17 * scale)
                    .overlay(Circle().fill(.black.opacity(0.8)).frame(width: 6 * scale, height: 8 * scale))
                    .offset(x: 15 * scale, y: -3 * scale)
            }
            Circle().fill(.black.opacity(0.55)).frame(width: 3.5 * scale, height: 3.5 * scale)
                .offset(x: -7 * scale, y: 15 * scale)
            Circle().fill(.black.opacity(0.55)).frame(width: 3.5 * scale, height: 3.5 * scale)
                .offset(x: 7 * scale, y: 15 * scale)
            Capsule()
                .stroke(state == .error ? Color.red : Color.black.opacity(0.58), lineWidth: 2 * scale)
                .frame(width: 18 * scale, height: state == .success ? 9 * scale : 4 * scale)
                .offset(y: 24 * scale)
        }
    }
}
