import SwiftUI

@MainActor
final class NotchAgentContext: ObservableObject {
    @Published var store: AgentStore?

    init(store: AgentStore? = nil) {
        self.store = store
    }
}

/// The physical notch and Ben龙 are one fixed stage. The mascot never moves in
/// response to pointer hover, and task bubbles appear directly in this stage.
struct NotchCompanionView: View {
    @ObservedObject var mascotModel: MascotModel
    @ObservedObject var voiceInteraction: VoiceInteractionController
    @ObservedObject var agentContext: NotchAgentContext

    let layout: NotchLayout
    let onVoiceTap: () -> Void
    let onSelectTask: (String) -> Void

    var body: some View {
        ZStack(alignment: .top) {
            background
            voiceButton

            taskOverlay
        }
        // Keep the root's reported size pinned so task-state overlays can only
        // redraw inside the notch and can never resize the NSPanel.
        .frame(
            width: layout.panelSize.width,
            height: layout.panelSize.height,
            alignment: .top
        )
        .clipShape(TopAttachedRoundedShape(radius: 18))
        .overlay {
            TopAttachedRoundedShape(radius: 18)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        }
        .contentShape(TopAttachedRoundedShape(radius: 18))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Ben龙 Codex 伙伴")
    }

    private var background: some View {
        TopAttachedRoundedShape(radius: 18)
            .fill(Color.black)
    }

    private var voiceButton: some View {
        MascotView(
            state: mascotModel.presentedState,
            motion: mascotModel.presentedMotion,
            size: dragonSize,
            revision: mascotModel.presentationRevision
        )
        .offset(y: dragonTopOffset)
        .contentShape(Rectangle())
        .onTapGesture(perform: onVoiceTap)
        .help(voiceHelp)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ben龙语音按钮")
        .accessibilityHint(voiceHelp)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onVoiceTap() }
        .zIndex(3)
    }

    private var taskOverlay: some View {
        Group {
            if let store = agentContext.store, !visibleTasks(in: store).isEmpty {
                DragonTaskThoughtCloud(
                    threads: visibleTasks(in: store),
                    store: store,
                    selectedThreadID: store.selectedThreadID,
                    onSelect: { threadID in
                        store.selectedThreadID = threadID
                        onSelectTask(threadID)
                    }
                )
                .offset(
                    x: min(58, max(32, layout.panelSize.width / 2 - 28)),
                    y: max(0, layout.mascotTopOffset - 4)
                )
                .zIndex(2)
            }
        }
    }

    private var dragonSize: CGFloat {
        layout.mascotSize
    }

    private var dragonTopOffset: CGFloat {
        layout.mascotTopOffset
    }

    private var voiceHelp: String {
        voiceInteraction.isConversationEnabled
            ? "单击暂停持续语音"
            : "单击开启持续语音；按住说话，松开发送"
    }

    private func visibleTasks(in store: AgentStore) -> [AgentThread] {
        Array(store.threads.filter { thread in
            store.activeTurns[thread.id]?.status.isCompanionRunning == true
        }.sorted { left, right in
            (left.updatedAt ?? left.createdAt ?? 0) > (right.updatedAt ?? right.createdAt ?? 0)
        }.prefix(8))
    }
}

private struct TopAttachedRoundedShape: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = min(radius, rect.width / 2, rect.height / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - radius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.closeSubpath()
        return path
    }
}
