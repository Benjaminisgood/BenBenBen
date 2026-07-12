import SwiftUI

/// The notch is a character, not a miniature dashboard. A single click brings
/// Ben龙 closer; a double click opens the five persistent artifact canvases.
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

    let layout: NotchLayout
    let onSendPrompt: (String) -> Void
    let onExpand: () -> Void
    let onMascotAction: () -> Void
    let onOpenSettings: () -> Void
    let onCollapse: () -> Void

    @State private var composer = ""
    @State private var dragonHasWalkedOut = false

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
        .accessibilityHint(drawerState.isExpanded ? "双击打开五类共同窗口" : "单击唤醒，双击打开共同窗口，按住说话")
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
        Button {
            guard !voiceInteraction.isRecording,
                  voiceInteraction.pendingTranscript == nil else { return }
            onExpand()
        } label: {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                MascotView(
                    state: mascotModel.presentedState,
                    size: min(82, layout.compactSize.height * 1.18),
                    revision: mascotModel.presentationRevision
                )
                .offset(y: 24)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("唤醒 Ben龙")
        .accessibilityHint("单击进入近身对话，双击打开五类共同窗口")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onExpand() }
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

            Spacer(minLength: 0)

            ZStack(alignment: .topTrailing) {
                MascotView(
                    state: mascotModel.presentedState,
                    size: 232,
                    revision: mascotModel.presentationRevision
                )
                .scaleEffect(dragonHasWalkedOut ? 1 : 0.34, anchor: .top)
                .offset(y: dragonHasWalkedOut ? 8 : -96)
                DragonActionGlyph(state: mascotModel.presentedState)
                    .offset(x: -18, y: 14)
            }
            .onTapGesture(perform: onMascotAction)
            .help("单击互动；双击进入五类共同窗口")

            replyBubble.frame(maxWidth: 520)
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
            if screenContext.isEnabled {
                Image(systemName: "eye.fill").font(.caption2).foregroundStyle(.green)
                    .help(screenContext.status.label)
            }
        }
        .foregroundStyle(.secondary)
    }

    private var replyBubble: some View {
        Text(replyText)
            .font(.callout)
            .lineLimit(4)
            .multilineTextAlignment(.center)
            .textSelection(.enabled)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(.white.opacity(0.075), in: .rect(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.08), lineWidth: 1) }
    }

    private var composerBar: some View {
        HStack(spacing: 8) {
            Button(action: toggleVoice) {
                Image(systemName: voiceInteraction.isRecording ? "phone.down.fill" : "phone.fill")
            }
            .buttonStyle(.glassProminent)
            .tint(voiceInteraction.isRecording ? .red : .green)
            .help(voiceInteraction.isRecording ? "结束通话并发送" : "和 Ben龙 说话")

            TextField("直接和 Ben龙 说，或输入要共同完成的事…", text: $composer, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...3)
                .onSubmit(send)

            Button {
                screenContext.isEnabled.toggle()
            } label: {
                Image(systemName: screenContext.isEnabled ? "eye.fill" : "eye.slash")
            }
            .buttonStyle(.glass)
            .foregroundStyle(screenContext.isEnabled ? Color.green : Color.secondary)
            .help(screenContext.isEnabled ? "停止共享屏幕上下文" : "允许 Codex 看到发送时的当前屏幕")

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

    private var replyText: String {
        if voiceInteraction.isRecording {
            return voiceInteraction.liveTranscript.isEmpty ? "我在听…" : voiceInteraction.liveTranscript
        }
        if let bubble = mascotModel.bubbleText, !bubble.isEmpty { return bubble }
        guard let agentStore = agentContext.store else { return "我正在连接 Codex…" }
        if let threadID = agentStore.selectedThreadID {
            let reply = agentStore.agentMessages[threadID]?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !reply.isEmpty { return reply }
        }
        return "告诉我你正在做什么。双击我，打开 HTML、PY、MD、SCRIPTS、PLIST 五个共同窗口。"
    }

    private func send() {
        let text = composer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        composer = ""
        onSendPrompt(text)
    }

    private func toggleVoice() {
        if voiceInteraction.isRecording {
            voiceInteraction.stopRecording()
        } else {
            Task { await voiceInteraction.startRecording() }
        }
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
