import SwiftUI

@MainActor
struct CompactDragonStageView: View {
    @ObservedObject var mascotModel: MascotModel
    let mascotSize: CGFloat
    let canvasSize: CGSize
    let homeSize: CGSize
    let physicalNotchSize: CGSize

    var body: some View {
        CompactDragonHomeView(
            state: mascotModel.presentedState,
            size: mascotSize,
            mascotRevision: mascotModel.presentationRevision,
            scene: mascotModel.compactHomeScene,
            sceneRevision: mascotModel.compactHomeSceneRevision,
            message: mascotModel.compactHomeMessage,
            canvasSize: canvasSize,
            homeSize: homeSize,
            physicalNotchSize: physicalNotchSize
        )
    }
}

/// A transparent, click-through stage aligned with the folded notch. The black
/// compact panel underneath is Ben龙's home window; this larger view lets the
/// character and props cross that window edge onto the desktop.
@MainActor
struct CompactDragonHomeView: View {
    let state: MascotState
    let size: CGFloat
    let mascotRevision: Int
    let scene: CompactHomeScene
    let sceneRevision: Int
    let message: String?
    let canvasSize: CGSize
    let homeSize: CGSize
    let physicalNotchSize: CGSize

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var dragonScale: CGFloat = 0.50
    @State private var dragonOffset = CGSize.zero
    @State private var dragonOpacity = 1.0
    @State private var dragonPitch = 0.0
    @State private var dragonYaw = 0.0
    @State private var dragonRoll = 0.0
    @State private var propOffset = CGSize.zero
    @State private var propOpacity = 0.0
    @State private var propScale: CGFloat = 0.3
    @State private var propRotation = 0.0
    @State private var speechScale: CGFloat = 0.1
    @State private var speechOpacity = 0.0

    private let homeScale: CGFloat = 0.50

