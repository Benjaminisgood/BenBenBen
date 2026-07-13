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
    @Published var activityLevel = CompanionActivityLevel.persisted {
        didSet {
            UserDefaults.standard.set(
                activityLevel.rawValue,
                forKey: "benbenben.companion.activityLevel"
            )
        }
    }

    private var agentBootstrapTask: Task<Void, Never>?
    private var archivedAgentTurnIDs = Set<String>()
    private var proactiveAgentTurnIDs = Set<String>()
    private var artifactBaselines: [String: AgentArtifactSnapshot] = [:]
    private var agentCancellables = Set<AnyCancellable>()
    private lazy var artifactWindowController = AgentArtifactWindowController(
        agentContext: agentContext,
        screenContext: screenContext
    )
    private lazy var taskWindowController = AgentTaskWindowController(agentContext: agentContext)
    private lazy var notchController = NotchPanelController(
        mascotModel: mascotModel,
        voiceInteraction: voiceInteraction,
        agentContext: agentContext,
        onSelectTask: { [weak self] threadID in
            self?.showTaskWindow(threadID: threadID)
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
            self?.handleVoicePrompt(prompt)
        }
        screenContext.onSignificantChange = { [weak self] screenshotURL in
            self?.reactToScreen(screenshotURL)
        }
    }

    func start() {
        guard !didStart else { return }
        didStart = true
        notchController.showDocked()
        voiceInteraction.activatePersistentListeningIfNeeded()
        Task {
            await bootstrapAgent()
        }
    }

    func showNotch() {
        notchController.show()
    }

    func showAgent() {
        notchController.showAgent()
    }

    func showArtifactWindows() {
        artifactWindowController.showAll()
    }

    func showWorkspaceWindows() {
        artifactWindowController.showAll()
        taskWindowController.show()
    }

    func showArtifactWindow(_ kind: AgentArtifactKind) {
        artifactWindowController.show(kind)
    }

    func showTaskWindow(threadID: String? = nil) {
        taskWindowController.show(threadID: threadID)
    }

    func createAgentThread() {
        showAgent()
        Task {
            if agentStore == nil {
                await bootstrapAgent()
            }
            let options = AgentThreadStartOptions(
                cwd: WorkspacePaths.root.path,
                executionMode: agentStore?.defaultExecutionMode ?? .askMe
            )
            _ = await agentStore?.createThread(options: options)
        }
    }

    func updateWorkspaceRoot(_ url: URL?) {
        WorkspacePaths.setRoot(url)
        agentStore?.selectedThreadID = nil
        Task {
            await artifactWindowController.reloadWorkspace()
            await agentStore?.reloadThreads(
                query: AgentThreadListQuery(cwd: [WorkspacePaths.root.path])
            )
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
        let sharedWindows = artifactWindowController.liveContext()
        let liveFocusedFile = focusedFile
            ?? sharedWindows.first(where: \.isFocused)?.selectedFile
        let governedPrompt = AgentOperatingContract.prompt(
            prompt,
            focusedFile: liveFocusedFile,
            sharedWindows: sharedWindows,
            selectedTaskID: taskWindowController.visibleThreadID,
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

    func handleVoicePrompt(_ prompt: String) {
        Task { await processVoicePrompt(prompt) }
    }

    private func processVoicePrompt(_ prompt: String) async {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let intent = VoiceCommandIntent.parse(text)
        var openedWindowNames: [String] = []

        switch intent.screenAction {
        case .enable:
            guard screenContext.enableFromVoice() else {
                mascotModel.showError(screenContext.status.label)
                return
            }
        case .disable:
            screenContext.disableSharing()
        case nil:
            break
        }

        if let kind = intent.artifactKind {
            let file = await artifactWindowController.show(kind, matching: text)
            openedWindowNames.append(file?.lastPathComponent ?? "\(kind.title) 共同窗口")
        }
        if intent.showsTaskWindow {
            showTaskWindow(threadID: agentStore?.selectedThreadID)
            openedWindowNames.append("任务窗口")
        }

        if intent.isPureScreenCommand {
            voiceInteraction.speakConversationReply("已经停止共享屏幕。")
            return
        }

        if intent.isPureWindowCommand {
            let target = openedWindowNames.isEmpty ? "窗口" : openedWindowNames.joined(separator: "、")
            voiceInteraction.speakConversationReply("已经打开\(target)。")
            return
        }

        if let newTaskPrompt = Self.newTaskPrompt(from: text) {
            _ = await submitQuickPrompt(
                newTaskPrompt,
                voiceInitiated: true,
                forceNewThread: true
            )
            return
        }
        if Self.isBareNewTaskCommand(text) {
            if agentStore == nil { await bootstrapAgent() }
            let options = AgentThreadStartOptions(
                cwd: WorkspacePaths.root.path,
                executionMode: agentStore?.defaultExecutionMode ?? .askMe
            )
            if let thread = await agentStore?.createThread(options: options) {
                showTaskWindow(threadID: thread.id)
                voiceInteraction.speakConversationReply("好，这是一个新任务，请继续说具体内容。")
            }
            return
        }

        if await resolvePendingSpokenDecision(text) {
            return
        }

        guard let store = agentStore,
              let threadID = store.selectedThreadID,
              let activeTurn = store.activeTurns[threadID],
              Self.isRunning(activeTurn.status) else {
            _ = await submitQuickPrompt(text, voiceInitiated: true)
            return
        }

        let screenshotURL = await screenContext.captureLatest()
        let sharedWindows = artifactWindowController.liveContext()
        var governedGuidance = AgentOperatingContract.prompt(
            text,
            focusedFile: sharedWindows.first(where: \.isFocused)?.selectedFile,
            sharedWindows: sharedWindows,
            selectedTaskID: taskWindowController.visibleThreadID,
            includesScreen: screenshotURL != nil
        )
        if let screenshotURL {
            governedGuidance += "\nThe latest screen image is available at: \(screenshotURL.path)"
        }
        let accepted = await store.steer(
            governedGuidance,
            threadID: threadID,
            turnID: activeTurn.id
        )
        if accepted {
            voiceInteraction.speakConversationReply("收到，我会按你的新要求继续。")
        }
    }

    private func resolvePendingSpokenDecision(_ text: String) async -> Bool {
        guard let store = agentStore else { return false }
        let selectedThreadID = store.selectedThreadID
        guard let request = store.pendingApprovals.values.first(where: {
            $0.kind == .userInput && ($0.threadID == selectedThreadID || selectedThreadID == nil)
        }), !request.userInputQuestions.isEmpty else { return false }

        let normalized = text.lowercased()
        var answers: [String: [String]] = [:]
        for question in request.userInputQuestions {
            let matchedOption = question.options.first {
                normalized.contains($0.label.lowercased())
            }
            answers[question.id] = [matchedOption?.label ?? text]
        }
        await store.resolveApproval(id: request.id, response: .userInputAnswers(answers))
        voiceInteraction.speakConversationReply("收到你的选择，我会继续。")
        return true
    }

    func sendAgentComposer(_ prompt: String, voiceInitiated: Bool = false) {
        if voiceInitiated {
            handleVoicePrompt(prompt)
            return
        }
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
        guard activityLevel.reactsToScreenChanges else { return }
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
                    if Self.requestsTaskWindow(message) {
                        self.showTaskWindow(threadID: threadID)
                    }
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
                        guard !artifacts.isEmpty, self.activityLevel.revealsArtifacts else { return }
                        await self.artifactWindowController.reveal(artifacts)
                    }
                }
            }
            .store(in: &agentCancellables)

        store.$pendingApprovals
            .receive(on: RunLoop.main)
            .sink { [weak self] approvals in
                guard let self,
                      self.activityLevel.revealsDecisions,
                      let request = approvals.values.first,
                      let threadID = request.threadID else { return }
                self.showTaskWindow(threadID: threadID)
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
        let prefixes = ["新任务", "新的任务", "这是个新任务", "另一个任务", "另外一个任务", "new task"]
        for prefix in prefixes where text.hasPrefix(prefix) {
            let remainder = text.dropFirst(prefix.count)
                .trimmingCharacters(in: CharacterSet(charactersIn: "：:，,。 "))
            return remainder.isEmpty ? nil : remainder
        }
        return nil
    }

    private static func isBareNewTaskCommand(_ text: String) -> Bool {
        let normalized = text.lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "：:，,。.!！?？ "))
        return ["新任务", "新的任务", "这是个新任务", "另一个任务", "另外一个任务", "new task"]
            .contains(normalized)
    }

    private static func visibleAgentMessage(_ raw: String) -> String {
        raw.replacingOccurrences(
            of: #"(?m)^BENBENBEN_ARTIFACT:\s*.*$"#,
            with: "",
            options: .regularExpression
        )
        .replacingOccurrences(
            of: #"(?m)^BENBENBEN_TASK_WINDOW:\s*.*$"#,
            with: "",
            options: .regularExpression
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func requestsTaskWindow(_ raw: String) -> Bool {
        raw.range(
            of: #"(?m)^BENBENBEN_TASK_WINDOW:\s*current\s*$"#,
            options: .regularExpression
        ) != nil
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
