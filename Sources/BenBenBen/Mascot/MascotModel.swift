import Combine
import Foundation

@MainActor
final class MascotModel: ObservableObject {
    @Published private(set) var state: MascotState = .idle
    @Published private(set) var presentedState: MascotState = .idle
    @Published private(set) var presentationRevision = 0
    @Published private(set) var bubbleText: String?
    @Published private(set) var relatedThreadID: String?
    @Published private(set) var isAwake = false
    @Published private(set) var compactHomeScene: CompactHomeScene = .tucked
    @Published private(set) var compactHomeSceneRevision = 0
    @Published private(set) var compactHomeMessage: String?

    private var agentCancellables = Set<AnyCancellable>()
    private var transientTask: Task<Void, Never>?
    private var ambientTask: Task<Void, Never>?
    private var interactionTask: Task<Void, Never>?
    private var lastAmbientMoment: AmbientMoment?
    private var previouslyRunningThreadIDs = Set<String>()
    private var voiceOverride = false
    private var latestApprovals: [AgentRequestID: AgentApprovalRequest] = [:]
    private var latestTurns: [String: AgentTurn] = [:]
    private var latestConnection: AgentConnectionState = .disconnected
    private var latestError: String?

    var isAmbientBehaviorRunning: Bool {
        ambientTask != nil
    }

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

    /// The expanded notch is the awake conversation surface. Ambient play is
    /// allowed only while the dragon is tucked away and operationally idle.
    func setAwake(_ awake: Bool) {
        guard isAwake != awake else { return }
        isAwake = awake

        if awake {
            stopAmbientBehavior()
            presentCompactHomeScene(.tucked, message: nil)
            if state == .idle, interactionTask == nil {
                present(.idle)
            }
        } else if state == .idle, interactionTask == nil {
            startAmbientBehavior()
        }
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

    /// Starts interruptible idle activities while the notch remains asleep.
    /// Waking the dragon or entering an operational state cancels the current
    /// frame sequence immediately.
    func startAmbientBehavior() {
        guard state == .idle,
              !isAwake,
              !voiceOverride,
              ambientTask == nil,
              interactionTask == nil else { return }

        ambientTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .milliseconds(Int64.random(in: 6_000...14_000)))
                } catch {
                    return
                }

                guard let self,
                      self.state == .idle,
                      !self.isAwake,
                      !self.voiceOverride else { return }
                let moment = AmbientMoment.random(avoiding: self.lastAmbientMoment)
                self.lastAmbientMoment = moment
                self.presentCompactHomeScene(
                    moment.compactHomeScene,
                    message: moment.compactHomeMessage,
                    restartingAnimation: true
                )

                for frame in moment.frames {
                    guard self.state == .idle,
                          !self.isAwake,
                          !self.voiceOverride,
                          self.interactionTask == nil else { return }
                    self.present(frame.pose, restartingAnimation: true)

                    do {
                        try await Task.sleep(for: frame.duration)
                    } catch {
                        return
                    }
                }

