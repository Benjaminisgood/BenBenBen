import AppKit
import SwiftUI

struct MascotView: View {
    let state: MascotState
    var size: CGFloat = 42

    @State private var breath = false

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
        .scaleEffect(y: breath ? 1.025 : 0.985, anchor: .bottom)
        .offset(y: state == .working && breath ? -1.5 : 0)
        .animation(
            .easeInOut(duration: state == .working ? 0.42 : 1.7).repeatForever(autoreverses: true),
            value: breath
        )
        .onAppear { breath = true }
        .accessibilityLabel("Ben龙，\(state.shortLabel)")
    }

    private var imageForState: NSImage? {
        guard let url = Bundle.main.url(
            forResource: state.assetName,
            withExtension: "png",
            subdirectory: "Mascot"
        ) else { return nil }
        return NSImage(contentsOf: url)
    }
}

private struct PixelBenDragon: View {
    let state: MascotState

    var body: some View {
        Canvas { context, size in
            let unit = max(1, floor(min(size.width, size.height) / 14))
            func block(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ color: Color) {
                context.fill(
                    Path(CGRect(x: x * unit, y: y * unit, width: width * unit, height: height * unit)),
                    with: .color(color)
                )
            }

            let green = Color(red: 0.46, green: 0.88, blue: 0.55)
            let light = Color(red: 0.88, green: 0.95, blue: 0.66)
            let ink = Color(red: 0.02, green: 0.14, blue: 0.06)

            block(4, 3, 6, 7, green)
            block(2, 4, 5, 4, green)
            block(1, 5, 3, 2, green)
            block(5, 9, 2, 3, green)
            block(8, 9, 2, 3, green)
            block(7, 7, 3, 3, light)
            block(10, 4, 2, 2, light)
            block(10, 7, 2, 2, light)
            block(10, 10, 2, 2, light)

            if state == .sleep {
                block(4, 5, 2, 1, ink)
                block(8, 5, 2, 1, ink)
            } else {
                block(4, 5, 1, 1, ink)
                block(8, 5, 1, 1, ink)
            }
            block(2, 7, 3, 1, ink)

            switch state {
            case .listening:
                block(12, 4, 1, 1, .cyan)
                block(13, 3, 1, 3, .cyan)
            case .thinking:
                block(1, 1, 1, 1, .yellow)
                block(2, 0, 1, 1, .yellow)
            case .working:
                block(0, 10, 3, 2, .blue)
            case .waitingApproval:
                block(0, 0, 2, 2, .orange)
            case .success:
                block(1, 1, 1, 1, .yellow)
                block(11, 1, 1, 1, .yellow)
            case .error:
                block(0, 1, 2, 1, .red)
            default:
                break
            }
        }
    }
}
