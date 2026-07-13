import SwiftUI

@MainActor
final class NotchCompanionInteractionState: ObservableObject {
    @Published var isComposingNewTask = false
    @Published private(set) var composerFocusRevision = 0

    func requestComposerFocus() {
        composerFocusRevision &+= 1
    }

    func beginNewTask() {
        isComposingNewTask = true
    }
}

/// The notch is a character, not a miniature dashboard. A click brings Ben龙
/// closer; shared artifact windows are opened explicitly from the menu bar.
struct NotchCompanionView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // These stores remain owned by WorkbenchEnvironment for compatibility.
    // Their hard-coded toolbars are intentionally absent from the notch: Codex
    // edits the files and the shared artifact windows observe those files.
    @ObservedObject var store: NoteStore
    @ObservedObject var settingsStore: AppSettingsStore
    let imageStore: LocalImageStore
    @ObservedObject var markdownAIStore: MarkdownAIEditStore
    @ObservedObject var markdownAIChatStore: MarkdownAIChatStore
    @ObservedObject var fileLockStore: FilePermissionLockStore
    @ObservedObject var drawerState: DrawerState
    @ObservedObject var editorInteractionState: EditorInteractionState
    @ObservedObject var workbenchState: WorkbenchState
    @ObservedObject var scriptsState: ScriptsModuleState
    @ObservedObject var pythonStore: CodeFileStore
    @ObservedObject var appleScriptStore: CodeFileStore
    @ObservedObject var shellCommandStore: ShellCommandStore
    @ObservedObject var shellWorkspaceStore: ShellWorkspaceStore
    @ObservedObject var launchdJobStore: LaunchdJobStore
    @ObservedObject var launchdAIAgent: LaunchdAIAgent
    @ObservedObject var shellAIStore: ScriptAIEditStore
    @ObservedObject var pythonAIStore: ScriptAIEditStore
    @ObservedObject var appleScriptAIStore: ScriptAIEditStore
    @ObservedObject var condaStore: CondaEnvironmentStore
    @ObservedObject var directoryStore: WorkspaceDirectoryStore
    @ObservedObject var terminalRunner: CommandRunner
    @ObservedObject var pythonRunner: PythonReplRunner
    @ObservedObject var appleScriptRunner: CommandRunner
    @ObservedObject var mascotModel: MascotModel
    @ObservedObject var voiceInteraction: VoiceInteractionController
    @ObservedObject var agentContext: NotchAgentContext
    @ObservedObject var screenContext: ScreenContextMonitor
    @ObservedObject var interactionState: NotchCompanionInteractionState

    let layout: NotchLayout
    let onSendPrompt: (String) -> Void
    let onStartNewTask: (String) -> Void
    let onExpand: () -> Void
    let onMascotAction: () -> Void
    let onOpenSettings: () -> Void
    let onCollapse: () -> Void

    @State private var composer = ""
    @State private var dragonHasWalkedOut = false
    @State private var detailThreadID: String?
    @FocusState private var isComposerFocused: Bool

    var body: some View {
        ZStack {
            if drawerState.isExpanded {
                conversationStage.transition(.opacity)
            } else {
                dragonBehindNotch
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(background)
        .clipShape(TopAttachedRoundedShape(radius: drawerState.isExpanded ? 30 : 18))
        .overlay {
            TopAttachedRoundedShape(radius: drawerState.isExpanded ? 30 : 18)
                .stroke(.white.opacity(drawerState.isExpanded ? 0.12 : 0.07), lineWidth: 1)
        }
        .contentShape(TopAttachedRoundedShape(radius: drawerState.isExpanded ? 30 : 18))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Ben龙 Codex 伙伴")
        .accessibilityHint(
            drawerState.isExpanded
                ? "单击回到当前工作，双击新建任务"
                : "单击唤醒，双击新建任务，按住说话"
        )
        .onChange(of: drawerState.isExpanded) { _, expanded in
            if expanded {
                dragonHasWalkedOut = reduceMotion
                if !reduceMotion {
                    dragonHasWalkedOut = false
                    withAnimation(.spring(response: 0.72, dampingFraction: 0.72)) {
                        dragonHasWalkedOut = true
                    }
                }
            } else {
                dragonHasWalkedOut = false
            }
        }
        .onChange(of: interactionState.composerFocusRevision) { _, _ in
            guard drawerState.isExpanded else { return }
            focusComposerAfterExpansion()
        }
        .onChange(of: runningTaskIDs) { _, runningIDs in
            if let detailThreadID, !runningIDs.contains(detailThreadID) {
                self.detailThreadID = nil
            }
        }
    }

    private var background: some View {
        ZStack {
            TopAttachedRoundedShape(radius: drawerState.isExpanded ? 30 : 18).fill(.ultraThinMaterial)
            TopAttachedRoundedShape(radius: drawerState.isExpanded ? 30 : 18)
                .fill(Color.black.opacity(drawerState.isExpanded ? 0.78 : 0.96))
            if drawerState.isExpanded {
                RadialGradient(
                    colors: [Color.green.opacity(0.13), .clear],
                    center: .center,
                    startRadius: 20,
                    endRadius: 280
                )
            }
        }
    }

    private var dragonBehindNotch: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            MascotView(
                state: mascotModel.presentedState,
                size: min(82, layout.compactSize.height * 1.18),
                revision: mascotModel.presentationRevision
            )
            .offset(y: 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .contentShape(Rectangle())
        .gesture(mascotTapGesture)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("唤醒 Ben龙")
        .accessibilityHint("单击进入近身对话，双击新建任务")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { handleMascotSingleClick() }
    }

    private var conversationStage: some View {
        VStack(spacing: 0) {
            HStack {
                liveStatus
                Spacer()
                Button(action: onCollapse) { Image(systemName: "chevron.up") }
                    .buttonStyle(.plain)
                    .help("让 Ben龙 回到刘海后面")
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)

            Spacer(minLength: 4)

            HStack(spacing: 18) {
                ZStack(alignment: .topTrailing) {
                    MascotView(
                        state: mascotModel.presentedState,
                        size: detailThreadID == nil ? 232 : 196,
                        revision: mascotModel.presentationRevision
                    )
                    .scaleEffect(dragonHasWalkedOut ? 1 : 0.34, anchor: .top)
                    .offset(y: dragonHasWalkedOut ? 8 : -96)
                    .contentShape(Rectangle())
                    .gesture(mascotTapGesture)
                    .help("单击回到当前工作 · 双击新任务")

                    if let agentStore = agentContext.store,
                       !visibleTasks(in: agentStore).isEmpty {
                        DragonTaskThoughtCloud(
                            threads: visibleTasks(in: agentStore),
                            store: agentStore,
                            selectedThreadID: agentStore.selectedThreadID,
                            isDetailVisible: detailThreadID != nil,
                            onSelect: { threadID in
                                withAnimation(.snappy(duration: 0.28)) {
                                    agentStore.selectedThreadID = threadID
                                    detailThreadID = threadID
                                }
                            }
                        )
                        .offset(x: detailThreadID == nil ? 112 : 96, y: -82)
                        .zIndex(4)
                    } else {
                        DragonActionGlyph(state: mascotModel.presentedState)
                            .offset(x: -14, y: 14)
                    }
                }

                if let detailThreadID, let agentStore = agentContext.store {
                    TaskProgressDetailCard(
                        threadID: detailThreadID,
                        store: agentStore,
                        onClose: { self.detailThreadID = nil }
                    )
                    .frame(width: 430)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.snappy(duration: 0.25), value: detailThreadID)

            Spacer(minLength: 8)

            if let approval = preferredApproval, let agentStore = agentContext.store {
                approvalBar(approval, store: agentStore)
            }
            composerBar
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
    }

    private var liveStatus: some View {
        HStack(spacing: 6) {
            Circle().fill(agentIsReady ? Color.green : Color.orange).frame(width: 7, height: 7)
            Text(mascotModel.presentedState.shortLabel).font(.caption.weight(.semibold))
            if let store = agentContext.store {
                let running = store.activeTurns.values.filter { $0.status.isCompanionRunning }.count
                if running > 0 {
                    Text("· \(running) 个任务运行中")
                        .font(.caption2)
                        .foregroundStyle(.cyan)
                }
            }
            if voiceInteraction.isConversationEnabled {
                HStack(spacing: 3) {
                    Circle().fill(Color.green).frame(width: 6, height: 6)
                    Image(systemName: "phone.fill").font(.caption2).foregroundStyle(.green)
                }
                .help("持续语音通话已开启")
                .accessibilityLabel("持续语音通话已开启")
            }
            if screenContext.isEnabled {
                HStack(spacing: 3) {
                    Circle().fill(Color.green).frame(width: 6, height: 6)
                    Image(systemName: "eye.fill").font(.caption2).foregroundStyle(.green)
                }
                .help("共享屏幕上下文已开启；会定时截图给 Codex")
                .accessibilityLabel("共享屏幕上下文已开启")
            }
        }
        .foregroundStyle(.secondary)
    }

    private var composerBar: some View {
        HStack(spacing: 8) {
            Button(action: toggleVoice) {
                Image(systemName: voiceInteraction.isConversationEnabled ? "phone.down.fill" : "phone.fill")
            }
            .buttonStyle(.glassProminent)
            .tint(voiceInteraction.isConversationEnabled ? .red : .green)
            .help(voiceInteraction.isConversationEnabled ? "关闭持续语音" : "开启持续语音")

            TextField(composerPlaceholder, text: $composer, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...3)
                .focused($isComposerFocused)
                .onSubmit(send)

            Button(action: beginOrSendNewTask) {
                Label(
                    interactionState.isComposingNewTask ? "新任务中" : "新任务",
                    systemImage: interactionState.isComposingNewTask ? "plus.bubble.fill" : "plus.bubble"
                )
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.glass)
            .foregroundStyle(interactionState.isComposingNewTask ? Color.cyan : Color.primary)
            .help(
                interactionState.isComposingNewTask
                    ? "正在输入一个独立任务；回车或点发送开始执行，再点一次取消"
                    : "另开一个并行任务；也可以先点这里再输入"
            )
            .accessibilityLabel(interactionState.isComposingNewTask ? "正在新建任务" : "新建任务")
            .accessibilityHint("点击后输入任务，回车或点发送开始执行")

            Button {
                screenContext.isEnabled.toggle()
            } label: {
                Image(systemName: screenContext.isEnabled ? "eye.fill" : "eye.slash")
            }
            .buttonStyle(.glass)
            .foregroundStyle(screenContext.isEnabled ? Color.green : Color.secondary)
            .help(
                screenContext.isEnabled
                    ? "停止定时截图给 Codex"
                    : "允许定时截图给 Codex（共享屏幕上下文）"
            )
            .accessibilityLabel(
                screenContext.isEnabled
                    ? "停止共享屏幕上下文"
                    : "允许定时截图给 Codex"
            )

            Button(action: send) { Image(systemName: "paperplane.fill") }
                .buttonStyle(.glassProminent)
                .disabled(composer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(.white.opacity(0.075), in: .capsule)
        .overlay { Capsule().stroke(.white.opacity(0.1), lineWidth: 1) }
    }

    private func approvalBar(_ approval: AgentApprovalRequest, store: AgentStore) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.raised.fill").foregroundStyle(.orange)
            Text(approval.reason ?? approval.command ?? "Codex 有一个动作需要确认")
                .font(.caption).lineLimit(2)
            Spacer()
            Button("拒绝", role: .destructive) {
                Task { await store.resolveApproval(id: approval.id, response: .decline) }
            }
            .buttonStyle(.glass)
            Button("允许一次") {
                Task { await store.resolveApproval(id: approval.id, response: .accept) }
            }
            .buttonStyle(.glassProminent)
        }
        .padding(9)
        .background(.orange.opacity(0.1), in: .rect(cornerRadius: 13))
    }

    private var preferredApproval: AgentApprovalRequest? {
        guard let agentStore = agentContext.store else { return nil }
        if let threadID = agentStore.selectedThreadID {
            return agentStore.pendingApprovals.values.first(where: { $0.threadID == threadID })
                ?? agentStore.pendingApprovals.values.first
        }
        return agentStore.pendingApprovals.values.first
    }

    private var agentIsReady: Bool {
        guard let agentStore = agentContext.store else { return false }
        if case .ready = agentStore.connectionState { return true }
        return false
    }

    private func send() {
        let text = composer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        composer = ""
        if interactionState.isComposingNewTask {
            interactionState.isComposingNewTask = false
            onStartNewTask(text)
        } else {
            onSendPrompt(text)
        }
    }

    private func beginOrSendNewTask() {
        let text = composer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            interactionState.isComposingNewTask.toggle()
            if interactionState.isComposingNewTask {
                interactionState.requestComposerFocus()
            }
            return
        }
        composer = ""
        interactionState.isComposingNewTask = false
        onStartNewTask(text)
    }

    private var mascotTapGesture: some Gesture {
        TapGesture(count: 2)
            .exclusively(before: TapGesture(count: 1))
            .onEnded { result in
                switch result {
                case .first:
                    beginNewTaskFromMascot()
                case .second:
                    handleMascotSingleClick()
                }
            }
    }

    private func handleMascotSingleClick() {
        guard (!voiceInteraction.isRecording || voiceInteraction.isConversationEnabled),
              voiceInteraction.pendingTranscript == nil else { return }

        guard drawerState.isExpanded else {
            switch mascotModel.state {
            case .working, .waitingApproval, .success, .error:
                onMascotAction()
            default:
                onExpand()
                interactionState.requestComposerFocus()
            }
            return
        }

        onMascotAction()
        switch mascotModel.state {
        case .working, .waitingApproval, .success, .error:
            break
        default:
            interactionState.requestComposerFocus()
        }
    }

    private func beginNewTaskFromMascot() {
        guard (!voiceInteraction.isRecording || voiceInteraction.isConversationEnabled),
              voiceInteraction.pendingTranscript == nil else { return }

        interactionState.beginNewTask()
        if !drawerState.isExpanded {
            onExpand()
        }
        interactionState.requestComposerFocus()
    }

    private func focusComposerAfterExpansion() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard drawerState.isExpanded else { return }
            isComposerFocused = true
        }
    }

    private var composerPlaceholder: String {
        interactionState.isComposingNewTask
            ? "Hi，要我做个新任务吗？"
            : "Hi，要我做点什么。"
    }

    private func toggleVoice() {
        voiceInteraction.toggleConversation()
    }

    private func visibleTasks(in store: AgentStore) -> [AgentThread] {
        Array(store.threads.filter { thread in
            store.activeTurns[thread.id]?.status.isCompanionRunning == true
        }.sorted { left, right in
            return (left.updatedAt ?? left.createdAt ?? 0) > (right.updatedAt ?? right.createdAt ?? 0)
        }.prefix(8))
    }

    private var runningTaskIDs: [String] {
        guard let store = agentContext.store else { return [] }
        return store.activeTurns.compactMap { threadID, turn in
            turn.status.isCompanionRunning ? threadID : nil
        }.sorted()
    }

}

private struct DragonActionGlyph: View {
    let state: MascotState

    var body: some View {
        Group {
            switch state {
            case .listening: Image(systemName: "phone.fill").foregroundStyle(.green)
            case .thinking, .working: Image(systemName: "ellipsis.message.fill").foregroundStyle(.cyan)
            case .waitingApproval: Image(systemName: "hand.raised.fill").foregroundStyle(.orange)
            case .success: Image(systemName: "paperplane.fill").foregroundStyle(.green)
            case .error: Image(systemName: "exclamationmark.bubble.fill").foregroundStyle(.red)
            default: EmptyView()
            }
        }
        .font(.system(size: 30, weight: .bold))
        .symbolEffect(.bounce, value: state)
        .padding(9)
        .background(.ultraThinMaterial, in: .circle)
    }
}
