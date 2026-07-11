import AppKit
import SwiftUI

struct AgentRouteView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if let store = model.agentStore {
                AgentWorkspaceView(store: store)
                    .environmentObject(model)
            } else {
                ContentUnavailableView {
                    Label("Connecting to Codex", systemImage: "sparkles")
                } description: {
                    Text("BenBenBen uses your installed Codex executable and current ChatGPT login.")
                } actions: {
                    Button("Try again") {
                        Task { await model.bootstrapAgent() }
                    }
                    .buttonStyle(.glassProminent)
                }
            }
        }
        .navigationTitle("Agents")
    }
}

private struct AgentWorkspaceView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var store: AgentStore

    @State private var threadSearch = ""
    @State private var composer = ""
    @State private var threadPendingArchive: AgentThread?

    var body: some View {
        HSplitView {
            threadColumn
                .frame(minWidth: 230, idealWidth: 270, maxWidth: 340)

            conversationColumn
                .frame(minWidth: 480, maxWidth: .infinity)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { _ = await store.createThread() }
                } label: {
                    Label("New thread", systemImage: "square.and.pencil")
                }
            }
        }
        .sheet(item: $threadPendingArchive) { thread in
            VStack(alignment: .leading, spacing: 18) {
                Text("Archive this Codex thread?")
                    .font(.title2.bold())
                Text(thread.displayTitle)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Cancel") { threadPendingArchive = nil }
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Archive") {
                        Task { await store.archiveThread(id: thread.id) }
                        threadPendingArchive = nil
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
            .frame(width: 420)
        }
    }

    private var threadColumn: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search threads", text: $threadSearch)
                    .textFieldStyle(.plain)
                    .onSubmit(reloadThreads)
                if !threadSearch.isEmpty {
                    Button {
                        threadSearch = ""
                        reloadThreads()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
            .padding(10)

            Divider()

            if store.threads.isEmpty {
                ContentUnavailableView(
                    "No Codex threads",
                    systemImage: "text.bubble",
                    description: Text("Create one to work with your notes, scripts, and jobs.")
                )
            } else {
                List(selection: $store.selectedThreadID) {
                    ForEach(store.threads) { thread in
                        AgentThreadRow(thread: thread)
                            .tag(thread.id)
                            .contextMenu {
                                Button("Archive", role: .destructive) {
                                    threadPendingArchive = thread
                                }
                            }
                    }
                }
                .listStyle(.sidebar)
                .onChange(of: store.selectedThreadID) { _, threadID in
                    guard let threadID else { return }
                    Task { _ = await store.resumeThread(id: threadID) }
                }
            }

            Divider()
            connectionFooter
        }
        .background(.background.secondary)
    }

    private var connectionFooter: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(store.connectionState.indicatorColor)
                .frame(width: 7, height: 7)
            Text(store.connectionState.label)
                .font(.caption)
                .lineLimit(1)
            Spacer()
            Button {
                Task {
                    await store.connect()
                    await store.reloadThreads()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
        }
        .padding(10)
    }

    private var conversationColumn: some View {
        VStack(spacing: 0) {
            if let warning = store.protocolVersionWarning {
                AgentBanner(text: warning, color: .orange, systemImage: "exclamationmark.triangle")
            }
            if let error = store.lastError {
                AgentBanner(text: error, color: .red, systemImage: "xmark.octagon")
            }
            if store.accountStatus?.requiresOpenAIAuth == true || store.accountStatus?.account == nil {
                loginBanner
            }

            if let threadID = store.selectedThreadID {
                AgentConversationView(
                    threadID: threadID,
                    entries: model.agentConversation[threadID] ?? [],
                    liveAgentMessage: liveAgentMessage(for: threadID),
                    commandOutput: store.commandOutputs.sorted { $0.key < $1.key }.last?.value,
                    diff: store.diffs[threadID]
                )
            } else {
                ContentUnavailableView(
                    "Start a conversation",
                    systemImage: "sparkles",
                    description: Text("Threads default to ~/keyoti with workspace-write and user-reviewed approvals.")
                )
                .frame(maxHeight: .infinity)
            }

            Divider()
            composerBar
        }
    }

    private var loginBanner: some View {
        AgentBanner(text: "Codex needs your ChatGPT sign-in.", color: .blue, systemImage: "person.crop.circle.badge.questionmark") {
            Button("Sign in") {
                Task {
                    await store.beginChatGPTLogin()
                    if let url = store.loginFlow?.authorizationURL {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            .buttonStyle(.glass)
        }
    }

    private var composerBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Ask Codex to answer or do something…", text: $composer, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...7)
                .onSubmit(sendComposer)

            HStack {
                Label("~/keyoti", systemImage: "folder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()

                if let threadID = store.selectedThreadID,
                   let turn = store.activeTurns[threadID],
                   turn.status.isAgentRunning {
                    Button("Stop", systemImage: "stop.fill") {
                        Task { await store.interrupt(threadID: threadID, turnID: turn.id) }
                    }
                    .buttonStyle(.glass)
                }

                Button("Send", systemImage: "arrow.up") {
                    sendComposer()
                }
                .buttonStyle(.glassProminent)
                .disabled(composer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
    }

    private func sendComposer() {
        let text = composer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        composer = ""
        model.sendAgentComposer(text)
    }

    private func reloadThreads() {
        let term = threadSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            await store.reloadThreads(query: AgentThreadListQuery(searchTerm: term.isEmpty ? nil : term))
        }
    }

    private func liveAgentMessage(for threadID: String) -> String? {
        guard let turn = store.activeTurns[threadID], turn.status.isAgentRunning else { return nil }
        return store.agentMessages[threadID]
    }
}

private struct AgentThreadRow: View {
    let thread: AgentThread

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(thread.displayTitle)
                .font(.callout.weight(.semibold))
                .lineLimit(2)
            HStack {
                if let cwd = thread.cwd {
                    Text(URL(fileURLWithPath: cwd).lastPathComponent)
                        .lineLimit(1)
                }
                Spacer()
                if let updatedAt = thread.updatedAt {
                    Text(Date(timeIntervalSince1970: updatedAt), style: .relative)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 5)
    }
}

private struct AgentConversationView: View {
    let threadID: String
    let entries: [AgentConversationEntry]
    let liveAgentMessage: String?
    let commandOutput: String?
    let diff: String?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if entries.isEmpty && (liveAgentMessage?.isEmpty ?? true) {
                        ContentUnavailableView(
                            "Thread ready",
                            systemImage: "sparkles",
                            description: Text("Codex owns the durable thread history; live turns appear here.")
                        )
                        .frame(maxWidth: .infinity, minHeight: 360)
                    }

                    ForEach(entries) { entry in
                        AgentMessageBubble(entry: entry)
                    }

                    if let liveAgentMessage, !liveAgentMessage.isEmpty {
                        AgentMessageBubble(
                            entry: AgentConversationEntry(role: .assistant, text: liveAgentMessage),
                            isStreaming: true
                        )
                    }

                    if let commandOutput, !commandOutput.isEmpty {
                        AgentCodeCard(title: "Command output", systemImage: "terminal", text: commandOutput)
                    }

                    if let diff, !diff.isEmpty {
                        AgentCodeCard(title: "Proposed diff", systemImage: "doc.text.magnifyingglass", text: diff)
                    }

                    Color.clear.frame(height: 1).id("agent-bottom")
                }
                .frame(maxWidth: 820, alignment: .leading)
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: entries.count) { _, _ in
                withAnimation { proxy.scrollTo("agent-bottom", anchor: .bottom) }
            }
            .onChange(of: liveAgentMessage) { _, _ in
                proxy.scrollTo("agent-bottom", anchor: .bottom)
            }
        }
    }
}

