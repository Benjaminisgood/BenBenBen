import Combine
import Foundation

/// Main-actor projection of AgentRuntime for SwiftUI. The store deliberately
/// owns only UI state; Codex thread transcripts remain owned by app-server.
@MainActor
final class AgentStore: ObservableObject {
    @Published private(set) var connectionState: AgentConnectionState = .disconnected
    @Published private(set) var accountStatus: AgentAccountStatus?
    @Published private(set) var loginFlow: AgentLoginFlow?
    @Published private(set) var threads: [AgentThread] = []
    @Published var selectedThreadID: String?
    @Published private(set) var activeTurns: [String: AgentTurn] = [:]
    @Published private(set) var agentMessages: [String: String] = [:]
    @Published private(set) var commandOutputs: [String: String] = [:]
    @Published private(set) var commandOutputsByThread: [String: String] = [:]
    @Published private(set) var diffs: [String: String] = [:]
    @Published private(set) var taskPlans: [String: [AgentPlanStep]] = [:]
    @Published private(set) var taskActivities: [String: [AgentTaskActivity]] = [:]
    @Published private(set) var taskSubagents: [String: [AgentSubagent]] = [:]
    @Published private(set) var historyLoadStates: [String: AgentHistoryLoadState] = [:]
    @Published private(set) var taskPrompts: [String: String] = [:]
    @Published private(set) var latestGuidance: [String: String] = [:]
    @Published private(set) var executionModes: [String: AgentTaskExecutionMode] = [:]
    @Published var defaultExecutionMode = AgentTaskExecutionMode.persistedDefault {
        didSet {
            UserDefaults.standard.set(
                defaultExecutionMode.rawValue,
                forKey: "benbenben.agent.executionMode"
            )
        }
    }
    @Published private(set) var tokenUsage: [String: AgentTokenUsage] = [:]
    @Published private(set) var pendingApprovals: [AgentRequestID: AgentApprovalRequest] = [:]
    @Published private(set) var warnings: [String] = []
    @Published private(set) var stderrLines: [String] = []
    @Published private(set) var unknownMessageCount = 0
    @Published private(set) var protocolVersionWarning: String?
    @Published private(set) var lastError: String?

    private let runtime: any AgentRuntime
    private var eventTask: Task<Void, Never>?
    private var loadedThreadIDs = Set<String>()
    private static let taskPromptsDefaultsKey = "benbenben.agent.taskPrompts"
    private static var persistedTaskPrompts: [String: String] {
        UserDefaults.standard.dictionary(forKey: taskPromptsDefaultsKey) as? [String: String] ?? [:]
    }

    init(runtime: any AgentRuntime) {
        self.runtime = runtime
        taskPrompts = Self.persistedTaskPrompts
        consumeEvents()
    }

    static func live(preferredCodexPath: String? = nil) async throws -> AgentStore {
        let installation = try await CodexExecutableDetector.detect(preferredPath: preferredCodexPath)
        UserDefaults.standard.set(
            installation.executableURL.path,
            forKey: "benbenben.codexExecutable"
        )
        var overrides: [String] = []
        let helper = WorkspacePaths.mcpHelper
        if FileManager.default.isExecutableFile(atPath: helper.path) {
            let escapedPath = helper.path
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            overrides.append("mcp_servers.benbenben.command=\"\(escapedPath)\"")
        }
        return AgentStore(
            runtime: CodexProcessActor(
                installation: installation,
                appServerConfigOverrides: overrides
            )
        )
    }

    deinit {
        eventTask?.cancel()
    }

    func connect(threadQuery: AgentThreadListQuery = AgentThreadListQuery()) async {
        lastError = nil
        loadedThreadIDs.removeAll()
        historyLoadStates.removeAll()
        do {
            _ = try await runtime.start()
            await refreshAccount()
            await reloadThreads(query: threadQuery)
        } catch {
            record(error)
        }
    }

    func disconnect() async {
        loadedThreadIDs.removeAll()
        await runtime.stop()
    }

    func refreshAccount(refreshToken: Bool = false) async {
        do {
            accountStatus = try await runtime.readAccount(refreshToken: refreshToken)
        } catch {
            record(error)
        }
    }

    func beginChatGPTLogin() async {
        do {
            loginFlow = try await runtime.startChatGPTLogin()
        } catch {
            record(error)
        }
    }

