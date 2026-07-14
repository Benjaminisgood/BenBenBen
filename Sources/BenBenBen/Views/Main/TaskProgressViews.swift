import AppKit
import SwiftUI

struct DragonTaskThoughtCloud: View {
    let threads: [AgentThread]
    @ObservedObject var store: AgentStore
    let selectedThreadID: String?
    let onSelect: (String) -> Void

    var body: some View {
        Group {
            if let thread = orderedThreads.first {
                Button {
                    onSelect(thread.id)
                } label: {
                    TaskThoughtBubble()
                }
                .buttonStyle(.plain)
                .contextMenu {
                    ForEach(AgentTaskExecutionMode.allCases) { mode in
                        Button {
                            store.setExecutionMode(mode, for: thread.id)
                        } label: {
                            if store.executionMode(for: thread.id) == mode {
                                Label(mode.title, systemImage: "checkmark")
                            } else {
                                Text(mode.title)
                            }
                        }
                    }
                }
                .accessibilityLabel("正在思考：\(taskTitle(thread))")
                .accessibilityHint("点击切换到这个任务并查看进展")
            }
        }
        .frame(width: 52, height: 54)
        .animation(.snappy(duration: 0.32), value: selectedThreadID)
        .animation(.snappy(duration: 0.32), value: threads.map(\.id))
    }

    private var orderedThreads: [AgentThread] {
        guard let selectedThreadID,
              let selected = threads.first(where: { $0.id == selectedThreadID }) else {
            return threads
        }
        return [selected] + threads.filter { $0.id != selectedThreadID }
    }

    private func taskTitle(_ thread: AgentThread) -> String {
        let source = companionTaskTitle(thread, store: store)
        let normalized = source.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty { return "任务 \(thread.id.prefix(6))" }
        let limit = 24
        return normalized.count > limit ? String(normalized.prefix(limit - 1)) + "…" : normalized
    }
}

private struct TaskThoughtBubble: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var floating = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Circle()
                .fill(Color.cyan.opacity(0.14))
                .frame(width: 42, height: 42)
                .overlay {
                    Circle()
                        .stroke(Color.cyan.opacity(0.46), lineWidth: 1)
                }
                .overlay {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.cyan)
                        .opacity(floating ? 1 : 0.55)
                }

            Circle()
                .fill(Color.cyan.opacity(0.32))
                .frame(width: 8, height: 8)
                .offset(x: 6, y: 6)
            Circle()
                .fill(Color.cyan.opacity(0.22))
                .frame(width: 4, height: 4)
                .offset(x: 2, y: 14)
        }
        .frame(width: 48, height: 50)
        .offset(y: reduceMotion ? 0 : (floating ? -2 : 2))
        .scaleEffect(reduceMotion ? 1 : (floating ? 1.02 : 0.98))
        .shadow(color: .cyan.opacity(0.16), radius: 8)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(
                .easeInOut(duration: 1.35)
                    .repeatForever(autoreverses: true)
            ) {
                floating = true
            }
        }
    }
}

