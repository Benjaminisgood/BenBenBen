import AppKit
import Combine
import Foundation

enum AgentPromptSubmissionResult: Equatable, Sendable {
    case accepted(threadID: String)
    case rejected(message: String)
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    let mascotModel: MascotModel
    let voiceInteraction: VoiceInteractionController
    let screenContext: ScreenContextMonitor
    let agentContext: NotchAgentContext
    let runtimeCatalog: RuntimeCatalogStore
    let loginItemStore: LoginItemStore

    @Published private(set) var didStart = false
    @Published private(set) var agentStore: AgentStore?

    private var agentBootstrapTask: Task<Void, Never>?
    private var archivedAgentTurnIDs = Set<String>()
    private var proactiveAgentTurnIDs = Set<String>()
    private var artifactBaselines: [String: AgentArtifactSnapshot] = [:]
    private var agentCancellables = Set<AnyCancellable>()
    private lazy var artifactWindowController = AgentArtifactWindowController(
        agentContext: agentContext,
        screenContext: screenContext,
        onPrompt: { [weak self] prompt, focusedFile in
            guard let self else {
                return .rejected(message: "BenBenBen 已关闭")
            }
            return await self.submitQuickPrompt(
                prompt,
                focusedFile: focusedFile,
                forceNewThread: true
            )
        }
    )
    private lazy var notchController = NotchPanelController(
        mascotModel: mascotModel,
        voiceInteraction: voiceInteraction,
        screenContext: screenContext,
        agentContext: agentContext,
        onSendPrompt: { [weak self] prompt in
            self?.sendAgentComposer(prompt)
        },
        onStartNewTask: { [weak self] prompt in
            self?.startNewAgentTask(prompt)
        }
    )

    private init() {
        mascotModel = MascotModel()
        voiceInteraction = VoiceInteractionController()
        screenContext = ScreenContextMonitor()
        agentContext = NotchAgentContext()
        runtimeCatalog = RuntimeCatalogStore()
        loginItemStore = LoginItemStore()
        WorkspacePaths.ensureDirectories()

        voiceInteraction.onStateChanged = { [weak mascotModel, weak voiceInteraction] listening in
            // Continuous listening is ambient infrastructure. Keep operational
            // Codex states visible instead of pinning the dragon in "listening".
            mascotModel?.setListening(listening && voiceInteraction?.isConversationEnabled != true)
        }
        voiceInteraction.onCountdownChanged = { [weak mascotModel] text, seconds in
            mascotModel?.showVoiceCountdown(text: text, seconds: seconds)
        }
        voiceInteraction.onError = { [weak mascotModel] message in
            mascotModel?.showError(message)
        }
        voiceInteraction.onSend = { [weak self] prompt in
            self?.sendAgentComposer(prompt, voiceInitiated: true)
        }
        screenContext.onSignificantChange = { [weak self] screenshotURL in
            self?.reactToScreen(screenshotURL)
        }
    }

    func start() {
        guard !didStart else { return }
        didStart = true
        notchController.showDocked()
        if screenContext.isEnabled {
            screenContext.start()
        }
        voiceInteraction.activatePersistentListeningIfNeeded()
        Task {
            await bootstrapAgent()
        }
    }

    func showNotch() {
        notchController.expand(animated: true)
    }

    func showAgent() {
        notchController.showAgent()
    }

    func showArtifactWindows() {
        artifactWindowController.showAll()
    }

    func showArtifactWindow(_ kind: AgentArtifactKind) {
        artifactWindowController.show(kind)
    }

    func createAgentThread() {
        showAgent()
        Task {
            if agentStore == nil {
                await bootstrapAgent()
            }
            _ = await agentStore?.createThread()
        }
    }

    func bootstrapAgent() async {
        guard agentStore == nil else { return }
        if let agentBootstrapTask {
            await agentBootstrapTask.value
            return
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performAgentBootstrap()
        }
        agentBootstrapTask = task
        await task.value
        agentBootstrapTask = nil
    }