    func reloadThreads(query: AgentThreadListQuery = AgentThreadListQuery()) async {
        do {
            let page = try await runtime.listThreads(query)
            let loaded = page.threads
            threads = loaded
            if selectedThreadID == nil || !loaded.contains(where: { $0.id == selectedThreadID }) {
                selectedThreadID = loaded.first?.id
            }
        } catch {
            record(error)
        }
    }

    func loadThreadHistory(id: String, force: Bool = false) async {
        if !force {
            switch historyLoadStates[id] {
            case .loading, .loaded:
                return
            case .failed, nil:
                break
            }
        }

        historyLoadStates[id] = .loading
        do {
            let history = try await runtime.readThread(id: id, includeTurns: true)
            let projection = await Task.detached(priority: .userInitiated) {
                AgentThreadHistoryProjection.make(from: history)
            }.value
            apply(history, projection: projection)
            historyLoadStates[id] = .loaded
            lastError = nil
        } catch {
            let message = error.localizedDescription
            historyLoadStates[id] = .failed(message)
            record(error)
        }
    }

    @discardableResult
    func createThread(options: AgentThreadStartOptions = AgentThreadStartOptions()) async -> AgentThread? {
        do {
            let thread = try await runtime.startThread(options)
            upsert(thread)
            loadedThreadIDs.insert(thread.id)
            executionModes[thread.id] = options.executionMode
            selectedThreadID = thread.id
            lastError = nil
            return thread
        } catch {
            record(error)
            return nil
        }
    }

    @discardableResult
    func resumeThread(id: String, cwd: String? = nil) async -> AgentThread? {
        do {
            let thread = try await runtime.resumeThread(id: id, cwd: cwd)
            upsert(thread)
            loadedThreadIDs.insert(thread.id)
            if executionModes[thread.id] == nil {
                executionModes[thread.id] = defaultExecutionMode
            }
            selectedThreadID = thread.id
            lastError = nil
            return thread
        } catch {
            record(error)
            return nil
        }
    }

    func archiveThread(id: String) async {
        do {
            try await runtime.archiveThread(id: id)
            removeThread(id)
        } catch {
            record(error)
        }
    }