                guard self.state == .idle,
                      !self.isAwake,
                      !self.voiceOverride,
                      self.interactionTask == nil else { return }
                self.present(.idle)
                self.presentCompactHomeScene(.tucked, message: nil)
            }
        }
    }

    /// Only the expanded dragon is interactive. The folded dragon lives on a
    /// click-through ambient stage and cannot be advanced manually.
    func cycleRestingAction() {
        guard isAwake, state == .idle, !voiceOverride else { return }

        relatedThreadID = nil
        bubbleText = nil
        stopAmbientBehavior()
        interactionTask?.cancel()

        let moment = AmbientMoment.next(after: lastAmbientMoment)
        lastAmbientMoment = moment
        guard let firstFrame = moment.frames.first else { return }
        present(firstFrame.pose, restartingAnimation: true)

        interactionTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: firstFrame.duration)
                for frame in moment.frames.dropFirst() {
                    guard let self,
                          !Task.isCancelled,
                          self.state == .idle,
                          !self.voiceOverride else { return }
                    self.present(frame.pose, restartingAnimation: true)
                    try await Task.sleep(for: frame.duration)
                }
            } catch {
                return
            }

            guard let self,
                  !Task.isCancelled,
                  self.state == .idle,
                  !self.voiceOverride else { return }
            self.interactionTask = nil
            self.present(.idle)
            self.presentCompactHomeScene(.tucked, message: nil)
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
            presentCompactHomeScene(.tucked, message: nil)
            present(newState)
        }
    }

    private func presentCompactHomeScene(
        _ scene: CompactHomeScene,
        message: String?,
        restartingAnimation: Bool = false
    ) {
        guard restartingAnimation
                || compactHomeScene != scene
                || compactHomeMessage != message else { return }
        compactHomeScene = scene
        compactHomeMessage = message
        compactHomeSceneRevision &+= 1
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

private struct AmbientFrame {
    let pose: MascotState
    let duration: Duration
}

private enum AmbientMoment: CaseIterable {
    case photography
    case stroll
    case tea
    case daydream
    case cloudWatching
    case resting
    case reading
    case music
    case gardening
    case snack
    case stretch
    case sketch
    case rain
    case stargazing
    case bubbles
    case wave
    case ponder
    case nap
    case celebrate

    var frames: [AmbientFrame] {
        switch self {
        case .photography:
            return [
                AmbientFrame(pose: .cameraReady, duration: .milliseconds(900)),
                AmbientFrame(pose: .cameraShutter, duration: .milliseconds(320)),
                AmbientFrame(pose: .cameraReady, duration: .milliseconds(650)),
            ]
        case .stroll:
            return [
                AmbientFrame(pose: .walkLeft, duration: .milliseconds(440)),
                AmbientFrame(pose: .walkRight, duration: .milliseconds(440)),
                AmbientFrame(pose: .walkLeft, duration: .milliseconds(440)),
                AmbientFrame(pose: .walkRight, duration: .milliseconds(440)),
            ]
        case .tea:
            return [
                AmbientFrame(pose: .teaHold, duration: .milliseconds(1_000)),
                AmbientFrame(pose: .teaSip, duration: .milliseconds(750)),
                AmbientFrame(pose: .teaHold, duration: .milliseconds(650)),
            ]
        case .daydream:
            return [AmbientFrame(pose: .daydream, duration: .milliseconds(2_800))]
        case .cloudWatching:
            return [AmbientFrame(pose: .cloudWatch, duration: .milliseconds(3_200))]
        case .resting:
            return [AmbientFrame(pose: .rest, duration: .milliseconds(3_600))]
        case .reading:
            return [AmbientFrame(pose: .read, duration: .milliseconds(3_500))]
        case .music:
            return [AmbientFrame(pose: .music, duration: .milliseconds(3_200))]
        case .gardening:
            return [AmbientFrame(pose: .waterFlower, duration: .milliseconds(2_800))]
        case .snack:
            return [AmbientFrame(pose: .snack, duration: .milliseconds(2_200))]
        case .stretch:
            return [AmbientFrame(pose: .stretch, duration: .milliseconds(1_700))]
        case .sketch:
            return [AmbientFrame(pose: .sketch, duration: .milliseconds(3_200))]
        case .rain:
            return [AmbientFrame(pose: .rain, duration: .milliseconds(3_000))]
        case .stargazing:
            return [AmbientFrame(pose: .stargaze, duration: .milliseconds(3_200))]
        case .bubbles:
            return [AmbientFrame(pose: .bubbles, duration: .milliseconds(2_700))]
        case .wave:
            return [AmbientFrame(pose: .listening, duration: .milliseconds(1_300))]
        case .ponder:
            return [AmbientFrame(pose: .thinking, duration: .milliseconds(1_800))]
        case .nap:
            return [AmbientFrame(pose: .sleep, duration: .milliseconds(3_200))]
        case .celebrate:
            return [AmbientFrame(pose: .success, duration: .milliseconds(1_100))]
        }
    }

    var compactHomeScene: CompactHomeScene {
        switch self {
        case .photography, .stretch, .celebrate:
            return .popOut
        case .snack, .stargazing:
            return .throwStar
        case .tea, .bubbles, .wave:
            return .talk
        case .resting, .rain, .nap:
            return .hide
        case .stroll, .daydream, .cloudWatching, .reading, .music,
             .gardening, .sketch, .ponder:
            return .peek3D
        }
    }

    var compactHomeMessage: String? {
        switch self {
        case .tea: return "喝口茶？"
        case .bubbles: return "噗噜噗噜"
        case .wave: return "嘿，我在家！"
        default: return nil
        }
    }

    static func random(avoiding previous: AmbientMoment?) -> AmbientMoment {
        allCases.filter { $0 != previous }.randomElement() ?? .wave
    }

    static func next(after previous: AmbientMoment?) -> AmbientMoment {
        guard let previous,
              let index = allCases.firstIndex(of: previous) else {
            return allCases[0]
        }
        return allCases[(index + 1) % allCases.count]
    }
}