    var body: some View {
        ZStack {
            doorwayGlow

            thrownStar
                .zIndex(4)

            MascotView(state: state, size: size, revision: mascotRevision)
                .scaleEffect(dragonScale, anchor: .center)
                .rotation3DEffect(
                    .degrees(dragonPitch),
                    axis: (x: 1, y: 0, z: 0),
                    anchor: .center,
                    perspective: 0.48
                )
                .rotation3DEffect(
                    .degrees(dragonYaw),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.48
                )
                .rotationEffect(.degrees(dragonRoll))
                .offset(x: dragonOffset.width, y: homeCenterY + dragonOffset.height)
                .opacity(dragonOpacity)
                .shadow(
                    color: .black.opacity(outsideHome ? 0.72 : 0.22),
                    radius: outsideHome ? 14 : 4,
                    x: dragonOffset.width * -0.08,
                    y: outsideHome ? 14 : 3
                )
                .shadow(
                    color: .mint.opacity(scene == .popOut || scene == .peek3D ? 0.52 : 0.14),
                    radius: scene == .peek3D ? 16 : 7
                )
                .zIndex(2)

            homeWindowSill
                .zIndex(3)

            speechBubble
                .zIndex(5)
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ben龙折叠动画，\(scene.shortLabel)")
        .task(id: HomeSceneTrigger(scene: scene, revision: sceneRevision, reduceMotion: reduceMotion)) {
            await playCurrentScene()
        }
    }

    /// SwiftUI coordinates are centered in the transparent panel. Its top is
    /// screen-top, so this aligns the character with the compact panel below.
    private var homeCenterY: CGFloat {
        -canvasSize.height / 2 + CompactHomeStageGeometry.safeHomeCenterScreenY(
            homeHeight: homeSize.height,
            physicalNotchHeight: physicalNotchSize.height,
            mascotSize: size,
            homeScale: homeScale
        )
    }

    private var homeLowerEdgeY: CGFloat {
        -canvasSize.height / 2 + homeSize.height
    }

    private var outsideHome: Bool {
        dragonOffset.height > homeSize.height * 0.38 || dragonScale > 0.88
    }

    private var doorwayGlow: some View {
        RadialGradient(
            colors: [Color.mint.opacity(outsideHome ? 0.28 : 0.10), .clear],
            center: .top,
            startRadius: 0,
            endRadius: size * 1.45
        )
        .frame(width: size * 2.5, height: size * 1.9)
        .offset(y: homeLowerEdgeY + size * 0.72)
        .opacity(scene == .hide ? 0.25 : 1)
        .allowsHitTesting(false)
    }

    /// This foreground lip visually occludes the dragon as it crosses the
    /// black home's lower edge, which makes the exit read as real depth.
    private var homeWindowSill: some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.98),
                        Color(red: 0.06, green: 0.15, blue: 0.13).opacity(0.96),
                        Color.black.opacity(0.98),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .overlay(alignment: .top) {
                Capsule()
                    .fill(Color.mint.opacity(outsideHome ? 0.42 : 0.18))
                    .frame(height: 1.5)
            }
            .frame(width: homeSize.width * 0.82, height: 9)
            .offset(y: homeLowerEdgeY)
            .shadow(color: .black.opacity(0.82), radius: 5, y: 4)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private var thrownStar: some View {
        if scene == .throwStar || propOpacity > 0 {
            ZStack {
                Circle()
                    .fill(Color.cyan.opacity(0.30))
                    .frame(width: 32, height: 32)
                    .blur(radius: 7)
                Image(systemName: "star.fill")
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(.yellow)
                    .shadow(color: .orange.opacity(0.95), radius: 5)
                ForEach(0..<5, id: \.self) { index in
                    Circle()
                        .fill(index.isMultiple(of: 2) ? Color.cyan : Color.yellow)
                        .frame(width: 4, height: 4)
                        .offset(x: CGFloat(-14 - index * 8), y: CGFloat(index * 5 - 10))
                }
            }
            .scaleEffect(propScale)
            .rotationEffect(.degrees(propRotation))
            .offset(x: propOffset.width, y: homeCenterY + propOffset.height)
            .opacity(propOpacity)
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var speechBubble: some View {
        if scene == .talk || speechOpacity > 0 {
            Text(message ?? "嘿！")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.84))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.white.opacity(0.96), in: Capsule())
                .overlay(alignment: .bottomLeading) {
                    SpeechTail()
                        .fill(.white.opacity(0.96))
                        .frame(width: 10, height: 8)
                        .offset(x: 12, y: 5)
                }
                .shadow(color: .black.opacity(0.34), radius: 8, y: 5)
                .shadow(color: .cyan.opacity(0.30), radius: 7)
                .scaleEffect(speechScale, anchor: .bottomLeading)
                .offset(x: size * 0.82, y: homeCenterY + size * 0.48)
                .opacity(speechOpacity)
                .allowsHitTesting(false)
        }
    }

    private func playCurrentScene() async {
        resetMotion()
        guard scene != .tucked else { return }

        if reduceMotion {
            applyReducedMotionScene()
            return
        }

        await Task.yield()
        guard !Task.isCancelled else { return }

        switch scene {
        case .tucked:
            break
        case .popOut:
            setInitial(scale: 0.44, offset: CGSize(width: 0, height: -12), opacity: 0.60, pitch: -62)
            dragonYaw = -18
            withAnimation(.spring(response: 0.42, dampingFraction: 0.56)) {
                dragonScale = 1.18
                dragonOffset = CGSize(width: -42, height: 108)
                dragonOpacity = 1
                dragonPitch = 8
                dragonYaw = 10
                dragonRoll = -8
            }
            guard await pause(milliseconds: 470) else { return }
            withAnimation(.spring(response: 0.40, dampingFraction: 0.62)) {
                dragonScale = 1.05
                dragonOffset = CGSize(width: 54, height: 142)
                dragonRoll = 9
                dragonYaw = -12
            }
            guard await pause(milliseconds: 310) else { return }
            withAnimation(.spring(response: 0.48, dampingFraction: 0.76)) {
                restoreDragon()
            }
        case .throwStar:
            setInitial(scale: 0.68, offset: CGSize(width: -8, height: 20), opacity: 1, pitch: 0)
            propOpacity = 1
            propOffset = CGSize(width: 8, height: 34)
            propScale = 0.30
            withAnimation(.spring(response: 0.30, dampingFraction: 0.62)) {
                dragonScale = 0.86
                dragonOffset = CGSize(width: -24, height: 58)
                dragonRoll = -10
                propScale = 0.82
            }
            guard await pause(milliseconds: 220) else { return }
            withAnimation(.timingCurve(0.16, 0.78, 0.22, 1, duration: 0.90)) {
                propOffset = CGSize(width: canvasSize.width * 0.37, height: 152)
                propScale = 1.34
                propRotation = 520
                dragonRoll = 6
            }
            guard await pause(milliseconds: 820) else { return }
            withAnimation(.easeIn(duration: 0.20)) {
                propOffset.height += 46
                propOpacity = 0
                restoreDragon()
            }
        case .talk:
            speechOpacity = 1
            withAnimation(.spring(response: 0.38, dampingFraction: 0.62)) {
                speechScale = 1
                dragonScale = 0.90
                dragonOffset = CGSize(width: -36, height: 66)
                dragonYaw = -10
            }
            guard await pause(milliseconds: 1_500) else { return }
            withAnimation(.easeIn(duration: 0.24)) {
                speechScale = 0.72
                speechOpacity = 0
                restoreDragon()
            }
        case .hide:
            withAnimation(.easeIn(duration: 0.42)) {
                dragonScale = 0.30
                dragonOffset = CGSize(width: 0, height: -48)
                dragonOpacity = 0.08
                dragonPitch = -58
            }
            guard await pause(milliseconds: 640) else { return }
            withAnimation(.spring(response: 0.50, dampingFraction: 0.58)) {
                dragonScale = 0.70
                dragonOffset = CGSize(width: 18, height: 20)
                dragonOpacity = 1
                dragonPitch = 3
                dragonYaw = 18
            }
            guard await pause(milliseconds: 450) else { return }
            withAnimation(.easeOut(duration: 0.26)) { restoreDragon() }
        case .peek3D:
            setInitial(
                scale: 0.38,
                offset: CGSize(width: -58, height: -8),
                opacity: 0.58,
                pitch: -18
            )
            dragonYaw = -82
            withAnimation(.spring(response: 0.54, dampingFraction: 0.55)) {
                dragonScale = 1.34
                dragonOffset = CGSize(width: 34, height: 112)
                dragonOpacity = 1
                dragonPitch = 10
                dragonYaw = 18
                dragonRoll = 3
            }
            guard await pause(milliseconds: 620) else { return }
            withAnimation(.spring(response: 0.38, dampingFraction: 0.62)) {
                dragonScale = 1.12
                dragonOffset = CGSize(width: -26, height: 136)
                dragonPitch = -3
                dragonYaw = -14
                dragonRoll = -4
            }
            guard await pause(milliseconds: 330) else { return }
            withAnimation(.spring(response: 0.46, dampingFraction: 0.76)) {
                restoreDragon()
            }
        }
    }

    private func applyReducedMotionScene() {
        switch scene {
        case .talk:
            dragonScale = 0.74
            dragonOffset = CGSize(width: -18, height: 34)
            speechScale = 1
            speechOpacity = 1
        case .throwStar:
            dragonScale = 0.72
            dragonOffset = CGSize(width: -12, height: 30)
            propOpacity = 1
            propScale = 1
            propOffset = CGSize(width: size * 1.12, height: 66)
        case .hide:
            dragonScale = 0.34
            dragonOffset = CGSize(width: 0, height: -32)
        case .popOut, .peek3D:
            dragonScale = 0.80
            dragonOffset = CGSize(width: 12, height: 42)
        case .tucked:
            break
        }
    }

    private func setInitial(
        scale: CGFloat,
        offset: CGSize,
        opacity: Double,
        pitch: Double
    ) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            dragonScale = scale
            dragonOffset = offset
            dragonOpacity = opacity
            dragonPitch = pitch
        }
    }

    private func resetMotion() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            restoreDragon()
            propOffset = .zero
            propOpacity = 0
            propScale = 0.3
            propRotation = 0
            speechScale = 0.1
            speechOpacity = 0
        }
    }

    private func restoreDragon() {
        dragonScale = homeScale
        dragonOffset = .zero
        dragonOpacity = 1
        dragonPitch = 0
        dragonYaw = 0
        dragonRoll = 0
    }

    private func pause(milliseconds: Int64) async -> Bool {
        do {
            try await Task.sleep(for: .milliseconds(milliseconds))
            return !Task.isCancelled
        } catch {
            return false
        }
    }
}

private struct HomeSceneTrigger: Equatable {
    let scene: CompactHomeScene
    let revision: Int
    let reduceMotion: Bool
}

private struct SpeechTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