private struct AgentMessageBubble: View {
    let entry: AgentConversationEntry
    var isStreaming = false

    var body: some View {
        HStack {
            if entry.role == .user { Spacer(minLength: 80) }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: entry.role == .user ? "person.fill" : "sparkles")
                    Text(entry.role == .user ? "Ben" : "Ben龙 · Codex")
                    if isStreaming {
                        ProgressView().controlSize(.mini)
                    }
                }
                .font(.caption.bold())
                .foregroundStyle(.secondary)

                Text(.init(entry.text))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .background(
                entry.role == .user ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.10),
                in: .rect(cornerRadius: 16)
            )
            if entry.role == .assistant { Spacer(minLength: 80) }
        }
    }
}

private struct AgentCodeCard: View {
    let title: String
    let systemImage: String
    let text: String

    var body: some View {
        GroupBox {
            ScrollView(.horizontal) {
                Text(text)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } label: {
            Label(title, systemImage: systemImage)
        }
    }
}

private struct AgentBanner<Actions: View>: View {
    let text: String
    let color: Color
    let systemImage: String
    @ViewBuilder let actions: Actions

    init(
        text: String,
        color: Color,
        systemImage: String,
        @ViewBuilder actions: () -> Actions
    ) {
        self.text = text
        self.color = color
        self.systemImage = systemImage
        self.actions = actions()
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage).foregroundStyle(color)
            Text(text).font(.caption).lineLimit(3)
            Spacer()
            actions
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(color.opacity(0.10))
    }
}

