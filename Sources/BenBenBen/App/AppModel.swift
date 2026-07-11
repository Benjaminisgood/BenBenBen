import AppKit
import Combine
import Foundation

enum MainRoute: String, CaseIterable, Hashable, Identifiable {
    case home
    case today
    case inbox
    case agents
    case knowledge
    case scripts
    case python
    case automations

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .today: return "Today"
        case .inbox: return "Inbox"
        case .agents: return "Agents"
        case .knowledge: return "Knowledge"
        case .scripts: return "Scripts"
        case .python: return "Python"
        case .automations: return "Automations"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house"
        case .today: return "sun.max"
        case .inbox: return "tray"
        case .agents: return "sparkles"
        case .knowledge: return "books.vertical"
        case .scripts: return "terminal"
        case .python: return "chevron.left.forwardslash.chevron.right"
        case .automations: return "clock.arrow.2.circlepath"
        }
    }
}

enum AgentConversationRole: Sendable {
    case user
    case assistant
}

struct AgentConversationEntry: Identifiable, Sendable {
    let id = UUID()
    let role: AgentConversationRole
    let text: String
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    let workbench: WorkbenchEnvironment
    let personalWorkspace: PersonalWorkspaceStore
    let mascotModel: MascotModel
    let voiceInteraction: VoiceInteractionController
    let runtimeCatalog: RuntimeCatalogStore
    let loginItemStore: LoginItemStore

    @Published var selectedRoute: MainRoute = .home
    @Published var globalSearch = ""
    @Published var isInspectorPresented = true
    @Published private(set) var didStart = false
    @Published private(set) var agentStore: AgentStore?
    @Published private(set) var agentConversation: [String: [AgentConversationEntry]] = [:]

    private var isBootstrappingAgent = false
    private var voiceReplyThreadID: String?
    private var archivedAgentTurnIDs = Set<String>()
    private var agentCancellables = Set<AnyCancellable>()
    private lazy var notchController = NotchPanelController(
        environment: workbench,
        mascotModel: mascotModel,
        voiceInteraction: voiceInteraction,
        onSendPrompt: { [weak self] prompt in
            self?.sendQuickPrompt(prompt)
        },
        onOpenAgent: { [weak self] in
            self?.showRelatedAgentThread()
        }
    )

    private init() {
        workbench = WorkbenchEnvironment()
        personalWorkspace = PersonalWorkspaceStore()
        mascotModel = MascotModel()
        voiceInteraction = VoiceInteractionController()
        runtimeCatalog = RuntimeCatalogStore()
        loginItemStore = LoginItemStore()

        voiceInteraction.onStateChanged = { [weak mascotModel] listening in
            mascotModel?.setListening(listening)
        }
        voiceInteraction.onCountdownChanged = { [weak mascotModel] text, seconds in
            mascotModel?.showVoiceCountdown(text: text, seconds: seconds)
        }
        voiceInteraction.onError = { [weak mascotModel] message in
            mascotModel?.showError(message)
        }
        voiceInteraction.onSend = { [weak self] prompt in
            self?.sendQuickPrompt(prompt, voiceInitiated: true)
        }
    }

    func start() {
        guard !didStart else { return }
        didStart = true
        notchController.showDocked()
        Task {
            await personalWorkspace.refresh()
        }
        Task {
            await bootstrapAgent()
        }
    }

    func showNotch() {
        notchController.expand(animated: true)
    }

    func showWorkbench(_ mode: WorkbenchMode) {
        workbench.workbenchState.select(mode)
        selectedRoute = switch mode {
        case .markdown: .knowledge
        case .scripts: .scripts
        case .python: .python
        case .tasks: .automations
        }
        showMainWindow()
    }

    func showMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.title == "BenBenBen" }) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    func bootstrapAgent() async {
        guard agentStore == nil, !isBootstrappingAgent else { return }
        isBootstrappingAgent = true
        defer { isBootstrappingAgent = false }

        do {
            let preferredPath = UserDefaults.standard.string(forKey: "benbenben.codexExecutable")
            let store = try await AgentStore.live(preferredCodexPath: preferredPath)
            agentStore = store
            mascotModel.bind(to: store)
            observeVoiceReplyCompletion(in: store)
            await store.connect()
        } catch {
            mascotModel.showError(error.localizedDescription)
        }
    }

    func sendQuickPrompt(_ prompt: String, voiceInitiated: Bool = false) {
        Task {
            if agentStore == nil {
                await bootstrapAgent()
            }
            guard let store = agentStore else { return }

            var threadID = store.selectedThreadID
            if threadID == nil {
                let options = AgentThreadStartOptions(cwd: personalWorkspace.registry.root.path)
                threadID = await store.createThread(options: options)?.id
            }
            guard let threadID else { return }

            store.selectedThreadID = threadID
            if voiceInitiated {
                voiceReplyThreadID = threadID
            }
            if await store.send(prompt, to: threadID) != nil {
                agentConversation[threadID, default: []].append(
                    AgentConversationEntry(role: .user, text: prompt)
                )
            }
        }
    }

    func sendAgentComposer(_ prompt: String) {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard let store = agentStore,
              let threadID = store.selectedThreadID,
              let activeTurn = store.activeTurns[threadID],
              Self.isRunning(activeTurn.status) else {
            sendQuickPrompt(text)
            return
        }

        agentConversation[threadID, default: []].append(
            AgentConversationEntry(role: .user, text: text)
        )
        Task {
            await store.steer(text, threadID: threadID, turnID: activeTurn.id)
        }
    }

    func showRelatedAgentThread() {
        if let threadID = mascotModel.relatedThreadID {
            agentStore?.selectedThreadID = threadID
        }
        selectedRoute = .agents
        showMainWindow()
    }

    private func observeVoiceReplyCompletion(in store: AgentStore) {
        agentCancellables.removeAll()
        store.$activeTurns
            .combineLatest(store.$agentMessages)
            .receive(on: RunLoop.main)
            .sink { [weak self] turns, messages in
                guard let self else { return }
                for (threadID, turn) in turns where Self.isCompleted(turn.status) {
                    let turnKey = "\(threadID):\(turn.id)"
                    guard !self.archivedAgentTurnIDs.contains(turnKey),
                          let message = messages[threadID], !message.isEmpty else { continue }
                    self.archivedAgentTurnIDs.insert(turnKey)
                    self.agentConversation[threadID, default: []].append(
                        AgentConversationEntry(role: .assistant, text: message)
                    )
                    if self.voiceReplyThreadID == threadID {
                        self.voiceReplyThreadID = nil
                        self.voiceInteraction.speakVoiceInitiatedReply(message)
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
}
