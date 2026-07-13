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

    init(runtime: any AgentRuntime) {
        self.runtime = runtime
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
            threads = page.threads
            if selectedThreadID == nil || !page.threads.contains(where: { $0.id == selectedThreadID }) {
                selectedThreadID = page.threads.first?.id
            }
        } catch {
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
        taskPrompts[id] = nil
        latestGuidance[id] = nil
        executionModes[id] = nil
        commandOutputsByThread[id] = nil
        if selectedThreadID == id {
            selectedThreadID = threads.first?.id
        }
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
        if activities.count > 80 {
            activities.removeFirst(activities.count - 80)
        }
        taskActivities[threadID] = activities
    }

    private func automaticallyResolve(
        _ request: AgentApprovalRequest,
        mode: AgentTaskExecutionMode
    ) async {
        let response: AgentApprovalResponse
        let accepted: Bool
        switch request.kind {
        case .command, .fileChange, .legacyCommand, .legacyFileChange:
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
