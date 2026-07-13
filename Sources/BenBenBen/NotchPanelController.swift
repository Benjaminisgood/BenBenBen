import AppKit
import QuartzCore
import SwiftUI

@MainActor
final class NotchPanel: NSPanel {
    var onMouseEvent: ((NSEvent) -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown || event.type == .leftMouseDragged || event.type == .leftMouseUp {
            onMouseEvent?(event)
        }

        super.sendEvent(event)
    }
}

@MainActor
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

@MainActor
final class NotchPanelController: NSObject {
    let environment: WorkbenchEnvironment
    let mascotModel: MascotModel
    let voiceInteraction: VoiceInteractionController
    let screenContext: ScreenContextMonitor
    private var settingsStore: AppSettingsStore { environment.settingsStore }
    private var directoryStore: WorkspaceDirectoryStore { environment.directoryStore }
    private var store: NoteStore { environment.noteStore }
    private var imageStore: LocalImageStore { environment.imageStore }
    private var markdownAIStore: MarkdownAIEditStore { environment.markdownAIStore }
    private var markdownAIChatStore: MarkdownAIChatStore { environment.markdownAIChatStore }
    private var fileLockStore: FilePermissionLockStore { environment.fileLockStore }
    private var drawerState: DrawerState { environment.drawerState }
    private var editorInteractionState: EditorInteractionState { environment.editorInteractionState }
    private var workbenchState: WorkbenchState { environment.workbenchState }
    private var scriptsState: ScriptsModuleState { environment.scriptsState }
    private var shellCommandStore: ShellCommandStore { environment.shellCommandStore }
    private var shellWorkspaceStore: ShellWorkspaceStore { environment.shellWorkspaceStore }
    private var launchdJobStore: LaunchdJobStore { environment.launchdJobStore }
    private var launchdAIAgent: LaunchdAIAgent { environment.launchdAIAgent }
    private var shellAIStore: ScriptAIEditStore { environment.shellAIStore }
    private var pythonAIStore: ScriptAIEditStore { environment.pythonAIStore }
    private var appleScriptAIStore: ScriptAIEditStore { environment.appleScriptAIStore }
    private var condaStore: CondaEnvironmentStore { environment.condaStore }
    private var pythonStore: CodeFileStore { environment.pythonStore }
    private var appleScriptStore: CodeFileStore { environment.appleScriptStore }
    private var terminalRunner: CommandRunner { environment.terminalRunner }
    private var pythonRunner: PythonReplRunner { environment.pythonRunner }
    private var appleScriptRunner: CommandRunner { environment.appleScriptRunner }
    private lazy var settingsPopoverController = SettingsPopoverController(
        settingsStore: settingsStore,
        directoryStore: directoryStore
    )
    private let compactPanel: NotchPanel
    private let expandedPanel: NotchPanel
    let agentContext: NotchAgentContext
    private let companionInteractionState = NotchCompanionInteractionState()
    private var hostingView: NSHostingView<NotchCompanionView>?
    private var compactHostingView: NSHostingView<NotchCompanionView>?
    private var mousePollingTimer: Timer?
    private var globalMouseDragMonitor: Any?
    private var globalMouseUpMonitor: Any?
    private var cachedLayout: NotchLayout?
    private var isExpanded = false
    private var activeMenuTrackingCount = 0
    private var collapseTask: DispatchWorkItem?
    private var voiceHoldTask: DispatchWorkItem?
    private var didStartVoiceHold = false
    private var suppressNextHotClick = false
    private var isTaskDetailVisible = false
    private var detailResizeTask: DispatchWorkItem?
    private let onSendPrompt: (String) -> Void
    private let onStartNewTask: (String) -> Void