    private func performAgentBootstrap() async {
        do {
            let preferredPath = UserDefaults.standard.string(forKey: "benbenben.codexExecutable")
            let store = try await AgentStore.live(preferredCodexPath: preferredPath)
            agentStore = store
            notchController.updateAgentStore(store)
            mascotModel.bind(to: store)
            observeVoiceReplyCompletion(in: store)
            await store.connect(
                threadQuery: AgentThreadListQuery(cwd: [WorkspacePaths.root.path])
            )
        } catch {
            mascotModel.showError(error.localizedDescription)
        }
    }

    func sendQuickPrompt(
        _ prompt: String,
        voiceInitiated: Bool = false,
        focusedFile: URL? = nil,
        screenImageURL: URL? = nil,
        proactive: Bool = false,
        forceNewThread: Bool = false
    ) {
        Task {
            _ = await submitQuickPrompt(
                prompt,
                voiceInitiated: voiceInitiated,
                focusedFile: focusedFile,
                screenImageURL: screenImageURL,
                proactive: proactive,
                forceNewThread: forceNewThread
            )
        }
    }

    @discardableResult
    func submitQuickPrompt(
        _ prompt: String,
        voiceInitiated: Bool = false,
        focusedFile: URL? = nil,
        screenImageURL: URL? = nil,
        proactive: Bool = false,
        forceNewThread: Bool = false
    ) async -> AgentPromptSubmissionResult {
        if agentStore == nil {
            await bootstrapAgent()
        }
        guard let store = agentStore else {
            return .rejected(message: "Codex 尚未连接")
        }

        var threadID = forceNewThread ? nil : store.selectedThreadID
        if threadID == nil {
            let options = AgentThreadStartOptions(
                cwd: WorkspacePaths.root.path,
                executionMode: store.defaultExecutionMode
            )
            threadID = await store.createThread(options: options)?.id
        }
        guard let threadID else {
            return .rejected(message: store.lastError ?? "无法创建 Codex 任务")
        }

        let fallbackOptions = AgentThreadStartOptions(
            cwd: WorkspacePaths.root.path,
            executionMode: store.executionMode(for: threadID)
        )
        let artifactBaseline = await Task.detached(priority: .utility) {
            AgentArtifactSnapshot.capture()
        }.value
        let screenshotURL: URL?
        if let screenImageURL {
            screenshotURL = screenImageURL
        } else {
            screenshotURL = await screenContext.captureLatest()
        }
        let governedPrompt = AgentOperatingContract.prompt(
            prompt,
            focusedFile: focusedFile,
            includesScreen: screenshotURL != nil
        )
        guard let sent = await store.send(
            governedPrompt,
            to: threadID,
            localImagePath: screenshotURL?.path,
            fallbackOptions: fallbackOptions
        ) else {
            return .rejected(message: store.lastError ?? "Codex 没有接受这个任务")
        }

        store.selectedThreadID = sent.threadID
        store.setTaskDisplayPrompt(prompt, for: sent.threadID)
        let turnKey = Self.turnKey(threadID: sent.threadID, turnID: sent.turn.id)
        artifactBaselines[turnKey] = artifactBaseline
        if proactive {
            proactiveAgentTurnIDs.insert(turnKey)
        }
        if voiceInitiated {
            voiceInteraction.speakConversationReply("收到，我开始处理这个任务。")
        }
        return .accepted(threadID: sent.threadID)
    }

    func sendAgentComposer(_ prompt: String, voiceInitiated: Bool = false) {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if let newTaskPrompt = Self.newTaskPrompt(from: text) {
            startNewAgentTask(newTaskPrompt, voiceInitiated: voiceInitiated)
            return
        }
        guard let store = agentStore,
              let threadID = store.selectedThreadID,
              let activeTurn = store.activeTurns[threadID],
              Self.isRunning(activeTurn.status) else {
            sendQuickPrompt(text, voiceInitiated: voiceInitiated)
            return
        }

        Task {
            let accepted = await store.steer(text, threadID: threadID, turnID: activeTurn.id)
            if accepted, voiceInitiated {
                voiceInteraction.speakConversationReply("收到，我会按你的新要求继续。")
            }
        }
    }

    func startNewAgentTask(_ prompt: String, voiceInitiated: Bool = false) {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        sendQuickPrompt(
            text,
            voiceInitiated: voiceInitiated,
            forceNewThread: true
        )
    }

