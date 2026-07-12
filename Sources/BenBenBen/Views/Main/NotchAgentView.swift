import AppKit
import Combine
import SwiftUI

@MainActor
final class NotchAgentContext: ObservableObject {
    @Published var store: AgentStore?

    init(store: AgentStore? = nil) {
        self.store = store
    }

    func updateStore(_ store: AgentStore?) {
        self.store = store
    }
}

struct NotchAgentView: View {
    @ObservedObject private var context: NotchAgentContext
    @ObservedObject private var mascotModel: MascotModel
    @ObservedObject private var voiceInteraction: VoiceInteractionController
    private let onSendPrompt: (String) -> Void

    @State private var composer = ""

    init(
        context: NotchAgentContext,
        mascotModel: MascotModel,
        voiceInteraction: VoiceInteractionController,
        onSendPrompt: @escaping (String) -> Void
    ) {
        _context = ObservedObject(wrappedValue: context)
        _mascotModel = ObservedObject(wrappedValue: mascotModel)
        _voiceInteraction = ObservedObject(wrappedValue: voiceInteraction)
        self.onSendPrompt = onSendPrompt
    }

    var body: some View {
        Group {
            if let store = context.store {
                NotchConnectedAgentView(
                    store: store,
                    mascotModel: mascotModel,
                    voiceInteraction: voiceInteraction,
                    composer: $composer,
                    onSendPrompt: onSendPrompt
                )
            } else {
                NotchDisconnectedAgentView(
                    mascotModel: mascotModel,
                    voiceInteraction: voiceInteraction,
                    composer: $composer,
                    onSendPrompt: onSendPrompt
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct NotchConnectedAgentView: View {
    @ObservedObject var store: AgentStore
    @ObservedObject var mascotModel: MascotModel
    @ObservedObject var voiceInteraction: VoiceInteractionController
    @Binding var composer: String
    let onSendPrompt: (String) -> Void

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            VStack(spacing: 8) {
                NotchAgentHeader(
                    store: store,
                    mascotModel: mascotModel
                )

                NotchAgentThreadBar(store: store)

                ScrollView {
                    VStack(spacing: 8) {
                        NotchAgentReplyCard(store: store)

                        if let approval = preferredApproval {
                            approvalCard(
                                approval,
                                additionalCount: max(pendingApprovals.count - 1, 0)
                            )
                        }
                    }
                    .padding(.horizontal, 1)
                }
                .scrollIndicators(.hidden)
                .frame(maxHeight: .infinity)

                NotchAgentComposer(
                    store: store,
                    voiceInteraction: voiceInteraction,
                    composer: $composer,
                    onSendPrompt: onSendPrompt
                )
            }
            .padding(10)
        }
        .controlSize(.small)
        .task(id: store.selectedThreadID) {
            guard let threadID = store.selectedThreadID,
                  store.activeTurns[threadID] == nil else { return }
            _ = await store.resumeThread(id: threadID)
        }
    }

    @ViewBuilder
    private func approvalCard(
        _ request: AgentApprovalRequest,
        additionalCount: Int
    ) -> some View {
        switch request.kind {
        case .userInput:
            NotchAgentUserInputCard(
                request: request,
                additionalCount: additionalCount,
                store: store
            )
        case .mcpElicitation:
            NotchAgentMCPCard(
                request: request,
                additionalCount: additionalCount,
                store: store
            )
        default:
            NotchAgentApprovalCard(
                request: request,
                additionalCount: additionalCount,
                store: store
            )
        }
    }

    private var pendingApprovals: [AgentApprovalRequest] {
        Array(store.pendingApprovals.values)
    }

    private var preferredApproval: AgentApprovalRequest? {
        guard let selectedThreadID = store.selectedThreadID else {
            return pendingApprovals.first
        }
        return pendingApprovals.first(where: { $0.threadID == selectedThreadID })
            ?? pendingApprovals.first
    }
}

private struct NotchDisconnectedAgentView: View {
    @ObservedObject var mascotModel: MascotModel
    @ObservedObject var voiceInteraction: VoiceInteractionController
    @Binding var composer: String
    let onSendPrompt: (String) -> Void

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    MascotView(
                        state: mascotModel.presentedState,
                        size: 36,
                        revision: mascotModel.presentationRevision
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ben龙 Agent")
                            .font(.headline)
                        Text(mascotModel.bubbleText ?? "正在等待 Codex 运行时")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Label("Agent 尚未连接", systemImage: "bolt.horizontal.circle")
                        .font(.callout.weight(.semibold))
                    Text("页面会在 NotchAgentContext 收到 AgentStore 后自动切换；你也可以先输入任务。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .glassEffect(.regular, in: .rect(cornerRadius: 12))

                Spacer(minLength: 0)

                NotchOfflineAgentComposer(
                    voiceInteraction: voiceInteraction,
                    composer: $composer,
                    onSendPrompt: onSendPrompt
                )
            }
            .padding(12)
        }
        .controlSize(.small)
    }
}

private struct NotchAgentHeader: View {
    @ObservedObject var store: AgentStore
    @ObservedObject var mascotModel: MascotModel

    var body: some View {
        HStack(spacing: 10) {
            MascotView(
                state: mascotModel.presentedState,
                size: 34,
                revision: mascotModel.presentationRevision
            )

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(store.connectionState.notchColor)
                        .frame(width: 7, height: 7)
                    Text("Ben龙 Agent")
                        .font(.callout.weight(.semibold))
                    Text(store.connectionState.notchLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text(accountLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let userCode = store.loginFlow?.userCode, !userCode.isEmpty {
                    HStack(spacing: 4) {
                        Text("代码 \(userCode)")
                            .font(.caption2.monospaced().weight(.semibold))
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(userCode, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.plain)
                        .help("复制登录代码")
                    }
                }
            }

            Spacer(minLength: 8)

            if store.connectionState.isStarting {
                ProgressView()
                    .controlSize(.mini)
            }

            if needsLogin {
                Button("登录", systemImage: "person.crop.circle.badge.questionmark") {
                    beginLogin()
                }
                .buttonStyle(.glassProminent)
            }

            Button {
                Task {
                    await store.connect()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.glass)
            .help("重新连接 Codex")
        }
        .frame(minHeight: 34)
    }

    private var needsLogin: Bool {
        guard let status = store.accountStatus else { return false }
        return status.requiresOpenAIAuth || status.account == nil
    }

    private var accountLabel: String {
        guard let status = store.accountStatus else {
            return "正在检查账户"
        }
        guard let account = status.account else {
            return status.requiresOpenAIAuth ? "需要 ChatGPT 登录" : "未登录"
        }
        return account.notchDisplayText
    }

    private func beginLogin() {
        Task {
            await store.beginChatGPTLogin()
            let url = store.loginFlow?.authorizationURL ?? store.loginFlow?.verificationURL
            if let url {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

private struct NotchAgentThreadBar: View {
    @ObservedObject var store: AgentStore

    var body: some View {
        HStack(spacing: 8) {
            Label("最近线程", systemImage: "text.bubble")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Menu {
                if store.threads.isEmpty {
                    Text("暂无线程")
                } else {
                    ForEach(store.threads) { thread in
                        Button {
                            select(thread)
                        } label: {
                            if thread.id == store.selectedThreadID {
                                Label(thread.notchTitle, systemImage: "checkmark")
                            } else {
                                Text(thread.notchTitle)
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(selectedThreadTitle)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
                .frame(maxWidth: 260, alignment: .leading)
            }
            .buttonStyle(.glass)

            Spacer(minLength: 4)

            if !store.pendingApprovals.isEmpty {
                Label("\(store.pendingApprovals.count)", systemImage: "hand.raised.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                    .help("待审批")
            }

            Button("新建", systemImage: "plus") {
                Task {
                    _ = await store.createThread()
                }
            }
            .buttonStyle(.glass)
        }
        .frame(minHeight: 28)
    }

    private var selectedThreadTitle: String {
        guard let selectedThreadID = store.selectedThreadID,
              let thread = store.threads.first(where: { $0.id == selectedThreadID }) else {
            return store.threads.isEmpty ? "尚无线程" : "选择线程"
        }
        return thread.notchTitle
    }

    private func select(_ thread: AgentThread) {
        guard thread.id != store.selectedThreadID else { return }
        store.selectedThreadID = thread.id
    }
}

private struct NotchAgentReplyCard: View {
    @ObservedObject var store: AgentStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: isRunning ? "sparkles" : "quote.bubble")
                    .foregroundStyle(isRunning ? Color.accentColor : Color.secondary)
                Text(isRunning ? "正在回复" : "当前回复")
                    .font(.caption.weight(.semibold))
                if isRunning {
                    ProgressView()
                        .controlSize(.mini)
                }
                Spacer()
                if let status = selectedTurn?.status, !status.isEmpty {
                    Text(status)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Text(replySummary)
                .font(.callout)
                .foregroundStyle(replySummaryIsPlaceholder ? .secondary : .primary)
                .lineLimit(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let error = store.lastError, !error.isEmpty {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            } else if let warning = store.protocolVersionWarning, !warning.isEmpty {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
        }
        .padding(11)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }

    private var selectedThread: AgentThread? {
        guard let selectedThreadID = store.selectedThreadID else { return nil }
        return store.threads.first(where: { $0.id == selectedThreadID })
    }

    private var selectedTurn: AgentTurn? {
        guard let selectedThreadID = store.selectedThreadID else { return nil }
        return store.activeTurns[selectedThreadID]
    }

    private var isRunning: Bool {
        selectedTurn?.status.isNotchAgentRunning == true
    }

    private var replySummary: String {
        if let selectedThreadID = store.selectedThreadID {
            let liveReply = store.agentMessages[selectedThreadID]?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !liveReply.isEmpty {
                return liveReply
            }
        }
        if let preview = selectedThread?.preview.trimmingCharacters(in: .whitespacesAndNewlines),
           !preview.isEmpty {
            return preview
        }
        return store.selectedThreadID == nil
            ? "新建或选择一个线程，然后告诉 Ben龙 你想完成什么。"
            : "这个线程已经准备好了。"
    }

    private var replySummaryIsPlaceholder: Bool {
        guard let selectedThreadID = store.selectedThreadID else { return true }
        let liveReply = store.agentMessages[selectedThreadID]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let preview = selectedThread?.preview.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return liveReply.isEmpty && preview.isEmpty
    }
}

private struct NotchAgentApprovalCard: View {
    let request: AgentApprovalRequest
    let additionalCount: Int
    @ObservedObject var store: AgentStore
    @State private var showsDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Image(systemName: request.kind.notchSystemImage)
                    .foregroundStyle(.orange)
                Text(request.kind.notchTitle)
                    .font(.caption.weight(.semibold))
                if additionalCount > 0 {
                    Text("另有 \(additionalCount) 项")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("需要确认")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
            }

            if let reason = request.reason, !reason.isEmpty {
                Text(reason)
                    .font(.caption)
                    .lineLimit(2)
            }

            if let command = request.command, !command.isEmpty {
                Text(command)
                    .font(.caption2.monospaced())
                    .lineLimit(2)
                    .textSelection(.enabled)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary, in: .rect(cornerRadius: 7))
            }

            if let detailText {
                DisclosureGroup(isExpanded: $showsDetails) {
                    ScrollView([.horizontal, .vertical]) {
                        Text(detailText)
                            .font(.caption2.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 96)
                    .padding(.top, 4)
                } label: {
                    Text(request.kind == .permissions ? "查看权限范围" : "查看修改详情")
                        .font(.caption.weight(.semibold))
                }
            }

            HStack(spacing: 8) {
                if let cwd = request.cwd, !cwd.isEmpty {
                    Label(URL(fileURLWithPath: cwd).lastPathComponent, systemImage: "folder")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button("拒绝", role: .destructive) {
                    resolve(.decline)
                }
                .buttonStyle(.glass)

                Button("允许一次") {
                    resolve(.accept)
                }
                .buttonStyle(.glassProminent)
            }
        }
        .padding(11)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }

    private var detailText: String? {
        if request.kind == .fileChange || request.kind == .legacyFileChange {
            if let threadID = request.threadID,
               let diff = store.diffs[threadID],
               !diff.isEmpty {
                return diff
            }
            if let data = try? JSONEncoder.pretty.encode(request.rawParams) {
                return String(data: data, encoding: .utf8)
            }
        }
        guard request.kind == .permissions,
              let permissions = request.rawParams["permissions"],
              let data = try? JSONEncoder.pretty.encode(permissions) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func resolve(_ response: AgentApprovalResponse) {
        Task {
            await store.resolveApproval(id: request.id, response: response)
        }
    }
}

private struct NotchAgentUserInputCard: View {
    let request: AgentApprovalRequest
    let additionalCount: Int
    @ObservedObject var store: AgentStore
    @State private var answers: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Agent 提问", systemImage: "questionmark.bubble")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                Spacer()
                if additionalCount > 0 {
                    Text("另有 \(additionalCount) 项")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(questions) { question in
                VStack(alignment: .leading, spacing: 6) {
                    Text(question.text)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)

                    if !question.options.isEmpty {
                        ScrollView(.horizontal) {
                            HStack(spacing: 6) {
                                ForEach(question.options, id: \.self) { option in
                                    Button(option) { answers[question.id] = option }
                                        .buttonStyle(.glass)
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                    }

                    TextField("输入回答", text: answerBinding(for: question.id))
                        .textFieldStyle(.roundedBorder)
                }
            }

            HStack {
                Button("跳过", role: .cancel) { resolve([:]) }
                    .buttonStyle(.glass)
                Spacer()
                Button("提交", systemImage: "arrow.up") { submit() }
                    .buttonStyle(.glassProminent)
                    .disabled(resolvedAnswers.isEmpty)
            }
        }
        .padding(11)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }

    private var questions: [NotchQuestion] {
        let decoded = request.rawParams["questions"]?.arrayValue?.enumerated().map { index, json in
            NotchQuestion(
                id: json["id"]?.stringValue ?? "answer_\(index)",
                text: json["question"]?.stringValue
                    ?? json["header"]?.stringValue
                    ?? "Agent 需要你的回答",
                options: json["options"]?.arrayValue?.compactMap {
                    $0["label"]?.stringValue ?? $0.stringValue
                } ?? []
            )
        } ?? []
        if !decoded.isEmpty { return decoded }
        return [NotchQuestion(
            id: "answer",
            text: request.reason ?? "Agent 需要你的回答",
            options: []
        )]
    }

    private func submit() {
        guard !resolvedAnswers.isEmpty else { return }
        resolve(resolvedAnswers)
    }

    private var resolvedAnswers: [String: [String]] {
        answers.reduce(into: [:]) { result, entry in
            let value = entry.value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                result[entry.key] = [value]
            }
        }
    }

    private func answerBinding(for id: String) -> Binding<String> {
        Binding(
            get: { answers[id, default: ""] },
            set: { answers[id] = $0 }
        )
    }

    private func resolve(_ answers: [String: [String]]) {
        Task {
            await store.resolveApproval(id: request.id, response: .userInputAnswers(answers))
        }
    }
}

private struct NotchQuestion: Identifiable {
    let id: String
    let text: String
    let options: [String]
}

private struct NotchAgentMCPCard: View {
    let request: AgentApprovalRequest
    let additionalCount: Int
    @ObservedObject var store: AgentStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("MCP 请求", systemImage: "shippingbox")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                Spacer()
                if additionalCount > 0 {
                    Text("另有 \(additionalCount) 项")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Text(message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("取消") { resolve(.cancel) }
                    .buttonStyle(.glass)
                Spacer()
                Button("拒绝", role: .destructive) { resolve(.decline) }
                    .buttonStyle(.glassProminent)
            }
        }
        .padding(11)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }

    private var message: String {
        request.rawParams["message"]?.stringValue
            ?? request.reason
            ?? "MCP 服务请求额外信息；当前刘海界面可取消或拒绝该请求。"
    }

    private func resolve(_ response: AgentApprovalResponse) {
        Task { await store.resolveApproval(id: request.id, response: response) }
    }
}

private struct NotchAgentComposer: View {
    @ObservedObject var store: AgentStore
    @ObservedObject var voiceInteraction: VoiceInteractionController
    @Binding var composer: String
    let onSendPrompt: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("问 Ben龙，或让它替你完成任务…", text: $composer, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...3)
                .onSubmit(submit)

            HStack(spacing: 7) {
                composerStatus
                Spacer(minLength: 6)

                if let pendingTranscript = voiceInteraction.pendingTranscript {
                    Button {
                        voiceInteraction.cancelPending()
                    } label: {
                        Label(
                            voiceInteraction.countdownSeconds.map { "\($0) 秒" } ?? "取消",
                            systemImage: "xmark.circle"
                        )
                    }
                    .buttonStyle(.glass)
                    .help(pendingTranscript)
                }

                Button {
                    toggleVoice()
                } label: {
                    Image(systemName: voiceInteraction.isConversationEnabled ? "stop.circle.fill" : "mic")
                }
                .buttonStyle(.glass)
                .foregroundStyle(voiceInteraction.isConversationEnabled ? Color.red : Color.primary)
                .help(voiceInteraction.isConversationEnabled ? "关闭持续语音" : "开启持续语音")

                if let selectedThreadID = store.selectedThreadID,
                   let turn = store.activeTurns[selectedThreadID],
                   turn.status.isNotchAgentRunning {
                    Button("停止", systemImage: "stop.fill") {
                        Task {
                            await store.interrupt(threadID: selectedThreadID, turnID: turn.id)
                        }
                    }
                    .buttonStyle(.glass)
                }

                Button("发送", systemImage: "arrow.up") {
                    submit()
                }
                .buttonStyle(.glassProminent)
                .disabled(trimmedComposer.isEmpty)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }

    @ViewBuilder
    private var composerStatus: some View {
        if voiceInteraction.isRecording {
            Text(voiceInteraction.liveTranscript.isEmpty ? "正在听…" : voiceInteraction.liveTranscript)
                .foregroundStyle(.red)
        } else if voiceInteraction.isConversationEnabled, voiceInteraction.isSpeaking {
            Text("Ben龙 正在说话…")
                .foregroundStyle(.green)
        } else if let error = voiceInteraction.lastError {
            Text(error)
                .foregroundStyle(.red)
        } else {
            Text("Return 发送")
                .foregroundStyle(.secondary)
        }
    }

    private var trimmedComposer: String {
        composer.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submit() {
        guard !trimmedComposer.isEmpty else { return }
        let text = trimmedComposer
        composer = ""
        onSendPrompt(text)
    }

    private func toggleVoice() {
        voiceInteraction.toggleConversation()
    }
}

private struct NotchOfflineAgentComposer: View {
    @ObservedObject var voiceInteraction: VoiceInteractionController
    @Binding var composer: String
    let onSendPrompt: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("先告诉 Ben龙 你想做什么…", text: $composer, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...3)
                .onSubmit(submit)

            HStack(spacing: 8) {
                Text(voiceInteraction.isRecording ? "持续聆听中…" : "连接完成后会自动继续")
                    .font(.caption2)
                    .foregroundStyle(voiceInteraction.isRecording ? Color.red : Color.secondary)
                    .lineLimit(1)
                Spacer()

                if let pendingTranscript = voiceInteraction.pendingTranscript {
                    Button {
                        voiceInteraction.cancelPending()
                    } label: {
                        Label(
                            voiceInteraction.countdownSeconds.map { "\($0) 秒" } ?? "取消",
                            systemImage: "xmark.circle"
                        )
                    }
                    .buttonStyle(.glass)
                    .help(pendingTranscript)
                }

                Button {
                    toggleVoice()
                } label: {
                    Image(systemName: voiceInteraction.isConversationEnabled ? "stop.circle.fill" : "mic")
                }
                .buttonStyle(.glass)

                Button("发送", systemImage: "arrow.up") {
                    submit()
                }
                .buttonStyle(.glassProminent)
                .disabled(trimmedComposer.isEmpty)
            }
        }
        .padding(10)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }

    private var trimmedComposer: String {
        composer.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submit() {
        guard !trimmedComposer.isEmpty else { return }
        let text = trimmedComposer
        composer = ""
        onSendPrompt(text)
    }

    private func toggleVoice() {
        voiceInteraction.toggleConversation()
    }
}

private extension AgentConnectionState {
    var notchLabel: String {
        switch self {
        case .disconnected:
            return "未连接"
        case .starting:
            return "连接中"
        case .ready(let info):
            return "Codex \(info.installation.version)"
        case .failed:
            return "连接失败"
        }
    }

    var notchColor: Color {
        switch self {
        case .ready:
            return .green
        case .starting:
            return .yellow
        case .failed:
            return .red
        case .disconnected:
            return .secondary
        }
    }

    var isStarting: Bool {
        if case .starting = self { return true }
        return false
    }
}

private extension AgentAccount {
    var notchDisplayText: String {
        switch self {
        case .apiKey:
            return "OpenAI API key"
        case .chatGPT(let email, let plan):
            if let email, !email.isEmpty {
                return "\(email) · \(plan)"
            }
            return "ChatGPT · \(plan)"
        case .amazonBedrock:
            return "Amazon Bedrock"
        case .unknown(let type, _):
            return type
        }
    }
}

private extension AgentThread {
    var notchTitle: String {
        let source: String
        if let name, !name.isEmpty {
            source = name
        } else if !preview.isEmpty {
            source = preview
        } else {
            source = "线程 \(id.prefix(6))"
        }

        guard source.count > 32 else { return source }
        return String(source.prefix(29)) + "…"
    }
}

private extension AgentApprovalKind {
    var notchTitle: String {
        switch self {
        case .command, .legacyCommand:
            return "运行命令"
        case .fileChange, .legacyFileChange:
            return "修改文件"
        case .permissions:
            return "权限请求"
        case .userInput:
            return "Agent 提问"
        case .mcpElicitation:
            return "MCP 请求"
        }
    }

    var notchSystemImage: String {
        switch self {
        case .command, .legacyCommand:
            return "terminal"
        case .fileChange, .legacyFileChange:
            return "doc.badge.gearshape"
        case .permissions:
            return "hand.raised"
        case .userInput:
            return "questionmark.bubble"
        case .mcpElicitation:
            return "shippingbox"
        }
    }
}

private extension String {
    var isNotchAgentRunning: Bool {
        let normalized = lowercased()
        return normalized.contains("progress")
            || normalized == "running"
            || normalized == "started"
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
