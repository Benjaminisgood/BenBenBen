import Combine
import Foundation

@MainActor
final class MascotModel: ObservableObject {
    @Published private(set) var state: MascotState = .idle
    @Published private(set) var bubbleText: String?
    @Published private(set) var relatedThreadID: String?

    private var agentCancellables = Set<AnyCancellable>()
    private var transientTask: Task<Void, Never>?
    private var previouslyRunningThreadIDs = Set<String>()
    private var voiceOverride = false

    func bind(to store: AgentStore) {
        agentCancellables.removeAll()

        Publishers.CombineLatest4(
            store.$pendingApprovals,
            store.$activeTurns,
            store.$connectionState,
            store.$lastError
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] approvals, turns, connection, error in
            self?.synchronize(
                approvals: approvals,
                turns: turns,
                connection: connection,
                error: error
            )
        }
        .store(in: &agentCancellables)
    }

    func setListening(_ listening: Bool) {
        voiceOverride = listening
        transientTask?.cancel()
        if listening {
            state = .listening
            bubbleText = "我在听，松开就发送"
        } else if state == .listening {
            state = .thinking
            bubbleText = "正在听写…"
        }
    }

    func showVoiceCountdown(text: String, seconds: Int) {
        guard !voiceOverride else { return }
        state = .thinking
        bubbleText = "\(seconds) 秒后发送：\(text)"
    }

    func showError(_ message: String) {
        voiceOverride = false
        state = .error
        bubbleText = message
        scheduleReturnToIdle(after: .seconds(5))
    }

    func clearTransient() {
        transientTask?.cancel()
        transientTask = nil
        bubbleText = nil
        if state != .waitingApproval && state != .working {
            state = .idle
        }
    }

    private func synchronize(
        approvals: [AgentRequestID: AgentApprovalRequest],
        turns: [String: AgentTurn],
        connection: AgentConnectionState,
        error: String?
    ) {
        guard !voiceOverride else { return }

        if let approval = approvals.values.first {
            transientTask?.cancel()
            state = .waitingApproval
            relatedThreadID = approval.threadID
            bubbleText = approval.reason ?? approval.command ?? "有一个动作需要你批准"
            return
        }

        if let error, !error.isEmpty {
            showError(error)
            return
        }

        let running = Set(turns.compactMap { threadID, turn in
            Self.isRunning(turn.status) ? threadID : nil
        })
        if let threadID = running.first {
            transientTask?.cancel()
            previouslyRunningThreadIDs = running
            state = .working
            relatedThreadID = threadID
            bubbleText = "我正在处理这件事"
            return
        }

        if let completedThreadID = previouslyRunningThreadIDs.first {
            previouslyRunningThreadIDs.removeAll()
            state = .success
            relatedThreadID = completedThreadID
            bubbleText = "完成了，点我看看"
            scheduleReturnToIdle(after: .seconds(4))
            return
        }

        switch connection {
        case .starting:
            state = .thinking
            bubbleText = "正在连接 Codex"
        case .ready:
            if state != .success {
                state = .idle
                bubbleText = nil
            }
        case .disconnected:
            state = .sleep
            bubbleText = "Codex 还没连接"
        case .failed(let message):
            showError(message)
        }
    }

    private func scheduleReturnToIdle(after duration: Duration) {
        transientTask?.cancel()
        transientTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.state = .idle
            self?.bubbleText = nil
        }
    }

    private static func isRunning(_ status: String) -> Bool {
        let value = status.lowercased()
        return value.contains("progress") || value == "running" || value == "started"
    }
}