    @discardableResult
    func send(
        _ text: String,
        to threadID: String,
        localImagePath: String? = nil,
        fallbackOptions: AgentThreadStartOptions = AgentThreadStartOptions()
    ) async -> AgentSentTurn? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        do {
            let readyThreadID = try await ensureThreadIsLoaded(
                id: threadID,
                fallbackOptions: fallbackOptions
            )
            agentMessages[readyThreadID] = ""
            if taskPrompts[readyThreadID] == nil {
                taskPrompts[readyThreadID] = trimmed
            }
            latestGuidance[readyThreadID] = nil
            let mode = executionMode(for: readyThreadID)
            let turn = try await runtime.startTurn(
                threadID: readyThreadID,
                text: trimmed,
                localImagePath: localImagePath,
                options: AgentTurnStartOptions(executionMode: mode)
            )
            lastError = nil
            activeTurns[readyThreadID] = turn
            latestGuidance[readyThreadID] = "收到，我开始处理这个任务。"
            return AgentSentTurn(threadID: readyThreadID, turn: turn)
        } catch {
            if let bridgeError = error as? CodexBridgeError, bridgeError.isMissingThread {
                loadedThreadIDs.remove(threadID)
                removeThread(threadID)
                do {
                    let replacement = try await startReplacementThread(options: fallbackOptions)
                    agentMessages[replacement.id] = ""
                    taskPrompts[replacement.id] = trimmed
                    latestGuidance[replacement.id] = nil
                    let mode = executionMode(for: replacement.id)
                    let turn = try await runtime.startTurn(
                        threadID: replacement.id,
                        text: trimmed,
                        localImagePath: localImagePath,
                        options: AgentTurnStartOptions(executionMode: mode)
                    )
                    lastError = nil
                    activeTurns[replacement.id] = turn
                    latestGuidance[replacement.id] = "收到，我开始处理这个任务。"
                    return AgentSentTurn(threadID: replacement.id, turn: turn)
                } catch {
                    record(error)
                    return nil
                }
            }
            record(error)
            return nil
        }
    }

    @discardableResult
    func steer(_ text: String, threadID: String, turnID: String) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        do {
            _ = try await runtime.steerTurn(threadID: threadID, turnID: turnID, text: trimmed)
            latestGuidance[threadID] = "收到，我会按这条引导继续：\(Self.shortLabel(trimmed, limit: 42))"
            upsertActivity(
                AgentTaskActivity(
                    id: "guidance:\(UUID().uuidString)",
                    kind: .guidance,
                    title: "收到新的引导",
                    detail: trimmed,
                    status: "completed",
                    updatedAt: Date()
                ),
                threadID: threadID
            )
            lastError = nil
            return true
        } catch {
            record(error)
            return false
        }
    }

    func interrupt(threadID: String, turnID: String) async {
        do {
            try await runtime.interruptTurn(threadID: threadID, turnID: turnID)
            upsertActivity(
                AgentTaskActivity(
                    id: "interrupt:\(turnID)",
                    kind: .lifecycle,
                    title: "任务已停止",
                    detail: nil,
                    status: "interrupted",
                    updatedAt: Date()
                ),
                threadID: threadID
            )
        } catch {
            record(error)
        }
    }

    func executionMode(for threadID: String) -> AgentTaskExecutionMode {
        executionModes[threadID] ?? defaultExecutionMode
    }

    func setTaskDisplayPrompt(_ prompt: String, for threadID: String) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        taskPrompts[threadID] = trimmed
        persistTaskPrompts()
    }

    func setExecutionMode(_ mode: AgentTaskExecutionMode, for threadID: String) {
        executionModes[threadID] = mode
        if mode != .askMe {
            let approvals = pendingApprovals.values.filter { $0.threadID == threadID }
            for approval in approvals {
                Task { [weak self] in
                    await self?.automaticallyResolve(approval, mode: mode)
                }
            }
        }
    }

    func resolveApproval(id: AgentRequestID, response: AgentApprovalResponse) async {
        do {
            try await runtime.respondToApproval(id: id, response: response)
            pendingApprovals.removeValue(forKey: id)
        } catch {
            record(error)
        }
    }

    func clearTransientLogs() {
        warnings.removeAll()
        stderrLines.removeAll()
        unknownMessageCount = 0
        lastError = nil
    }

    private func consumeEvents() {
        let events = runtime.eventStream()
        eventTask = Task { [weak self] in
            for await event in events {
                guard !Task.isCancelled else { return }
                self?.apply(event)
            }
        }
    }

    private func apply(_ event: AgentEvent) {
        switch event {
        case let .connectionChanged(state):
            connectionState = state

        case let .protocolVersionMismatch(expected, actual):
            protocolVersionWarning =
                "Codex \(actual) differs from the schema-tested version \(expected). Run the protocol contract tests."

        case let .agentMessageDelta(context, delta):
            latestGuidance[context.threadID] = nil
            agentMessages[context.threadID, default: ""].append(delta)

        case let .commandOutputDelta(context, delta):
            let key = context.itemID ?? context.turnID
            commandOutputs[key, default: ""].append(delta)
            commandOutputsByThread[context.threadID, default: ""].append(delta)

        case let .fileChangeOutputDelta(context, delta):
            let key = context.itemID ?? context.turnID
            commandOutputs[key, default: ""].append(delta)
            commandOutputsByThread[context.threadID, default: ""].append(delta)

        case let .diffUpdated(context, diff):
            diffs[context.threadID] = diff

        case let .planUpdated(threadID, _, steps, explanation):
            taskPlans[threadID] = steps
            if let explanation, !explanation.isEmpty {
                upsertActivity(
                    AgentTaskActivity(
                        id: "plan-explanation",
                        kind: .reasoning,
                        title: "执行计划已更新",
                        detail: explanation,
                        status: "inProgress",
                        updatedAt: Date()
                    ),
                    threadID: threadID
                )
            }

        case let .taskActivityUpdated(threadID, _, activity):
            upsertActivity(activity, threadID: threadID)

        case let .tokenUsageUpdated(threadID, _, usage):
            tokenUsage[threadID] = usage

        case let .turnStarted(threadID, turn):
            lastError = nil
            activeTurns[threadID] = turn
            commandOutputsByThread[threadID] = ""
            upsertActivity(
                AgentTaskActivity(
                    id: "turn:\(turn.id)",
                    kind: .lifecycle,
                    title: "任务开始执行",
                    detail: nil,
                    status: turn.status,
                    updatedAt: Date()
                ),
                threadID: threadID
            )

        case let .turnCompleted(threadID, turn):
            activeTurns[threadID] = turn
            pendingApprovals = pendingApprovals.filter { $0.value.threadID != threadID }
            latestGuidance[threadID] = nil
            upsertActivity(
                AgentTaskActivity(
                    id: "turn:\(turn.id)",
                    kind: .lifecycle,
                    title: turn.status.lowercased() == "completed" ? "任务已经完成" : "任务已结束",
                    detail: turn.errorMessage,
                    status: turn.status,
                    updatedAt: Date()
                ),
                threadID: threadID
            )

        case let .threadUpdated(thread):
            upsert(thread)

        case let .threadArchived(threadID):
            removeThread(threadID)

        case let .approvalRequested(request):
            if let threadID = request.threadID {
                upsertActivity(
                    AgentTaskActivity(
                        id: "approval:\(request.id)",
                        kind: .approval,
                        title: "需要权限确认",
                        detail: request.reason ?? request.command,
                        status: "waiting",
                        updatedAt: Date()
                    ),
                    threadID: threadID
                )
            }
            if let threadID = request.threadID {
                let mode = executionMode(for: threadID)
                if mode != .askMe {
                    Task { [weak self] in await self?.automaticallyResolve(request, mode: mode) }
                } else {
                    pendingApprovals[request.id] = request
                }
            } else {
                pendingApprovals[request.id] = request
            }

        case let .loginCompleted(_, success, error):
            if success {
                loginFlow = nil
                Task { [weak self] in await self?.refreshAccount() }
            } else if let error {
                recordMessage(error)
            }

        case let .runtimeError(_, _, message, willRetry):
            recordMessage(willRetry ? "\(message) (retrying)" : message)

        case let .warning(message):
            appendBounded(message, to: &warnings, limit: 200)

        case let .stderr(text):
            for line in text.split(whereSeparator: \Character.isNewline) {
                appendBounded(String(line), to: &stderrLines, limit: 400)
            }

        case let .malformedMessage(line, error):
            unknownMessageCount += 1
            appendBounded("Malformed app-server message: \(error) — \(line)", to: &warnings, limit: 200)

        case .unknownMessage:
            unknownMessageCount += 1

        case let .processExited(status, expected, stderrTail):
            loadedThreadIDs.removeAll()
            guard !expected else { return }
            recordMessage("Codex app-server exited with status \(status). \(stderrTail)")
        }
    }

    private func apply(
        _ history: AgentThreadHistory,
        projection: AgentThreadHistoryProjection
    ) {
        let threadID = history.thread.id
        upsert(history.thread)

        if let lastTurn = history.turns.last,
           let turn = try? AgentTurn(json: lastTurn.raw) {
            let currentTurnIsRunning = activeTurns[threadID]?.status.isCompanionRunning == true
            if !currentTurnIsRunning || turn.status.isCompanionRunning {
                activeTurns[threadID] = turn
            }
        }

        mergeActivities(projection.activities, threadID: threadID)

        let currentTurnIsRunning = activeTurns[threadID]?.status.isCompanionRunning == true
        if let message = projection.latestAgentMessage, !currentTurnIsRunning {
            agentMessages[threadID] = message
        }
        if let output = projection.latestCommandOutput, !currentTurnIsRunning {
            commandOutputsByThread[threadID] = output
        }

        var subagents = projection.subagents
        for index in subagents.indices {
            guard let child = threads.first(where: { $0.id == subagents[index].threadID }) else { continue }
            subagents[index].nickname = child.agentNickname ?? subagents[index].nickname
            subagents[index].role = child.agentRole ?? subagents[index].role
            if let activeStatus = activeTurns[child.id]?.status {
                subagents[index].status = activeStatus
            } else if !subagents[index].status.isAgentTerminal, let childStatus = child.status {
                subagents[index].status = childStatus
            }
        }
        taskSubagents[threadID] = subagents

        if let parentThreadID = history.thread.parentThreadID {
            var siblings = taskSubagents[parentThreadID, default: []]
            let status = activeTurns[threadID]?.status ?? history.thread.status ?? "notLoaded"
            let child = AgentSubagent(
                threadID: threadID,
                parentThreadID: parentThreadID,
                path: nil,
                nickname: history.thread.agentNickname,
                role: history.thread.agentRole,
                status: status,
                prompt: history.thread.preview,
                message: projection.latestAgentMessage
            )
            if let index = siblings.firstIndex(where: { $0.threadID == threadID }) {
                var merged = siblings[index]
                merged.nickname = child.nickname ?? merged.nickname
                merged.role = child.role ?? merged.role
                merged.status = child.status
                if let prompt = child.prompt, !prompt.isEmpty { merged.prompt = prompt }
                merged.message = child.message ?? merged.message
                siblings[index] = merged
            } else {
                siblings.append(child)
            }
            taskSubagents[parentThreadID] = siblings.sorted { $0.displayName < $1.displayName }
        }
    }

    private func upsert(_ thread: AgentThread) {
        if let index = threads.firstIndex(where: { $0.id == thread.id }) {
            threads[index] = thread
        } else {
            threads.insert(thread, at: 0)
        }
    }

    private func removeThread(_ id: String) {
        loadedThreadIDs.remove(id)
        threads.removeAll { $0.id == id }
        taskPlans[id] = nil
        taskActivities[id] = nil
        taskSubagents[id] = nil
        historyLoadStates[id] = nil
        for parentID in Array(taskSubagents.keys) {
            taskSubagents[parentID]?.removeAll { $0.threadID == id }
        }
        taskPrompts[id] = nil
        persistTaskPrompts()
        latestGuidance[id] = nil
        executionModes[id] = nil
        commandOutputsByThread[id] = nil
        if selectedThreadID == id {
            selectedThreadID = threads.first?.id
        }
    }

    private func persistTaskPrompts() {
        UserDefaults.standard.set(taskPrompts, forKey: Self.taskPromptsDefaultsKey)
    }

    private func ensureThreadIsLoaded(
        id: String,
        fallbackOptions: AgentThreadStartOptions
    ) async throws -> String {
        if loadedThreadIDs.contains(id) {
            return id
        }

        do {
            let cwd = threads.first(where: { $0.id == id })?.cwd ?? fallbackOptions.cwd
            let thread = try await runtime.resumeThread(id: id, cwd: cwd)
            upsert(thread)
            loadedThreadIDs.insert(thread.id)
            if executionModes[thread.id] == nil {
                executionModes[thread.id] = defaultExecutionMode
            }
            selectedThreadID = thread.id
            lastError = nil
            return thread.id
        } catch {
            guard let bridgeError = error as? CodexBridgeError, bridgeError.isMissingThread else {
                throw error
            }
            loadedThreadIDs.remove(id)
            removeThread(id)
            return try await startReplacementThread(options: fallbackOptions).id
        }
    }

    private func startReplacementThread(options: AgentThreadStartOptions) async throws -> AgentThread {
        let thread = try await runtime.startThread(options)
        upsert(thread)
        loadedThreadIDs.insert(thread.id)
        executionModes[thread.id] = options.executionMode
        selectedThreadID = thread.id
        lastError = nil
        return thread
    }

    private func record(_ error: Error) {
        recordMessage(error.localizedDescription)
    }

    private func recordMessage(_ message: String) {
        lastError = message
        appendBounded(message, to: &warnings, limit: 200)
    }

    private func upsertActivity(_ activity: AgentTaskActivity, threadID: String) {
        var activities = taskActivities[threadID, default: []]
        if let index = activities.firstIndex(where: { $0.id == activity.id }) {
            activities[index] = activity
        } else {
            activities.append(activity)
        }
        activities.sort { $0.updatedAt < $1.updatedAt }
        taskActivities[threadID] = activities
    }

    private func mergeActivities(_ incoming: [AgentTaskActivity], threadID: String) {
        var activitiesByID = Dictionary(
            (taskActivities[threadID] ?? []).map { ($0.id, $0) },
            uniquingKeysWith: { _, replacement in replacement }
        )
        for activity in incoming {
            activitiesByID[activity.id] = activity
        }
        taskActivities[threadID] = activitiesByID.values.sorted { $0.updatedAt < $1.updatedAt }
    }

    private func automaticallyResolve(
        _ request: AgentApprovalRequest,
        mode: AgentTaskExecutionMode
    ) async {
        let response: AgentApprovalResponse
        let accepted: Bool
        switch request.kind {
        case .command, .fileChange:
            response = .acceptForSession
            accepted = true
        case .permissions:
            if mode == .fullAccess {
                response = .grantPermissions(
                    request.rawParams["permissions"] ?? .object([:]),
                    scope: "session"
                )
                accepted = true
            } else {
                // Auto-review keeps the workspace boundary intact. Full-access
                // is the explicit mode that may grant sandbox escapes.
                response = .decline
                accepted = false
            }
        case .userInput, .mcpElicitation:
            pendingApprovals[request.id] = request
            return
        }
        await resolveApproval(id: request.id, response: response)
        if let threadID = request.threadID {
            upsertActivity(
                AgentTaskActivity(
                    id: "approval:\(request.id)",
                    kind: .approval,
                    title: accepted ? "权限已自动允许" : "越界权限已自动拒绝",
                    detail: request.reason ?? request.command,
                    status: accepted ? "completed" : "declined",
                    updatedAt: Date()
                ),
                threadID: threadID
            )
        }
    }

    private static func shortLabel(_ text: String, limit: Int) -> String {
        let singleLine = text.replacingOccurrences(of: "\n", with: " ")
        return singleLine.count <= limit ? singleLine : String(singleLine.prefix(limit - 1)) + "…"
    }

    private func appendBounded(_ value: String, to values: inout [String], limit: Int) {
        values.append(value)
        if values.count > limit {
            values.removeFirst(values.count - limit)
        }
    }
}

