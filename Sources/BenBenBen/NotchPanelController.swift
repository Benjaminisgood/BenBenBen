import AppKit
import QuartzCore
import SwiftUI

@MainActor
final class NotchPanel: NSPanel {
    var onMouseEvent: ((NSEvent) -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown || event.type == .leftMouseUp {
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
    let mascotModel: MascotModel
    let voiceInteraction: VoiceInteractionController
    let screenContext: ScreenContextMonitor
    let agentContext: NotchAgentContext

    private let presentationState = NotchPresentationState()
    private let companionInteractionState = NotchCompanionInteractionState()
    private let compactPanel: NotchPanel
    private let expandedPanel: NotchPanel
    private let onSendPrompt: (String) -> Void
    private let onStartNewTask: (String) -> Void

    private var hostingView: NSHostingView<NotchCompanionView>?
    private var compactHostingView: NSHostingView<NotchCompanionView>?
    private var mousePollingTimer: Timer?
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

    init(
        mascotModel: MascotModel = MascotModel(),
        voiceInteraction: VoiceInteractionController = VoiceInteractionController(),
        screenContext: ScreenContextMonitor = ScreenContextMonitor(),
        agentContext: NotchAgentContext = NotchAgentContext(),
        onSendPrompt: @escaping (String) -> Void = { _ in },
        onStartNewTask: @escaping (String) -> Void = { _ in }
    ) {
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
        observeGlobalMouseUp()
        observeMenuTracking()
    }

    func showDocked() {
        let layout = currentLayout()
        rebuildContent(layout: layout)
        isExpanded = false
        mascotModel.setAwake(false)
        presentationState.isExpanded = false
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
        setPresentationExpanded(true, animated: animated)
    }

    func collapse(animated: Bool) {
        guard isExpanded else { return }
        isExpanded = false
        expandedPanel.makeFirstResponder(nil)
        expandedPanel.resignKey()
        expandedPanel.orderOut(nil)
        expandedPanel.contentView = nil
        setPresentationExpanded(false, animated: false)
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
        expand(animated: true)
    }

    func updateAgentStore(_ store: AgentStore) {
        agentContext.store = store
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
            presentationState: presentationState,
            mascotModel: mascotModel,
            voiceInteraction: voiceInteraction,
            agentContext: agentContext,
            screenContext: screenContext,
            interactionState: companionInteractionState,
            layout: layout,
            onSendPrompt: onSendPrompt,
            onStartNewTask: onStartNewTask,
            onMascotAction: { [weak self] in self?.mascotModel.cycleRestingAction() },
            onTaskDetailVisibilityChanged: { [weak self] visible in
                self?.setTaskDetailVisible(visible)
            },
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

    private func setPresentationExpanded(_ expanded: Bool, animated: Bool) {
        mascotModel.setAwake(expanded)
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            presentationState.isExpanded = expanded
            return
        }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            presentationState.isExpanded = expanded
        }
    }

    private func setTaskDetailVisible(_ visible: Bool) {
        guard isTaskDetailVisible != visible else { return }
        isTaskDetailVisible = visible
        detailResizeTask?.cancel()

        let shouldAnimate = isExpanded && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        expandedPanel.setFrame(expandedFrame(for: currentLayout()), display: true, animate: shouldAnimate)

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
            case .leftMouseDown: self.beginHotPanelPress()
            case .leftMouseUp: self.endHotPanelPress()
            default: break
            }
        }
    }

    private func observeGlobalMouseUp() {
        globalMouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isExpanded else { return }
                if self.didStartVoiceHold {
                    self.endHotPanelPress()
                } else if self.voiceHoldTask != nil {
                    self.voiceHoldTask?.cancel()
                    self.voiceHoldTask = nil
                }
            }
        }
    }

    private func beginHotPanelPress() {
        voiceHoldTask?.cancel()
        didStartVoiceHold = false

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
            if ProcessInfo.processInfo.environment["BENBENBEN_UI_TEST_EXPANDED"] == "1"
                || activeMenuTrackingCount > 0
                || hasFocusedTextInput
                || agentContext.store?.pendingApprovals.isEmpty == false
                || isPointInExpandedStayRegion(point) {
                cancelCollapse()
            } else {
                scheduleCollapse()
            }
            return
        }

        if activationFrame().contains(point) {
            expand(animated: true, activate: false)
        }
    }

    private func scheduleCollapse() {
        guard collapseTask == nil, activeMenuTrackingCount == 0 else { return }
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.collapseTask = nil
            guard self.activeMenuTrackingCount == 0,
                  !self.hasFocusedTextInput,
                  self.agentContext.store?.pendingApprovals.isEmpty != false,
                  !self.isPointInExpandedStayRegion(NSEvent.mouseLocation) else { return }
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
        let frame = compactPanel.frame
        return frame.width > 0 && frame.height > 0 ? frame : compactFrame(for: currentLayout())
    }

    private func isPointInExpandedStayRegion(_ point: NSPoint) -> Bool {
        expandedPanel.frame.insetBy(dx: -10, dy: -10).contains(point)
    }

    private var hasFocusedTextInput: Bool {
        guard expandedPanel.isKeyWindow else { return false }
        return expandedPanel.firstResponder is NSTextView || expandedPanel.firstResponder is NSTextField
    }

    private func currentLayout() -> NotchLayout {
        NotchGeometry.layout(for: targetScreen())
    }

    private func targetScreen() -> NSScreen? {
        NotchGeometry.targetScreen()
    }

    private func compactFrame(for layout: NotchLayout) -> NSRect {
        let screenFrame = targetScreen()?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return frame(for: layout.compactSize, topY: screenFrame.maxY + layout.compactTopOffset, in: screenFrame)
    }

    private func expandedFrame(for layout: NotchLayout) -> NSRect {
        let screenFrame = targetScreen()?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = isTaskDetailVisible ? layout.expandedDetailSize : layout.expandedSize
        return frame(for: size, topY: screenFrame.maxY + layout.expandedTopOffset, in: screenFrame)
    }

    private func frame(for size: NSSize, topY: CGFloat, in screenFrame: NSRect) -> NSRect {
        NSRect(
            x: screenFrame.midX - size.width / 2,
            y: topY - size.height,
            width: size.width,
            height: size.height
        )
    }
}
