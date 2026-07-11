import AppKit
import SwiftUI

@MainActor
final class NotchPanel: NSPanel {
    var onMouseEvent: ((NSEvent) -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

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
    private let hotPanel: NotchPanel
    private let drawerPanel: NotchPanel
    private var hostingView: NSHostingView<NotebookView>?
    private var hotHostingView: NSHostingView<CompactNotchView>?
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
    private let onSendPrompt: (String) -> Void
    private let onOpenAgent: () -> Void

    init(
        environment: WorkbenchEnvironment = WorkbenchEnvironment(),
        mascotModel: MascotModel = MascotModel(),
        voiceInteraction: VoiceInteractionController = VoiceInteractionController(),
        onSendPrompt: @escaping (String) -> Void = { _ in },
        onOpenAgent: @escaping () -> Void = {}
    ) {
        self.environment = environment
        self.mascotModel = mascotModel
        self.voiceInteraction = voiceInteraction
        self.onSendPrompt = onSendPrompt
        self.onOpenAgent = onOpenAgent
        hotPanel = NotchPanel(
            contentRect: .zero,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        drawerPanel = NotchPanel(
            contentRect: .zero,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        super.init()
        configurePanel(hotPanel)
        configurePanel(drawerPanel)
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
        drawerState.isExpanded = false
        drawerState.revealProgress = 0
        hotPanel.setFrame(hotFrame(for: layout), display: true)
        hotPanel.orderFrontRegardless()
        drawerPanel.setFrame(drawerFrame(for: layout), display: true)
        drawerPanel.orderOut(nil)
    }

    func expand(animated: Bool) {
        guard !isExpanded else { return }
        let layout = currentLayout()
        cancelCollapse()
        isExpanded = true
        rebuildContent(layout: layout)
        drawerPanel.setFrame(drawerFrame(for: layout), display: true)
        NSApp.activate(ignoringOtherApps: true)
        drawerPanel.makeKeyAndOrderFront(nil)
        hotPanel.orderOut(nil)
        setDrawerExpanded(true, animated: animated)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) { [weak self] in
            guard let self else { return }
            guard self.isExpanded else { return }
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
        if let range = editorInteractionState.currentSelectionRange() {
            store.updateSelection(for: store.activeTabID, range: range)
        }
        settingsPopoverController.close(animated: false)
        isExpanded = false
        setDrawerExpanded(false, animated: animated)
        let delay: TimeInterval = animated ? 0.18 : 0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            guard !self.isExpanded else { return }
            let layout = self.currentLayout()
            self.drawerPanel.orderOut(nil)
            self.hotPanel.setFrame(self.hotFrame(for: layout), display: true)
            self.hotPanel.orderFrontRegardless()
        }
    }

    func showWorkbenchMode(_ mode: WorkbenchMode) {
        cancelCollapse()
        workbenchState.select(mode)
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
        let hotView = CompactNotchView(
            layout: layout,
            mascotModel: mascotModel,
            voiceInteraction: voiceInteraction
        )
        let view = NotebookView(
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
            layout: layout,
            onSendPrompt: onSendPrompt,
            onOpenAgent: onOpenAgent,
            onOpenSettings: { [weak self] in self?.openSettingsPopover() }
        )

        if let hotHostingView {
            hotHostingView.rootView = hotView
        } else {
            let host = FirstMouseHostingView(rootView: hotView)
            host.translatesAutoresizingMaskIntoConstraints = false
            host.wantsLayer = true
            host.layer?.masksToBounds = true
            hotPanel.contentView = host
            hotHostingView = host
        }

        if let hostingView {
            hostingView.rootView = view
            return
        }

        let host = FirstMouseHostingView(rootView: view)
        host.translatesAutoresizingMaskIntoConstraints = false
        host.wantsLayer = true
        host.layer?.masksToBounds = true
        drawerPanel.contentView = host
        hostingView = host
    }

    private func setDrawerExpanded(_ expanded: Bool, animated: Bool) {
        guard animated else {
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

    private func startMousePolling() {
        let timer = Timer(
            timeInterval: 1.0 / 60.0,
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
        hotPanel.onMouseEvent = { [weak self] event in
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

        drawerPanel.onMouseEvent = { [weak self] event in
            guard let self else { return }
            self.editorInteractionState.handleMouseEvent(event, searchingIn: self.hostingView)
        }
    }

    private func beginHotPanelPress() {
        voiceHoldTask?.cancel()
        didStartVoiceHold = false

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
            return
        }
        expand(animated: true)
    }

    private func observeGlobalSelectionMouseEvents() {
        globalMouseDragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] _ in
            Task { @MainActor in
                self?.editorInteractionState.noteGlobalMouseDragged()
            }
        }

        globalMouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            Task { @MainActor in
                self?.editorInteractionState.noteGlobalMouseUp()
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
        hotPanel.setFrame(hotFrame(for: layout), display: true)
        drawerPanel.setFrame(drawerFrame(for: layout), display: true)
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
            if activeMenuTrackingCount > 0 {
                cancelCollapse()
                return
            }

            if editorInteractionState.isDraggingSelection {
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
            expand(animated: true)
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
        let frame = hotPanel.frame
        guard frame.width > 0, frame.height > 0 else {
            return hotFrame(for: layout)
        }

        return frame
    }

    private func isPointInExpandedStayRegion(_ point: NSPoint) -> Bool {
        let margin: CGFloat = 10
        return drawerPanel.frame.insetBy(dx: -margin, dy: -margin).contains(point)
            || activationFrame().contains(point)
            || settingsPopoverController.contains(point)
    }

    private func openSettingsPopover() {
        cancelCollapse()
        settingsPopoverController.show(relativeTo: drawerPanel)
    }

    private func currentLayout() -> NotchLayout {
        NotchGeometry.layout(for: targetScreen())
    }

    private func targetScreen() -> NSScreen? {
        NotchGeometry.targetScreen()
    }

    private func hotFrame(for layout: NotchLayout) -> NSRect {
        let screen = targetScreen()
        let screenFrame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return frame(for: layout.compactSize, topY: screenFrame.maxY + layout.compactTopOffset, in: screenFrame)
    }

    private func drawerFrame(for layout: NotchLayout) -> NSRect {
        let screen = targetScreen()
        let screenFrame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let topY = screenFrame.maxY + layout.expandedTopOffset
        return frame(for: layout.expandedSize, topY: topY, in: screenFrame)
    }

    private func frame(for size: NSSize, topY: CGFloat, in screenFrame: NSRect) -> NSRect {
        let x = screenFrame.midX - size.width / 2
        let y = topY - size.height

        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }
}