private struct AgentThreadHistoryProjection: Sendable {
    let activities: [AgentTaskActivity]
    let latestAgentMessage: String?
    let latestCommandOutput: String?
    let subagents: [AgentSubagent]

    static func make(from history: AgentThreadHistory) -> AgentThreadHistoryProjection {
        var activities: [AgentTaskActivity] = []
        var latestAgentMessage: String?
        var latestCommandOutput: String?
        var subagents: [String: AgentSubagent] = [:]

        for (turnIndex, turn) in history.turns.enumerated() {
            let baseTimestamp = turn.startedAt
                ?? turn.completedAt
                ?? history.thread.updatedAt
                ?? history.thread.createdAt
                ?? 0
            activities.append(
                AgentTaskActivity(
                    id: "history:\(turn.id):start",
                    kind: .lifecycle,
                    title: history.turns.count == 1 ? "任务开始执行" : "第 \(turnIndex + 1) 轮开始",
                    detail: nil,
                    status: turn.status == "inProgress" ? turn.status : "completed",
                    updatedAt: Date(timeIntervalSince1970: baseTimestamp)
                )
            )

            for (itemIndex, item) in turn.items.enumerated() {
                let timestamp = Date(
                    timeIntervalSince1970: baseTimestamp + Double(itemIndex + 1) / 1_000
                )
                if let activity = activity(
                    from: item,
                    turnID: turn.id,
                    timestamp: timestamp,
                    parentThreadID: history.thread.id,
                    subagents: &subagents,
                    latestAgentMessage: &latestAgentMessage,
                    latestCommandOutput: &latestCommandOutput
                ) {
                    activities.append(activity)
                }
            }

            if turn.status != "inProgress" {
                let endingTimestamp = turn.completedAt
                    ?? baseTimestamp + Double(turn.items.count + 1) / 1_000
                activities.append(
                    AgentTaskActivity(
                        id: "history:\(turn.id):end",
                        kind: .lifecycle,
                        title: turn.status == "completed" ? "任务已经完成" : "任务已结束",
                        detail: turn.errorMessage,
                        status: turn.status,
                        updatedAt: Date(timeIntervalSince1970: endingTimestamp)
                    )
                )
            }
        }

        return AgentThreadHistoryProjection(
            activities: activities.sorted { $0.updatedAt < $1.updatedAt },
            latestAgentMessage: latestAgentMessage,
            latestCommandOutput: latestCommandOutput,
            subagents: subagents.values.sorted { $0.displayName < $1.displayName }
        )
    }