    init(
        environment: WorkbenchEnvironment = WorkbenchEnvironment(),
        mascotModel: MascotModel = MascotModel(),
        voiceInteraction: VoiceInteractionController = VoiceInteractionController(),
        screenContext: ScreenContextMonitor = ScreenContextMonitor(),
        agentContext: NotchAgentContext = NotchAgentContext(),
        onSendPrompt: @escaping (String) -> Void = { _ in },
        onStartNewTask: @escaping (String) -> Void = { _ in }
    ) {
        self.environment = environment
        self.mascotModel = mascotModel
        self.voiceInteraction = voiceInteraction
        self.screenContext = screenContext
        self.agentContext = agentContext
        self.onSendPrompt = onSendPrompt
        self.onStartNewTask = onStartNewTask
        compactPanel = NotchPanel(
            contentRect: .zero,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        expandedPanel = NotchPanel(
            contentRect: .zero,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        super.init()
        configurePanel(compactPanel)
        configurePanel(expandedPanel)
        rebuildContent()
        startMousePolling()
        observeScreenChanges()
        observePanelMouseEvents()
        observeGlobalSelectionMouseEvents()
        observeMenuTracking()
    }

    func showDocked() {
        let layout = currentLayout()
        rebuildContent(layout: layout)
        isExpanded = false
        mascotModel.setAwake(false)
        drawerState.isExpanded = false
        drawerState.revealProgress = 0
        compactPanel.setFrame(compactFrame(for: layout), display: true)
        expandedPanel.setFrame(expandedFrame(for: layout), display: true)
        expandedPanel.orderOut(nil)
        compactPanel.orderFrontRegardless()
    }

    func expand(animated: Bool) {
        expand(animated: animated, activate: true)
    }

    private func expand(animated: Bool, activate: Bool) {
        guard !isExpanded else {
            if activate {
                NSApp.activate(ignoringOtherApps: true)
                expandedPanel.makeKeyAndOrderFront(nil)
            } else {
                expandedPanel.orderFrontRegardless()
            }
            return
        }
        let layout = currentLayout()
        cancelCollapse()
        isExpanded = true
        if cachedLayout != layout {
            rebuildContent(layout: layout)
        }
        expandedPanel.setFrame(expandedFrame(for: layout), display: true)
        compactPanel.orderOut(nil)
        compactPanel.contentView = nil
        if expandedPanel.contentView == nil, let hostingView {
            expandedPanel.contentView = hostingView
        }
        if activate {
            NSApp.activate(ignoringOtherApps: true)
            expandedPanel.makeKeyAndOrderFront(nil)
        } else {
            expandedPanel.orderFrontRegardless()
        }
        setDrawerExpanded(true, animated: animated)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) { [weak self] in
            guard let self else { return }
            guard self.isExpanded else { return }
            guard self.drawerState.activeDestination == .markdown else { return }
            self.editorInteractionState.restoreSelection(
                self.store.selectionRange(for: self.store.activeTabID),
                searchingIn: self.hostingView
            )
            self.editorInteractionState.requestLayoutRefresh(searchingIn: self.hostingView)
            self.editorInteractionState.requestFocus(searchingIn: self.hostingView)
        }
    }

    func collapse(animated: Bool) {
        guard isExpanded else { return }
        if drawerState.activeDestination == .markdown,
           let range = editorInteractionState.currentSelectionRange() {
            store.updateSelection(for: store.activeTabID, range: range)
        }
        settingsPopoverController.close(animated: false)
        isExpanded = false
        expandedPanel.makeFirstResponder(nil)
        expandedPanel.resignKey()
        expandedPanel.orderOut(nil)
        expandedPanel.contentView = nil
        setDrawerExpanded(false, animated: false)
        compactPanel.setFrame(compactFrame(for: currentLayout()), display: true)
        if compactPanel.contentView == nil, let compactHostingView {
            compactPanel.contentView = compactHostingView
        }
        compactPanel.orderFrontRegardless()
    }

    func showAgent() {
        cancelCollapse()
        if let threadID = mascotModel.relatedThreadID {
            agentContext.store?.selectedThreadID = threadID
        } else if mascotModel.state == .error {
            agentContext.store?.selectedThreadID = nil
        }
        drawerState.select(.agent)
        expand(animated: true)
    }

    func updateAgentStore(_ store: AgentStore) {
        agentContext.store = store
    }

    private func handleMascotAction() {
        mascotModel.cycleRestingAction()
    }

    func showWorkbenchMode(_ mode: WorkbenchMode) {
        cancelCollapse()
        workbenchState.select(mode)
        drawerState.select(.workbench(mode))
        expand(animated: true)
    }

    func newMarkdownNote() {
        store.addTab()
        showWorkbenchMode(.markdown)
    }

    func newPythonFile() {
        pythonStore.addFile()
        showWorkbenchMode(.python)
    }

    func newShellWorkspace() {
        scriptsState.selectKind(.shell)
        shellWorkspaceStore.addWorkspace()
        let workspace = shellWorkspaceStore.activeWorkspace
        terminalRunner.usePersistence(
            inputURL: workspace.inputURL,
            outputURL: workspace.transcriptURL
        )
        syncShellIntegration()
        showWorkbenchMode(.scripts)
    }

    func runShellCommand() {
        scriptsState.selectKind(.shell)
        showWorkbenchMode(.scripts)
        syncShellIntegration()
    }

    func runPythonFile() {
        showWorkbenchMode(.python)
        syncPythonIntegration()
        let filePath = pythonStore.activeFile.filePath
        pythonRunner.runFile(
            configuration: condaStore.pythonLaunchConfiguration(bridgeScript: PythonReplRunner.bridgeScript),
            filePath: filePath,
            displayName: condaStore.runPythonFileDisplayCommand(filePath: filePath)
        )
    }

    func runPythonCommand() {
        showWorkbenchMode(.python)
        syncPythonIntegration()
        pythonRunner.run(
            configuration: condaStore.pythonLaunchConfiguration(bridgeScript: PythonReplRunner.bridgeScript)
        )
    }

    func newAppleScriptFile() {
        scriptsState.selectKind(.appleScript)
        appleScriptStore.addFile()
        showWorkbenchMode(.scripts)
    }

    func runAppleScriptFile() {
        scriptsState.selectKind(.appleScript)
        showWorkbenchMode(.scripts)
        appleScriptStore.persistActiveFile()
        let filePath = appleScriptStore.activeFile.filePath
        let didLaunch = TerminalAppBridge.run(
            command: AppleScriptCommand.runFile(filePath),
            workingDirectory: directoryStore.appleScriptDirectoryURL.path
        )
        scriptsState.lastLaunchStatus = didLaunch ? "launched in Terminal" : "Terminal launch failed"
    }

    func runAppleScriptCommand() {
        scriptsState.selectKind(.appleScript)
        showWorkbenchMode(.scripts)
        let command = appleScriptRunner.input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }
        let didLaunch = TerminalAppBridge.run(
            command: "/usr/bin/osascript -e \(command.shellEscaped)",
            workingDirectory: directoryStore.appleScriptDirectoryURL.path
        )
        scriptsState.lastLaunchStatus = didLaunch ? "launched in Terminal" : "Terminal launch failed"
    }