struct TaskProgressDetailCard: View {
    let threadID: String
    @ObservedObject var store: AgentStore
    let onClose: () -> Void
    var showsCloseButton = true
    var usesWindowLayout = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if let parentThreadID = thread?.parentThreadID {
                    Button {
                        store.selectedThreadID = parentThreadID
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.plain)
                    .help("返回主任务")
                    .accessibilityLabel("返回主任务")
                }
                Circle().fill(status.companionStatusColor).frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.callout.weight(.semibold)).lineLimit(1)
                    Text(status.companionStatusLabel).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await store.loadThreadHistory(id: threadID, force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .disabled(historyLoadState == .loading)
                .help("重新读取 Codex 历史记录")
                .accessibilityLabel("重新读取任务历史记录")
                if showsCloseButton {
                    Button(action: onClose) { Image(systemName: "xmark") }
                        .buttonStyle(.plain)
                }
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if let pendingRequest {
                        TaskPendingRequestView(request: pendingRequest, store: store)
                    }

                    switch historyLoadState {
                    case .loading:
                        HStack(spacing: 7) {
                            ProgressView().controlSize(.small)
                            Text("正在读取永久任务记录…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    case let .failed(message):
                        HStack(alignment: .top, spacing: 7) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("历史记录读取失败").font(.caption.weight(.semibold))
                                Text(message)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                Button("重试") {
                                    Task { await store.loadThreadHistory(id: threadID, force: true) }
                                }
                                .controlSize(.small)
                            }
                        }
                    case .loaded, nil:
                        EmptyView()
                    }

                    if !plan.isEmpty {
                        Text("计划").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(plan) { step in
                            HStack(alignment: .top, spacing: 7) {
                                Image(systemName: step.status.companionPlanIcon)
                                    .foregroundStyle(step.status.companionStatusColor)
                                Text(step.step).font(.caption).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    if !subagents.isEmpty {
                        Text("Agent 协作").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(subagents) { agent in
                            Button {
                                store.selectedThreadID = agent.threadID
                            } label: {
                                HStack(alignment: .top, spacing: 7) {
                                    Image(systemName: "person.2.fill")
                                        .foregroundStyle(agent.status.companionStatusColor)
                                        .frame(width: 13)
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 5) {
                                            Text(agent.displayName).font(.caption.weight(.medium))
                                            Text(agent.status.companionStatusLabel)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        if let prompt = agent.prompt, !prompt.isEmpty {
                                            Text(prompt)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                        }
                                        if let message = agent.message, !message.isEmpty {
                                            Text(message)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                        }
                                    }
                                    Spacer(minLength: 4)
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .help("查看这个 Agent 的永久执行记录")
                        }
                    }

                    if !activities.isEmpty {
                        Text("执行时间线").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(activities) { activity in
                            HStack(alignment: .top, spacing: 7) {
                                Image(systemName: activity.kind.companionSystemImage)
                                    .foregroundStyle(activity.status.companionStatusColor)
                                    .frame(width: 13)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(activity.title).font(.caption.weight(.medium))
                                    if let detail = activity.detail, !detail.isEmpty {
                                        Text(detail)
                                            .font(activity.kind == .command ? .caption2.monospaced() : .caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(usesWindowLayout ? nil : 3)
                                            .textSelection(.enabled)
                                    }
                                }
                            }
                        }
                    }

                    if activities.isEmpty, !liveReply.isEmpty {
                        Text("Ben龙 回复").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(liveReply)
                            .font(.caption)
                            .lineLimit(usesWindowLayout ? nil : 6)
                            .textSelection(.enabled)
                    } else if activities.isEmpty, let output = recentOutput, !output.isEmpty {
                        Text("最新输出").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(output)
                            .font(.caption2.monospaced())
                            .lineLimit(usesWindowLayout ? nil : 5)
                            .textSelection(.enabled)
                    } else if historyLoadState == .loaded,
                              plan.isEmpty,
                              subagents.isEmpty,
                              activities.isEmpty {
                        ContentUnavailableView(
                            "没有可显示的执行记录",
                            systemImage: "clock.badge.questionmark",
                            description: Text("Codex 已返回这个任务，但没有持久化 turn/items。")
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: usesWindowLayout ? .infinity : 210)

            HStack(spacing: 6) {
                Picker("权限", selection: executionModeBinding) {
                    ForEach(AgentTaskExecutionMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .fixedSize()
                .help("调整这个任务的权限")

                if let usage = store.tokenUsage[threadID] {
                    Label("\(usage.total.totalTokens)", systemImage: "gauge.with.dots.needle.33percent")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .help("已消耗 \(usage.total.totalTokens) tokens")
                }

                Spacer(minLength: 4)

                if let turn = store.activeTurns[threadID], turn.status.isCompanionRunning {
                    Text("继续对 Ben龙说话会引导此任务")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Button(role: .destructive) {
                        Task { await store.interrupt(threadID: threadID, turnID: turn.id) }
                    } label: {
                        Image(systemName: "stop.fill")
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .help("停止这个任务")
                    .accessibilityLabel("停止这个任务")
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.12), lineWidth: 1) }
        .task(id: threadID) {
            await store.loadThreadHistory(id: threadID)
        }
    }

    private var thread: AgentThread? { store.threads.first { $0.id == threadID } }
    private var title: String {
        guard let thread else { return "任务 \(threadID.prefix(6))" }
        return companionTaskTitle(thread, store: store)
    }
    private var status: String { store.activeTurns[threadID]?.status ?? thread?.status ?? "idle" }
    private var plan: [AgentPlanStep] { store.taskPlans[threadID] ?? [] }
    private var activities: [AgentTaskActivity] {
        let values = store.taskActivities[threadID] ?? []
        return usesWindowLayout ? values : Array(values.suffix(6))
    }
    private var subagents: [AgentSubagent] { store.taskSubagents[threadID] ?? [] }
    private var historyLoadState: AgentHistoryLoadState? { store.historyLoadStates[threadID] }
    private var liveReply: String {
        store.agentMessages[threadID]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
    private var recentOutput: String? {
        store.commandOutputsByThread[threadID]?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var executionModeBinding: Binding<AgentTaskExecutionMode> {
        Binding(
            get: { store.executionMode(for: threadID) },
            set: { store.setExecutionMode($0, for: threadID) }
        )
    }
    private var pendingRequest: AgentApprovalRequest? {
        store.pendingApprovals.values.first { $0.threadID == threadID }
    }
}

@MainActor
final class AgentTaskWindowController {
    private let agentContext: NotchAgentContext
    private var window: NSWindow?

    init(agentContext: NotchAgentContext) {
        self.agentContext = agentContext
    }

    var visibleThreadID: String? {
        guard window?.isVisible == true else { return nil }
        return agentContext.store?.selectedThreadID
    }

    func show(threadID: String? = nil) {
        if let threadID {
            agentContext.store?.selectedThreadID = threadID
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        taskWindow().makeKeyAndOrderFront(nil)
    }

    private func taskWindow() -> NSWindow {
        if let window { return window }
        let root = AgentTaskWindowView(agentContext: agentContext)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 610),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Ben龙 · 任务"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenAuxiliary]
        window.contentMinSize = NSSize(width: 680, height: 440)
        window.center()
        window.contentView = NSHostingView(rootView: root)
        self.window = window
        return window
    }
}

private struct AgentTaskWindowView: View {
    @ObservedObject var agentContext: NotchAgentContext
    @State private var visibleThreadID: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Label("任务", systemImage: "bubble.left.and.text.bubble.right.fill")
                    .font(.headline)
                Text("左侧切换最近任务；语音只会继续当前选中的一个任务")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 30)
            .padding(.bottom, 10)

            Divider()

            if let store = agentContext.store {
                HSplitView {
                    List(selection: $visibleThreadID) {
                        ForEach(sortedThreads(store)) { thread in
                            TaskHistoryRow(
                                thread: thread,
                                store: store,
                                isSelected: visibleThreadID == thread.id
                            )
                            .tag(thread.id)
                        }
                    }
                    .listStyle(.sidebar)
                    .frame(minWidth: 210, idealWidth: 250, maxWidth: 310)
                    .onAppear {
                        visibleThreadID = store.selectedThreadID
                    }
                    .onChange(of: visibleThreadID) { _, threadID in
                        Task { @MainActor in
                            await Task.yield()
                            guard store.selectedThreadID != threadID else { return }
                            store.selectedThreadID = threadID
                        }
                    }
                    .onChange(of: store.selectedThreadID) { _, threadID in
                        guard visibleThreadID != threadID else { return }
                        visibleThreadID = threadID
                    }

                    Group {
                        if let threadID = visibleThreadID ?? store.selectedThreadID {
                            TaskProgressDetailCard(
                                threadID: threadID,
                                store: store,
                                onClose: {},
                                showsCloseButton: false,
                                usesWindowLayout: true
                            )
                            .padding(14)
                        } else {
                            ContentUnavailableView(
                                "还没有任务",
                                systemImage: "waveform.badge.plus",
                                description: Text("点一下 Ben龙，然后直接说出第一个任务。")
                            )
                        }
                    }
                    .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ProgressView("正在连接 Codex…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(.regularMaterial)
    }

    private func sortedThreads(_ store: AgentStore) -> [AgentThread] {
        let ordered = store.threads.sorted {
            ($0.updatedAt ?? $0.createdAt ?? 0) > ($1.updatedAt ?? $1.createdAt ?? 0)
        }
        let ids = Set(ordered.map(\.id))
        let roots = ordered.filter { thread in
            guard let parentThreadID = thread.parentThreadID else { return true }
            return !ids.contains(parentThreadID)
        }
        var flattened: [AgentThread] = []
        var visited = Set<String>()

        func appendTree(_ thread: AgentThread) {
            guard visited.insert(thread.id).inserted else { return }
            flattened.append(thread)
            for child in ordered where child.parentThreadID == thread.id {
                appendTree(child)
            }
        }

        for root in roots { appendTree(root) }
        for orphan in ordered { appendTree(orphan) }
        return flattened
    }

}

private struct TaskHistoryRow: View {
    let thread: AgentThread
    @ObservedObject var store: AgentStore
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(status.companionStatusColor)
                .frame(width: 7, height: 7)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .lineLimit(2)
                HStack(spacing: 4) {
                    if thread.parentThreadID != nil {
                        Text(agentLabel)
                    }
                    Text(status.companionStatusLabel)
                }
                .font(.caption2)
                .foregroundStyle(isSelected ? Color.white.opacity(0.78) : Color.secondary)
            }
        }
        .padding(.vertical, 3)
        .padding(.leading, thread.parentThreadID == nil ? 0 : 14)
    }

    private var title: String {
        companionTaskTitle(thread, store: store)
    }

    private var status: String {
        store.activeTurns[thread.id]?.status ?? thread.status ?? "idle"
    }

    private var agentLabel: String {
        let name = thread.agentNickname ?? thread.agentRole
        return name.map { "Agent · \($0) ·" } ?? "Agent ·"
    }
}

@MainActor
private func companionTaskTitle(_ thread: AgentThread, store: AgentStore) -> String {
    if let persisted = store.taskPrompts[thread.id], !persisted.isEmpty {
        return persisted
    }
    if let name = thread.name, !name.isEmpty {
        return name
    }
    if let nickname = thread.agentNickname, !nickname.isEmpty { return nickname }
    if let role = thread.agentRole, !role.isEmpty { return role }
    let preview = thread.preview.trimmingCharacters(in: .whitespacesAndNewlines)
    if let userRange = preview.range(of: "\n[User]\n") {
        let userText = preview[userRange.upperBound...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !userText.isEmpty { return userText }
    }
    if preview.hasPrefix("[BenBenBen operating contract]") || preview.isEmpty {
        return "历史任务 \(thread.id.prefix(6))"
    }
    return preview
}

private struct TaskPendingRequestView: View {
    let request: AgentApprovalRequest
    @ObservedObject var store: AgentStore

    var body: some View {
        Group {
            if request.kind == .userInput, !request.userInputQuestions.isEmpty {
                TaskUserInputDecisionView(request: request, store: store)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Ben龙需要你判断", systemImage: "hand.raised.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                    Text(request.reason ?? request.command ?? "Codex 请求继续执行")
                        .font(.caption)
                        .textSelection(.enabled)
                    HStack {
                        Button("拒绝", role: .destructive) {
                            Task { await store.resolveApproval(id: request.id, response: .decline) }
                        }
                        .buttonStyle(.bordered)
                        if request.kind != .mcpElicitation {
                            Button("允许一次") {
                                Task { await store.resolveApproval(id: request.id, response: .accept) }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        if request.kind == .command || request.kind == .fileChange || request.kind == .permissions {
                            Button("本次会话允许") {
                                Task { await store.resolveApproval(id: request.id, response: .acceptForSession) }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .controlSize(.small)
                }
            }
        }
        .padding(10)
        .background(.orange.opacity(0.10), in: .rect(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(.orange.opacity(0.22), lineWidth: 1) }
    }
}

private struct TaskUserInputDecisionView: View {
    let request: AgentApprovalRequest
    @ObservedObject var store: AgentStore
    @State private var selections: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("请及时选择", systemImage: "questionmark.bubble.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
            ForEach(request.userInputQuestions) { question in
                VStack(alignment: .leading, spacing: 6) {
                    Text(question.header).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    Text(question.question).font(.caption)
                    if question.options.isEmpty {
                        Text("直接对 Ben龙说出答案")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        HStack(spacing: 6) {
                            ForEach(question.options) { option in
                                Button(option.label) { selections[question.id] = option.label }
                                    .buttonStyle(.bordered)
                                    .tint(selections[question.id] == option.label ? .cyan : .secondary)
                                    .help(option.description)
                            }
                        }
                        .controlSize(.small)
                    }
                }
            }
            if canSubmit {
                Button("确认选择") {
                    let answers = selections.mapValues { [$0] }
                    Task { await store.resolveApproval(id: request.id, response: .userInputAnswers(answers)) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .id(request.id.description)
    }

    private var canSubmit: Bool {
        let selectable = request.userInputQuestions.filter { !$0.options.isEmpty }
        return !selectable.isEmpty && selectable.allSatisfy { selections[$0.id] != nil }
    }
}

extension AgentTaskActivityKind {
    var companionSystemImage: String {
        switch self {
        case .lifecycle: return "sparkles"
        case .agent: return "person.2.fill"
        case .command: return "terminal"
        case .fileChange: return "doc.badge.gearshape"
        case .tool: return "wrench.and.screwdriver"
        case .reasoning: return "brain"
        case .message: return "text.bubble"
        case .approval: return "hand.raised"
        case .guidance: return "arrow.turn.down.right"
        }
    }
}

extension String {
    var companionStatusColor: Color {
        let value = lowercased()
        if value.contains("progress") || value == "running" || value == "started" || value == "active" { return .cyan }
        if value == "completed" || value == "success" || value == "shutdown" { return .green }
        if value == "failed" || value == "error" || value == "errored" || value == "systemerror" { return .red }
        if value == "waiting" || value == "pending" || value == "pendinginit" { return .orange }
        if value == "interrupted" || value == "cancelled" { return .secondary }
        return .secondary
    }

    var companionStatusLabel: String {
        let value = lowercased()
        if value.contains("progress") || value == "running" || value == "started" || value == "active" {
            return "正在执行，可随时继续引导"
        }
        if value == "completed" || value == "success" || value == "shutdown" { return "已完成" }
        if value == "failed" || value == "error" || value == "errored" || value == "systemerror" { return "执行失败" }
        if value == "interrupted" || value == "cancelled" { return "已停止" }
        if value == "waiting" || value == "pending" || value == "pendinginit" { return "等待中" }
        if value == "idle" { return "空闲" }
        if value == "notloaded" { return "历史任务" }
        if value == "declined" { return "已拒绝" }
        return "状态未知"
    }

    var companionPlanIcon: String {
        let value = lowercased()
        if value == "completed" { return "checkmark.circle.fill" }
        if value.contains("progress") { return "circle.dotted.circle.fill" }
        return "circle"
    }
}