    private func reactToScreen(_ screenshotURL: URL) {
        if let store = agentStore,
           let threadID = store.selectedThreadID,
           let turn = store.activeTurns[threadID],
           Self.isRunning(turn.status) {
            return
        }
        sendQuickPrompt(
            "主动观察我当前屏幕。如果有明显错误、阻塞、可继续的工作或值得提醒的内容，请简短回应；否则只回复“继续陪伴”。不要未经确认执行风险动作。",
            screenImageURL: screenshotURL,
            proactive: true
        )
    }

    private func observeVoiceReplyCompletion(in store: AgentStore) {
        agentCancellables.removeAll()
        store.$activeTurns
            .combineLatest(store.$agentMessages)
            .receive(on: RunLoop.main)
            .sink { [weak self] turns, messages in
                guard let self else { return }
                for (threadID, turn) in turns where Self.isCompleted(turn.status) {
                    let turnKey = Self.turnKey(threadID: threadID, turnID: turn.id)
                    guard !self.archivedAgentTurnIDs.contains(turnKey),
                          let message = messages[threadID], !message.isEmpty else { continue }
                    self.archivedAgentTurnIDs.insert(turnKey)
                    let visibleMessage = Self.visibleAgentMessage(message)
                    let isProactive = self.proactiveAgentTurnIDs.remove(turnKey) != nil
                    let shouldSurface = !isProactive || !Self.isPassiveScreenReply(visibleMessage)

                    if shouldSurface,
                       self.voiceInteraction.canSpeakReplies {
                        self.voiceInteraction.speakConversationReply(visibleMessage)
                    }
                    if isProactive, shouldSurface {
                        self.showNotch()
                    }

                    let baseline = self.artifactBaselines.removeValue(forKey: turnKey)
                    let handedOffURLs = Self.artifactURLs(in: message)
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        let current = await Task.detached(priority: .utility) {
                            AgentArtifactSnapshot.capture()
                        }.value
                        var artifacts = baseline.map { current.changes(since: $0) } ?? []
                        for url in handedOffURLs {
                            guard let kind = AgentArtifactKind.kind(containing: url) else { continue }
                            let artifact = AgentArtifact(kind: kind, url: url, modifiedAt: Date())
                            if !artifacts.contains(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) {
                                artifacts.append(artifact)
                            }
                        }
                        guard !artifacts.isEmpty else { return }
                        await self.artifactWindowController.reveal(artifacts)
                    }
                }
            }
            .store(in: &agentCancellables)
    }

    private static func isCompleted(_ status: String) -> Bool {
        let value = status.lowercased()
        return value == "completed" || value == "success" || value == "failed" || value == "interrupted"
    }

    private static func isRunning(_ status: String) -> Bool {
        let value = status.lowercased()
        return value.contains("progress") || value == "running" || value == "started"
    }

    private static func turnKey(threadID: String, turnID: String) -> String {
        "\(threadID):\(turnID)"
    }

    private static func newTaskPrompt(from text: String) -> String? {
        let prefixes = ["新任务", "另一个任务", "另外一个任务"]
        for prefix in prefixes where text.hasPrefix(prefix) {
            let remainder = text.dropFirst(prefix.count)
                .trimmingCharacters(in: CharacterSet(charactersIn: "：:，,。 "))
            return remainder.isEmpty ? nil : remainder
        }
        return nil
    }

    private static func visibleAgentMessage(_ raw: String) -> String {
        raw.replacingOccurrences(
            of: #"(?m)^BENBENBEN_ARTIFACT:\s*.*$"#,
            with: "",
            options: .regularExpression
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func artifactURLs(in raw: String) -> [URL] {
        raw.split(whereSeparator: \Character.isNewline).compactMap { line in
            let prefix = "BENBENBEN_ARTIFACT:"
            let value = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            guard value.hasPrefix(prefix) else { return nil }
            let path = value.dropFirst(prefix.count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard path.hasPrefix("/") else { return nil }
            let url = URL(fileURLWithPath: path).standardizedFileURL
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return url
        }
    }

    private static func isPassiveScreenReply(_ message: String) -> Bool {
        let normalized = message
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "。", with: "")
        return normalized == "继续陪伴"
    }
}