    private func syncShellIntegration() {
        terminalRunner.useWorkingDirectory(directoryStore.shellWorkingDirectoryURL)
        terminalRunner.useShellConfiguration(
            bootstrapURL: directoryStore.benshellInitScriptURL,
            environment: ["BENSHELL_HOME": directoryStore.benshellRootDirectoryURL.path]
        )
        shellCommandStore.useBenshellRoot(directoryStore.benshellRootDirectoryURL)
    }

    private func syncPythonIntegration() {
        pythonRunner.useWorkingDirectory(directoryStore.pythonProjectDirectoryURL)
        condaStore.useCondaRoot(directoryStore.condaRootDirectoryURL)
    }

    private func configurePanel(_ panel: NotchPanel) {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.acceptsMouseMovedEvents = true
    }

    private func rebuildContent(layout: NotchLayout? = nil) {
        let layout = layout ?? currentLayout()
        cachedLayout = layout
        let view = NotchCompanionView(
            store: store,
            settingsStore: settingsStore,
            imageStore: imageStore,
            markdownAIStore: markdownAIStore,
            markdownAIChatStore: markdownAIChatStore,
            fileLockStore: fileLockStore,
            drawerState: drawerState,
            editorInteractionState: editorInteractionState,
            workbenchState: workbenchState,
            scriptsState: scriptsState,
            pythonStore: pythonStore,
            appleScriptStore: appleScriptStore,
            shellCommandStore: shellCommandStore,
            shellWorkspaceStore: shellWorkspaceStore,
            launchdJobStore: launchdJobStore,
            launchdAIAgent: launchdAIAgent,
            shellAIStore: shellAIStore,
            pythonAIStore: pythonAIStore,
            appleScriptAIStore: appleScriptAIStore,
            condaStore: condaStore,
            directoryStore: directoryStore,
            terminalRunner: terminalRunner,
            pythonRunner: pythonRunner,
            appleScriptRunner: appleScriptRunner,
            mascotModel: mascotModel,
            voiceInteraction: voiceInteraction,
            agentContext: agentContext,
            screenContext: screenContext,
            interactionState: companionInteractionState,
            layout: layout,
            onSendPrompt: onSendPrompt,
            onStartNewTask: onStartNewTask,
            onMascotAction: { [weak self] in self?.handleMascotAction() },
            onTaskDetailVisibilityChanged: { [weak self] visible in
                self?.setTaskDetailVisible(visible)
            },
            onOpenSettings: { [weak self] in self?.openSettingsPopover() },
            onCollapse: { [weak self] in self?.collapse(animated: true) }
        )

        if let hostingView, let compactHostingView {
            hostingView.rootView = view
            compactHostingView.rootView = view
            return
        }

        func makeHost() -> FirstMouseHostingView<NotchCompanionView> {
            let host = FirstMouseHostingView(rootView: view)
            host.sizingOptions = []
            host.translatesAutoresizingMaskIntoConstraints = true
            host.autoresizingMask = [.width, .height]
            host.wantsLayer = true
            host.layer?.masksToBounds = true
            return host
        }

        let compactHost = makeHost()
        let expandedHost = makeHost()
        compactPanel.contentView = compactHost
        expandedPanel.contentView = expandedHost
        compactHostingView = compactHost
        hostingView = expandedHost
    }