private extension AgentBanner where Actions == EmptyView {
    init(text: String, color: Color, systemImage: String) {
        self.init(text: text, color: color, systemImage: systemImage) { EmptyView() }
    }
}

struct AgentInspectorView: View {
    @ObservedObject var store: AgentStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GroupBox("Runtime") {
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Status", value: store.connectionState.label)
                        LabeledContent("Account", value: store.accountStatus?.displayText ?? "Checking")
                        LabeledContent("Policy", value: "on-request")
                        LabeledContent("Sandbox", value: "workspace-write")
                    }
                }

                if store.pendingApprovals.isEmpty {
                    GroupBox("Approvals") {
                        Label("Nothing waiting", systemImage: "checkmark.shield")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    ForEach(Array(store.pendingApprovals.values)) { request in
                        AgentApprovalCard(request: request, store: store)
                    }
                }

                if let threadID = store.selectedThreadID, let usage = store.tokenUsage[threadID] {
                    GroupBox("Tokens") {
                        VStack(alignment: .leading, spacing: 6) {
                            LabeledContent("Total", value: "\(usage.total.totalTokens)")
                            LabeledContent("Input", value: "\(usage.total.inputTokens)")
                            LabeledContent("Output", value: "\(usage.total.outputTokens)")
                        }
                    }
                }

                if !store.warnings.isEmpty || store.unknownMessageCount > 0 {
                    GroupBox("Diagnostics") {
                        VStack(alignment: .leading, spacing: 6) {
                            LabeledContent("Unknown events", value: "\(store.unknownMessageCount)")
                            ForEach(store.warnings.suffix(5), id: \.self) { warning in
                                Text(warning).font(.caption).textSelection(.enabled)
                            }
                        }
                    }
                }
            }
            .padding(12)
        }
    }
}

private struct AgentApprovalCard: View {
    let request: AgentApprovalRequest
    @ObservedObject var store: AgentStore

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                if let reason = request.reason {
                    Text(reason).font(.callout)
                }
                if let command = request.command {
                    Text(command)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.black.opacity(0.15), in: .rect(cornerRadius: 8))
                }
                if let cwd = request.cwd {
                    Label(cwd, systemImage: "folder")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                HStack {
                    Button("Decline", role: .destructive) {
                        resolve(.decline)
                    }
                    Spacer()
                    if request.kind == .command || request.kind == .legacyCommand {
                        Button("This session") { resolve(.acceptForSession) }
                    }
                    Button("Approve once") { resolve(.accept) }
                        .buttonStyle(.glassProminent)
                }
                .controlSize(.small)
            }
        } label: {
            Label(request.kind.title, systemImage: request.kind.systemImage)
                .foregroundStyle(.orange)
        }
    }

    private func resolve(_ response: AgentApprovalResponse) {
        Task { await store.resolveApproval(id: request.id, response: response) }
    }
}

private extension AgentThread {
    var displayTitle: String {
        if let name, !name.isEmpty { return name }
        if !preview.isEmpty { return preview }
        return "Thread \(id.prefix(8))"
    }
}

private extension String {
    var isAgentRunning: Bool {
        let value = lowercased()
        return value.contains("progress") || value == "running" || value == "started"
    }
}

private extension AgentConnectionState {
    var label: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .starting: return "Connecting"
        case .ready(let info): return "Codex \(info.installation.version)"
        case .failed: return "Connection failed"
        }
    }

    var indicatorColor: Color {
        switch self {
        case .ready: return .green
        case .starting: return .yellow
        case .failed: return .red
        case .disconnected: return .secondary
        }
    }
}

private extension AgentAccountStatus {
    var displayText: String {
        switch account {
        case .apiKey: return "API key"
        case .chatGPT(let email, let plan): return email.map { "\($0) · \(plan)" } ?? "ChatGPT · \(plan)"
        case .amazonBedrock: return "Amazon Bedrock"
        case .unknown(let type, _): return type
        case nil: return requiresOpenAIAuth ? "Sign-in required" : "Signed out"
        }
    }
}

private extension AgentApprovalKind {
    var title: String {
        switch self {
        case .command, .legacyCommand: return "Command approval"
        case .fileChange, .legacyFileChange: return "File change approval"
        case .permissions: return "Permission request"
        case .userInput: return "Agent question"
        case .mcpElicitation: return "MCP request"
        }
    }

    var systemImage: String {
        switch self {
        case .command, .legacyCommand: return "terminal"
        case .fileChange, .legacyFileChange: return "doc.badge.gearshape"
        case .permissions: return "hand.raised"
        case .userInput: return "questionmark.bubble"
        case .mcpElicitation: return "shippingbox"
        }
    }
}
