import Combine
import Foundation

@MainActor
final class MascotModel: ObservableObject {
    @Published private(set) var state: MascotState = .idle
    @Published private(set) var presentedState: MascotState = .idle
    @Published private(set) var presentationRevision = 0
    @Published private(set) var bubbleText: String?
    @Published private(set) var relatedThreadID: String?

    private var agentCancellables = Set<AnyCancellable>()
    private var transientTask: Task<Void, Never>?
    private var ambientTask: Task<Void, Never>?
    private var interactionTask: Task<Void, Never>?
    private var previouslyRunningThreadIDs = Set<String>()
    private var voiceOverride = false
    private var latestApprovals: [AgentRequestID: AgentApprovalRequest] = [:]
    private var latestTurns: [String: AgentTurn] = [:]
    private var latestConnection: AgentConnectionState = .disconnected
    private var latestError: String?

    init() {
        startAmbientBehavior()
    }

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
            applyBusinessState(.listening, bubble: "我在听，停顿后就会发送")
        } else if state == .listening {
            applyBusinessState(.thinking, bubble: "正在听写…")
            synchronizeLatestAgentState()
        }
    }

    func showVoiceCountdown(text: String, seconds: Int) {
        guard !voiceOverride else { return }
        switch state {
        case .working, .waitingApproval, .error:
            return
        default:
            break
        }
        transientTask?.cancel()
        applyBusinessState(.thinking, bubble: "\(seconds) 秒后发送：\(text)")
    }

    func showError(_ message: String) {
        voiceOverride = false
        transientTask?.cancel()
        applyBusinessState(.error, bubble: message)
        scheduleReturnToIdle(after: .seconds(5))
    }

    func clearTransient() {
        transientTask?.cancel()
        transientTask = nil
        bubbleText = nil
        if state != .waitingApproval && state != .working {
            applyBusinessState(.idle, bubble: nil)
        }
    }

    /// Starts restrained, interruptible idle moments using the approved poses.
    /// Operational states always take priority and stop this loop immediately.
    func startAmbientBehavior() {
        guard state == .idle, !voiceOverride, ambientTask == nil, interactionTask == nil else { return }

        ambientTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .milliseconds(Int64.random(in: 14_000...28_000)))
                } catch {
                    return
                }

                guard let self, self.state == .idle, !self.voiceOverride else { return }
                let moment = AmbientMoment.random()
                self.present(moment.pose)

                do {
                    try await Task.sleep(for: moment.duration)
                } catch {
                    return
                }

                guard self.state == .idle, !self.voiceOverride, self.interactionTask == nil else { return }
                self.present(.idle)
            }
        }
    }

    /// Gives the mascot a lightweight click response without reusing a stale
    /// completed-thread association.
    func interact() {
        guard state == .idle, !voiceOverride else { return }

        relatedThreadID = nil
        stopAmbientBehavior()
        interactionTask?.cancel()
        present(.success, restartingAnimation: true)
        bubbleText = "嗨，我在这儿"

        interactionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1_100))
            guard let self, !Task.isCancelled, self.state == .idle else { return }
            self.interactionTask = nil
            self.bubbleText = nil
            self.present(.idle)
            self.startAmbientBehavior()
        }
    }

    private func synchronize(
        approvals: [AgentRequestID: AgentApprovalRequest],
        turns: [String: AgentTurn],
        connection: AgentConnectionState,
        error: String?
    ) {
        latestApprovals = approvals
        latestTurns = turns
        latestConnection = connection
        latestError = error
        guard !voiceOverride else { return }

        if let approval = approvals.values.first {
            transientTask?.cancel()
            applyBusinessState(
                .waitingApproval,
                bubble: approval.reason ?? approval.command ?? "有一个动作需要你批准",
                relatedThreadID: approval.threadID
            )
            return
        }

        let running = Set(turns.compactMap { threadID, turn in
            Self.isRunning(turn.status) ? threadID : nil
        })
        if let threadID = running.first {
            transientTask?.cancel()
            previouslyRunningThreadIDs = running
            applyBusinessState(.working, bubble: "我正在处理这件事", relatedThreadID: threadID)
            return
        }

        if let error, !error.isEmpty {
            showError(error)
            return
        }

        if let completedThreadID = previouslyRunningThreadIDs.first {
            transientTask?.cancel()
            previouslyRunningThreadIDs.removeAll()
            applyBusinessState(.success, bubble: "完成了，点我看看", relatedThreadID: completedThreadID)
            scheduleReturnToIdle(after: .seconds(4))
            return
        }

        switch connection {
        case .starting:
            transientTask?.cancel()
            applyBusinessState(.thinking, bubble: "正在连接 Codex")
        case .ready:
            if state != .success {
                applyBusinessState(.idle, bubble: nil)
            }
        case .disconnected:
            transientTask?.cancel()
            applyBusinessState(.sleep, bubble: "Codex 还没连接")
        case .failed(let message):
            showError(message)
        }
    }

    private func scheduleReturnToIdle(after duration: Duration) {
        transientTask?.cancel()
        transientTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.transientTask = nil
            self?.applyBusinessState(.idle, bubble: nil)
        }
    }

    private func synchronizeLatestAgentState() {
        synchronize(
            approvals: latestApprovals,
            turns: latestTurns,
            connection: latestConnection,
            error: latestError
        )
    }

    private func applyBusinessState(
        _ newState: MascotState,
        bubble: String?,
        relatedThreadID: String? = nil
    ) {
        state = newState
        bubbleText = bubble
        self.relatedThreadID = relatedThreadID

        if newState == .idle {
            if interactionTask == nil {
                present(.idle)
                startAmbientBehavior()
            }
        } else {
            interactionTask?.cancel()
            interactionTask = nil
            stopAmbientBehavior()
            present(newState)
        }
    }

    private func present(_ newState: MascotState, restartingAnimation: Bool = false) {
        guard restartingAnimation || presentedState != newState else { return }
        presentedState = newState
        presentationRevision &+= 1
    }

    private func stopAmbientBehavior() {
        ambientTask?.cancel()
        ambientTask = nil
    }

    private static func isRunning(_ status: String) -> Bool {
        let value = status.lowercased()
        return value.contains("progress") || value == "running" || value == "started"
    }
}

private enum AmbientMoment: CaseIterable {
    case wave
    case ponder
    case nap
    case celebrate

    var pose: MascotState {
        switch self {
        case .wave: return .listening
        case .ponder: return .thinking
        case .nap: return .sleep
        case .celebrate: return .success
        }
    }

    var duration: Duration {
        switch self {
        case .wave: return .milliseconds(1_300)
        case .ponder: return .milliseconds(1_800)
        case .nap: return .milliseconds(3_200)
        case .celebrate: return .milliseconds(1_100)
        }
    }

    static func random() -> AmbientMoment {
        allCases.randomElement() ?? .wave
    }
}