    private static func activity(
        from item: AgentJSON,
        turnID: String,
        timestamp: Date,
        parentThreadID: String,
        subagents: inout [String: AgentSubagent],
        latestAgentMessage: inout String?,
        latestCommandOutput: inout String?
    ) -> AgentTaskActivity? {
        guard let type = item["type"]?.stringValue else { return nil }
        let itemID = item["id"]?.stringValue ?? "\(turnID):\(type):\(timestamp.timeIntervalSince1970)"
        let status = item["status"]?.stringValue ?? "completed"

        switch type {
        case "userMessage":
            let text = (item["content"]?.arrayValue ?? [])
                .compactMap { $0["text"]?.stringValue }
                .joined(separator: "\n")
            return AgentTaskActivity(
                id: itemID,
                kind: .message,
                title: "用户任务",
                detail: visibleUserText(text),
                status: "completed",
                updatedAt: timestamp
            )

        case "agentMessage":
            let text = item["text"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let text, !text.isEmpty { latestAgentMessage = text }
            return AgentTaskActivity(
                id: itemID,
                kind: .message,
                title: "Ben龙 回复",
                detail: text,
                status: "completed",
                updatedAt: timestamp
            )

        case "reasoning":
            let summary = item["summary"]?.arrayValue?.compactMap(\.stringValue) ?? []
            let content = item["content"]?.arrayValue?.compactMap(\.stringValue) ?? []
            let detail = (summary.isEmpty ? content : summary).joined(separator: "\n")
            return AgentTaskActivity(
                id: itemID,
                kind: .reasoning,
                title: "分析过程",
                detail: detail.isEmpty ? nil : detail,
                status: "completed",
                updatedAt: timestamp
            )

        case "plan":
            return AgentTaskActivity(
                id: itemID,
                kind: .reasoning,
                title: "执行计划",
                detail: item["text"]?.stringValue,
                status: "completed",
                updatedAt: timestamp
            )

        case "commandExecution":
            let command = item["command"]?.stringValue ?? ""
            let output = item["aggregatedOutput"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let output, !output.isEmpty { latestCommandOutput = output }
            let detail = [command.isEmpty ? nil : "$ \(command)", output]
                .compactMap { $0 }
                .joined(separator: "\n")
            return AgentTaskActivity(
                id: itemID,
                kind: .command,
                title: status == "completed" ? "命令执行完成" : "命令执行",
                detail: detail.isEmpty ? nil : detail,
                status: status,
                updatedAt: timestamp
            )

        case "fileChange":
            let changes = (item["changes"]?.arrayValue ?? []).compactMap { change -> String? in
                guard let path = change["path"]?.stringValue else { return nil }
                if let kind = change["kind"]?.stringValue { return "\(kind) · \(path)" }
                return path
            }
            return AgentTaskActivity(
                id: itemID,
                kind: .fileChange,
                title: status == "completed" ? "文件修改完成" : "文件修改",
                detail: changes.isEmpty ? nil : changes.joined(separator: "\n"),
                status: status,
                updatedAt: timestamp
            )

        case "mcpToolCall":
            let tool = [item["server"]?.stringValue, item["tool"]?.stringValue]
                .compactMap { $0 }
                .joined(separator: " · ")
            let error = compactJSON(item["error"])
            return AgentTaskActivity(
                id: itemID,
                kind: .tool,
                title: status == "completed" ? "工具调用完成" : "工具调用",
                detail: [tool.isEmpty ? nil : tool, error].compactMap { $0 }.joined(separator: "\n"),
                status: status,
                updatedAt: timestamp
            )

        case "dynamicToolCall":
            let tool = [item["namespace"]?.stringValue, item["tool"]?.stringValue]
                .compactMap { $0 }
                .joined(separator: " · ")
            return AgentTaskActivity(
                id: itemID,
                kind: .tool,
                title: status == "completed" ? "工具调用完成" : "工具调用",
                detail: tool.isEmpty ? nil : tool,
                status: status,
                updatedAt: timestamp
            )

        case "collabAgentToolCall":
            let tool = item["tool"]?.stringValue ?? "collaboration"
            let prompt = item["prompt"]?.stringValue
            let receiverThreadIDs = item["receiverThreadIds"]?.arrayValue?.compactMap(\.stringValue) ?? []
            let states = item["agentsStates"]?.objectValue ?? [:]
            for threadID in Set(receiverThreadIDs).union(states.keys) {
                let state = states[threadID]
                var subagent = subagents[threadID] ?? AgentSubagent(
                    threadID: threadID,
                    parentThreadID: parentThreadID,
                    path: nil,
                    nickname: nil,
                    role: nil,
                    status: status,
                    prompt: prompt,
                    message: nil
                )
                subagent.status = state?["status"]?.stringValue ?? subagent.status
                subagent.prompt = prompt ?? subagent.prompt
                subagent.message = state?["message"]?.stringValue ?? subagent.message
                subagents[threadID] = subagent
            }
            return AgentTaskActivity(
                id: itemID,
                kind: .agent,
                title: collaborationTitle(tool),
                detail: [prompt, receiverThreadIDs.isEmpty ? nil : receiverThreadIDs.joined(separator: "、")]
                    .compactMap { $0 }
                    .joined(separator: "\n"),
                status: status,
                updatedAt: timestamp
            )

        case "subAgentActivity":
            guard let threadID = item["agentThreadId"]?.stringValue else { return nil }
            let path = item["agentPath"]?.stringValue
            let kind = item["kind"]?.stringValue ?? "interacted"
            var subagent = subagents[threadID] ?? AgentSubagent(
                threadID: threadID,
                parentThreadID: parentThreadID,
                path: path,
                nickname: nil,
                role: nil,
                status: "notLoaded",
                prompt: nil,
                message: nil
            )
            subagent.path = path ?? subagent.path
            if kind == "started", !subagent.status.isAgentTerminal {
                subagent.status = "running"
            }
            if kind == "interrupted" { subagent.status = "interrupted" }
            subagents[threadID] = subagent
            return AgentTaskActivity(
                id: itemID,
                kind: .agent,
                title: kind == "started" ? "子 Agent 开始执行" : "子 Agent 状态更新",
                detail: [path, threadID].compactMap { $0 }.joined(separator: " · "),
                status: subagent.status,
                updatedAt: timestamp
            )

        case "webSearch":
            return AgentTaskActivity(
                id: itemID,
                kind: .tool,
                title: "网页搜索",
                detail: item["query"]?.stringValue,
                status: "completed",
                updatedAt: timestamp
            )

        case "imageView":
            return AgentTaskActivity(
                id: itemID,
                kind: .tool,
                title: "查看图片",
                detail: item["path"]?.stringValue,
                status: "completed",
                updatedAt: timestamp
            )

        case "imageGeneration":
            return AgentTaskActivity(
                id: itemID,
                kind: .tool,
                title: "生成图片",
                detail: item["savedPath"]?.stringValue,
                status: status,
                updatedAt: timestamp
            )

        case "sleep":
            let milliseconds = item["durationMs"]?.integerValue ?? 0
            return AgentTaskActivity(
                id: itemID,
                kind: .lifecycle,
                title: "等待",
                detail: "\(milliseconds) ms",
                status: "completed",
                updatedAt: timestamp
            )

        case "enteredReviewMode":
            return AgentTaskActivity(
                id: itemID,
                kind: .lifecycle,
                title: "进入代码审查",
                detail: item["review"]?.stringValue,
                status: "completed",
                updatedAt: timestamp
            )

        case "exitedReviewMode":
            return AgentTaskActivity(
                id: itemID,
                kind: .lifecycle,
                title: "完成代码审查",
                detail: item["review"]?.stringValue,
                status: "completed",
                updatedAt: timestamp
            )

        case "contextCompaction":
            return AgentTaskActivity(
                id: itemID,
                kind: .lifecycle,
                title: "压缩任务上下文",
                detail: nil,
                status: "completed",
                updatedAt: timestamp
            )

        default:
            return AgentTaskActivity(
                id: itemID,
                kind: .lifecycle,
                title: "处理 \(type)",
                detail: nil,
                status: status,
                updatedAt: timestamp
            )
        }
    }

    private static func visibleUserText(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let range = trimmed.range(of: "\n[User]\n") else { return trimmed }
        let visible = trimmed[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return visible.isEmpty ? trimmed : visible
    }

    private static func collaborationTitle(_ tool: String) -> String {
        switch tool {
        case "spawnAgent": return "创建子 Agent"
        case "sendInput": return "向子 Agent 发送引导"
        case "resumeAgent": return "继续子 Agent"
        case "wait": return "等待子 Agent"
        case "closeAgent": return "关闭子 Agent"
        default: return "Agent 协作"
        }
    }

    private static func compactJSON(_ value: AgentJSON?) -> String? {
        guard let value, value != .null,
              let data = try? JSONEncoder().encode(value),
              var text = String(data: data, encoding: .utf8) else { return nil }
        if text.count > 500 { text = String(text.prefix(499)) + "…" }
        return text
    }
}
