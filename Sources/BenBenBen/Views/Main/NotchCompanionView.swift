import SwiftUI

@MainActor
final class NotchAgentContext: ObservableObject {
    @Published var store: AgentStore?

    init(store: AgentStore? = nil) {
        self.store = store
    }
}

@MainActor
final class NotchPresentationState: ObservableObject {
    @Published var isExpanded = false
}

/// The physical notch and Ben龙 are one stage. Hovering only grows the black
/// stage downward; the mascot keeps the same screen position and size so the
/// compact crop naturally becomes a full-body view.
struct NotchCompanionView: View {
    @ObservedObject var presentationState: NotchPresentationState
    @ObservedObject var mascotModel: MascotModel
    @ObservedObject var voiceInteraction: VoiceInteractionController
    @ObservedObject var agentContext: NotchAgentContext
    @ObservedObject var screenContext: ScreenContextMonitor

    let layout: NotchLayout
    let onSelectTask: (String) -> Void

    var body: some View {
        ZStack(alignment: .top) {
            background

            MascotView(
                state: mascotModel.presentedState,
                size: dragonSize,
                revision: mascotModel.presentationRevision
            )
            .offset(y: dragonTopOffset)
            .contentShape(Rectangle())
            .onTapGesture(perform: toggleVoiceConversation)
            .help(voiceInteraction.isConversationEnabled ? "暂停语音录入" : "开始语音交互")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Ben龙语音按钮")
            .accessibilityHint(voiceInteraction.isConversationEnabled ? "单击暂停语音录入" : "单击开始语音交互")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { toggleVoiceConversation() }
            .zIndex(3)

            if presentationState.isExpanded {
                expandedOverlay
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(TopAttachedRoundedShape(radius: presentationState.isExpanded ? 24 : 17))
        .overlay {
            TopAttachedRoundedShape(radius: presentationState.isExpanded ? 24 : 17)
                .stroke(.white.opacity(presentationState.isExpanded ? 0.13 : 0.06), lineWidth: 1)
        }
        .contentShape(TopAttachedRoundedShape(radius: presentationState.isExpanded ? 24 : 17))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Ben龙 Codex 伙伴")
    }

    private var background: some View {
        ZStack {
            TopAttachedRoundedShape(radius: presentationState.isExpanded ? 24 : 17)
                .fill(Color.black)
            if presentationState.isExpanded {
                LinearGradient(
                    colors: [Color.black, Color(red: 0.015, green: 0.08, blue: 0.045)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(TopAttachedRoundedShape(radius: 24))
            }
        }
    }

    private var expandedOverlay: some View {
        ZStack(alignment: .top) {
            if let store = agentContext.store, !visibleTasks(in: store).isEmpty {
                DragonTaskThoughtCloud(
                    threads: visibleTasks(in: store),
                    store: store,
                    selectedThreadID: store.selectedThreadID,
                    isDetailVisible: false,
                    onSelect: { threadID in
                        store.selectedThreadID = threadID
                        onSelectTask(threadID)
                    }
                )
                .scaleEffect(0.82, anchor: .top)
                .offset(y: 80)
                .zIndex(2)
            } else {
                DragonActionGlyph(state: mascotModel.presentedState)
                    .scaleEffect(0.72)
                    .offset(x: 42, y: 66)
            }

            VStack(spacing: 0) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(agentIsReady ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)
                    Text("Ben龙")
                        .font(.caption2.weight(.semibold))
                    Spacer()
                    if screenContext.isEnabled {
                        Label("屏幕", systemImage: "eye.fill")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.green)
                            .help("正在共享屏幕上下文")
                    }
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 13)
                .padding(.top, 8)

                Spacer()

                voiceStatus
                    .padding(.horizontal, 12)
                    .padding(.bottom, 11)
            }
            .zIndex(5)
        }
    }

    private var voiceStatus: some View {
        HStack(spacing: 7) {
            Image(systemName: voiceInteraction.isConversationEnabled ? "waveform.circle.fill" : "pause.circle.fill")
                .foregroundStyle(voiceInteraction.isConversationEnabled ? Color.green : Color.secondary)
                .symbolEffect(.pulse, isActive: voiceInteraction.isRecording)
            VStack(alignment: .leading, spacing: 1) {
                Text(voiceTitle)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(voiceSubtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.075), in: .rect(cornerRadius: 13))
        .overlay { RoundedRectangle(cornerRadius: 13).stroke(.white.opacity(0.09), lineWidth: 1) }
    }

    private var voiceTitle: String {
        if voiceInteraction.isSpeaking { return "Ben龙正在回应" }
        if voiceInteraction.isRecording { return "正在聆听" }
        if voiceInteraction.isConversationEnabled { return "语音即将恢复" }
        return "语音已暂停"
    }

    private var voiceSubtitle: String {
        let transcript = voiceInteraction.liveTranscript
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !transcript.isEmpty { return transcript }
        return voiceInteraction.isConversationEnabled ? "再点 Ben龙暂停录入" : "点 Ben龙开始交互"
    }

    private var dragonSize: CGFloat {
        min(88, max(80, layout.compactSize.height * 1.36))
    }

    private var dragonTopOffset: CGFloat {
        16
    }

    private var agentIsReady: Bool {
        guard let store = agentContext.store else { return false }
        if case .ready = store.connectionState { return true }
        return false
    }

    private func toggleVoiceConversation() {
        if voiceInteraction.pendingTranscript != nil {
            voiceInteraction.cancelPending()
        }
        voiceInteraction.toggleConversation()
    }

    private func visibleTasks(in store: AgentStore) -> [AgentThread] {
        Array(store.threads.filter { thread in
            store.activeTurns[thread.id]?.status.isCompanionRunning == true
        }.sorted { left, right in
            (left.updatedAt ?? left.createdAt ?? 0) > (right.updatedAt ?? right.createdAt ?? 0)
        }.prefix(8))
    }
}

private struct DragonActionGlyph: View {
    let state: MascotState

    var body: some View {
        Group {
            switch state {
            case .listening: Image(systemName: "waveform").foregroundStyle(.green)
            case .thinking, .working: Image(systemName: "ellipsis.message.fill").foregroundStyle(.cyan)
            case .waitingApproval: Image(systemName: "hand.raised.fill").foregroundStyle(.orange)
            case .success: Image(systemName: "checkmark.message.fill").foregroundStyle(.green)
            case .error: Image(systemName: "exclamationmark.bubble.fill").foregroundStyle(.red)
            default: EmptyView()
            }
        }
        .font(.system(size: 28, weight: .bold))
        .symbolEffect(.bounce, value: state)
        .padding(8)
        .background(.ultraThinMaterial, in: .circle)
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
