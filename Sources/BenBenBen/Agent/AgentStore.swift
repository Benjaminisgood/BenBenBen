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
    @Published private(set) var diffs: [String: String] = [:]
    @Published private(set) var tokenUsage: [String: AgentTokenUsage] = [:]
    @Published private(set) var pendingApprovals: [AgentRequestID: AgentApprovalRequest] = [:]
    @Published private(set) var warnings: [String] = []
    @Published private(set) var stderrLines: [String] = []
    @Published private(set) var unknownMessageCount = 0
    @Published private(set) var protocolVersionWarning: String?
    @Published private(set) var lastError: String?

    private let runtime: any AgentRuntime
    private var eventTask: Task<Void, Never>?

    init(runtime: any AgentRuntime) {
        self.runtime = runtime
        consumeEvents()
    }

    static func live(preferredCodexPath: String? = nil) async throws -> AgentStore {
        let installation = try await CodexExecutableDetector.detect(preferredPath: preferredCodexPath)
        return AgentStore(runtime: CodexProcessActor(installation: installation))
    }

    deinit {
        eventTask?.cancel()
    }

    func connect() async {
        lastError = nil
        do {
            _ = try await runtime.start()
            await refreshAccount()
            await reloadThreads()
        } catch {
            record(error)
        }
    }

    func disconnect() async {
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
            if selectedThreadID == nil {
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
            selectedThreadID = thread.id
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
            selectedThreadID = thread.id
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
    func send(_ text: String, to threadID: String, localImagePath: String? = nil) async -> AgentTurn? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        agentMessages[threadID] = ""
        do {
            let turn = try await runtime.startTurn(
                threadID: threadID,
                text: trimmed,
                localImagePath: localImagePath
            )
            lastError = nil
            activeTurns[threadID] = turn
            return turn
        } catch {
            record(error)
            return nil
        }
    }

    func steer(_ text: String, threadID: String, turnID: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            _ = try await runtime.steerTurn(threadID: threadID, turnID: turnID, text: trimmed)
        } catch {
            record(error)
        }
    }

    func interrupt(threadID: String, turnID: String) async {
        do {
            try await runtime.interruptTurn(threadID: threadID, turnID: turnID)
        } catch {
            record(error)
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
            agentMessages[context.threadID, default: ""].append(delta)

        case let .commandOutputDelta(context, delta):
            let key = context.itemID ?? context.turnID
            commandOutputs[key, default: ""].append(delta)

        case let .fileChangeOutputDelta(context, delta):
            let key = context.itemID ?? context.turnID
            commandOutputs[key, default: ""].append(delta)

        case let .diffUpdated(context, diff):
            diffs[context.threadID] = diff

        case let .tokenUsageUpdated(threadID, _, usage):
            tokenUsage[threadID] = usage

        case let .turnStarted(threadID, turn):
            lastError = nil
            activeTurns[threadID] = turn

        case let .turnCompleted(threadID, turn):
            activeTurns[threadID] = turn
            pendingApprovals = pendingApprovals.filter { $0.value.threadID != threadID }

        case let .threadUpdated(thread):
            upsert(thread)

        case let .threadArchived(threadID):
            removeThread(threadID)

        case let .approvalRequested(request):
            pendingApprovals[request.id] = request

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
        threads.removeAll { $0.id == id }
        if selectedThreadID == id {
            selectedThreadID = threads.first?.id
        }
    }

    private func record(_ error: Error) {
        recordMessage(error.localizedDescription)
    }

    private func recordMessage(_ message: String) {
        lastError = message
        appendBounded(message, to: &warnings, limit: 200)
    }

    private func appendBounded(_ value: String, to values: inout [String], limit: Int) {
        values.append(value)
        if values.count > limit {
            values.removeFirst(values.count - limit)
        }
    }
}