    private func setDrawerExpanded(_ expanded: Bool, animated: Bool) {
        mascotModel.setAwake(expanded)
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            drawerState.isExpanded = expanded
            drawerState.revealProgress = expanded ? 1 : 0
            return
        }

        let animation: Animation = expanded
            ? .spring(response: 0.28, dampingFraction: 0.86)
            : .easeOut(duration: 0.16)

        withAnimation(animation) {
            drawerState.isExpanded = expanded
            drawerState.revealProgress = expanded ? 1 : 0
        }
    }

    private func setTaskDetailVisible(_ visible: Bool) {
        guard isTaskDetailVisible != visible else { return }
        isTaskDetailVisible = visible
        detailResizeTask?.cancel()

        let targetFrame = expandedFrame(for: currentLayout())
        let shouldAnimate = isExpanded && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        expandedPanel.setFrame(targetFrame, display: true, animate: shouldAnimate)

        guard !visible else { return }
        let task = DispatchWorkItem { [weak self] in
            guard let self, !self.isTaskDetailVisible else { return }
            self.expandedPanel.setFrame(
                self.expandedFrame(for: self.currentLayout()),
                display: true,
                animate: false
            )
        }
        detailResizeTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32, execute: task)
    }

    private func startMousePolling() {
        let timer = Timer(
            timeInterval: 1.0 / 20.0,
            target: self,
            selector: #selector(mousePollingTick),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        mousePollingTimer = timer
    }

    private func observeScreenChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    private func observePanelMouseEvents() {
        compactPanel.onMouseEvent = { [weak self] event in
            guard let self else { return }
            switch event.type {
            case .leftMouseDown:
                self.beginHotPanelPress()
            case .leftMouseUp:
                self.endHotPanelPress()
            default:
                break
            }
        }

        expandedPanel.onMouseEvent = { [weak self] event in
            guard let self else { return }
            self.editorInteractionState.handleMouseEvent(event, searchingIn: self.hostingView)
        }
    }

    private func beginHotPanelPress() {
        voiceHoldTask?.cancel()
        didStartVoiceHold = false

        // Persistent conversation already owns the microphone. In that mode a
        // press remains a normal click so the compact dragon is always usable.
        if voiceInteraction.isConversationEnabled {
            suppressNextHotClick = false
            return
        }

        if voiceInteraction.pendingTranscript != nil {
            suppressNextHotClick = true
            voiceInteraction.cancelPending()
            mascotModel.clearTransient()
            return
        }

        suppressNextHotClick = false
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.didStartVoiceHold = true
            Task { await self.voiceInteraction.startRecording() }
        }
        voiceHoldTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: task)
    }

    private func endHotPanelPress() {
        voiceHoldTask?.cancel()
        voiceHoldTask = nil

        if suppressNextHotClick {
            suppressNextHotClick = false
            return
        }
        if didStartVoiceHold {
            didStartVoiceHold = false
            voiceInteraction.stopRecording()
        }
    }

    private func observeGlobalSelectionMouseEvents() {
        globalMouseDragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] _ in
            Task { @MainActor in
                self?.editorInteractionState.noteGlobalMouseDragged()
            }
        }

        globalMouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.editorInteractionState.noteGlobalMouseUp()
                guard !self.isExpanded else { return }
                if self.didStartVoiceHold {
                    self.endHotPanelPress()
                } else if self.voiceHoldTask != nil {
                    self.voiceHoldTask?.cancel()
                    self.voiceHoldTask = nil
                }
            }
        }
    }

    private func observeMenuTracking() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(menuTrackingDidBegin),
            name: NSMenu.didBeginTrackingNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(menuTrackingDidEnd),
            name: NSMenu.didEndTrackingNotification,
            object: nil
        )
    }

    @objc private func screenParametersChanged(_ notification: Notification) {
        let layout = currentLayout()
        cancelCollapse()
        rebuildContent(layout: layout)
        compactPanel.setFrame(compactFrame(for: layout), display: true)
        expandedPanel.setFrame(expandedFrame(for: layout), display: true)
    }

    @objc private func mousePollingTick(_ timer: Timer) {
        handleMouseLocation(NSEvent.mouseLocation)
    }

    @objc private func menuTrackingDidBegin(_ notification: Notification) {
        activeMenuTrackingCount += 1
        cancelCollapse()
    }

    @objc private func menuTrackingDidEnd(_ notification: Notification) {
        activeMenuTrackingCount = max(0, activeMenuTrackingCount - 1)
        guard activeMenuTrackingCount == 0, isExpanded else { return }
        handleMouseLocation(NSEvent.mouseLocation)
    }

    private func handleMouseLocation(_ point: NSPoint) {
        if isExpanded {
            if ProcessInfo.processInfo.environment["BENBENBEN_UI_TEST_EXPANDED"] == "1" {
                cancelCollapse()
                return
            }
            if activeMenuTrackingCount > 0 {
                cancelCollapse()
                return
            }

            if editorInteractionState.isDraggingSelection {
                cancelCollapse()
                return
            }

            if hasFocusedTextInput || agentContext.store?.pendingApprovals.isEmpty == false {
                cancelCollapse()
                return
            }

            if isPointInExpandedStayRegion(point) {
                cancelCollapse()
            } else {
                scheduleCollapse()
            }
            return
        }

        if settingsStore.triggerMode == .hover, activationFrame().contains(point) {
            expand(animated: true, activate: false)
        }
    }

    private func scheduleCollapse() {
        guard collapseTask == nil else { return }
        guard activeMenuTrackingCount == 0 else { return }

        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.collapseTask = nil
            guard self.activeMenuTrackingCount == 0 else { return }
            guard !self.editorInteractionState.isDraggingSelection else { return }
            guard !self.hasFocusedTextInput else { return }
            guard self.agentContext.store?.pendingApprovals.isEmpty != false else { return }
            guard !self.isPointInExpandedStayRegion(NSEvent.mouseLocation) else { return }
            self.collapse(animated: true)
        }

        collapseTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: task)
    }

    private func cancelCollapse() {
        collapseTask?.cancel()
        collapseTask = nil
    }

    private func activationFrame() -> NSRect {
        let layout = currentLayout()
        let frame = compactPanel.frame
        guard frame.width > 0, frame.height > 0 else {
            return compactFrame(for: layout)
        }

        return frame
    }

    private func isPointInExpandedStayRegion(_ point: NSPoint) -> Bool {
        let margin: CGFloat = 10
        return expandedPanel.frame.insetBy(dx: -margin, dy: -margin).contains(point)
            || settingsPopoverController.contains(point)
    }

    private var hasFocusedTextInput: Bool {
        guard expandedPanel.isKeyWindow else { return false }
        return expandedPanel.firstResponder is NSTextView || expandedPanel.firstResponder is NSTextField
    }

    private func openSettingsPopover() {
        cancelCollapse()
        settingsPopoverController.show(relativeTo: expandedPanel)
    }

    private func currentLayout() -> NotchLayout {
        NotchGeometry.layout(for: targetScreen())
    }

    private func targetScreen() -> NSScreen? {
        NotchGeometry.targetScreen()
    }

    private func compactFrame(for layout: NotchLayout) -> NSRect {
        let screen = targetScreen()
        let screenFrame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return frame(for: layout.compactSize, topY: screenFrame.maxY + layout.compactTopOffset, in: screenFrame)
    }

    private func expandedFrame(for layout: NotchLayout) -> NSRect {
        let screen = targetScreen()
        let screenFrame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let topY = screenFrame.maxY + layout.expandedTopOffset
        let size = isTaskDetailVisible ? layout.expandedDetailSize : layout.expandedSize
        return frame(for: size, topY: topY, in: screenFrame)
    }

    private func frame(for size: NSSize, topY: CGFloat, in screenFrame: NSRect) -> NSRect {
        let x = screenFrame.midX - size.width / 2
        let y = topY - size.height

        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }
}
