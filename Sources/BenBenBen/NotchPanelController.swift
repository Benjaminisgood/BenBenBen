import AppKit
import Combine
import SwiftUI

struct DragonVoicePressArbitrator {
    enum BeginAction: Equatable {
        case scheduleHold
        case cancelPendingTranscript
    }

    enum HoldAction: Equatable {
        case startOneShotRecording
        case none
    }

    enum ReleaseAction: Equatable {
        case stopOneShotRecording
        case none
    }

    private enum Phase: Equatable {
        case idle
        case waitingForHold
        case recordingOneShot
        case suppressingTap
    }

    private var phase = Phase.idle

    var isTrackingPress: Bool {
        phase != .idle
    }

    mutating func begin(hasPendingTranscript: Bool) -> BeginAction {
        if hasPendingTranscript {
            phase = .suppressingTap
            return .cancelPendingTranscript
        }
        phase = .waitingForHold
        return .scheduleHold
    }

    mutating func holdThresholdReached(conversationEnabled: Bool) -> HoldAction {
        guard phase == .waitingForHold else { return .none }
        if conversationEnabled {
            phase = .suppressingTap
            return .none
        }
        phase = .recordingOneShot
        return .startOneShotRecording
    }

    mutating func release() -> ReleaseAction {
        switch phase {
        case .recordingOneShot:
            phase = .suppressingTap
            return .stopOneShotRecording
        case .waitingForHold:
            phase = .idle
            return .none
        case .idle, .suppressingTap:
            return .none
        }
    }

    mutating func consumeTap() -> Bool {
        guard phase == .suppressingTap else { return true }
        phase = .idle
        return false
    }
}

@MainActor
final class NotchPanel: NSPanel {
    var onMouseEvent: ((NSEvent) -> Void)?
    var lockedContentSize: NSSize?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func setContentSize(_ size: NSSize) {
        super.setContentSize(lockedContentSize ?? size)
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        var lockedFrame = frameRect
        if let lockedContentSize {
            lockedFrame.size = lockedContentSize
        }
        super.setFrame(lockedFrame, display: flag)
    }

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
    let agentContext: NotchAgentContext
    let preferences: NotchPreferences

    private let panel: NotchPanel
    private let onSelectTask: (String) -> Void
    private var hostingView: NSHostingView<NotchCompanionView>?
    private var cachedLayout: NotchLayout?
    private var preferenceCancellable: AnyCancellable?
    private var globalMouseUpMonitor: Any?
    private var voiceHoldTask: DispatchWorkItem?
    private var voiceRecordingStartTask: Task<Void, Never>?
    private var voicePressArbitrator = DragonVoicePressArbitrator()

    init(
        mascotModel: MascotModel = MascotModel(),
        voiceInteraction: VoiceInteractionController = VoiceInteractionController(),
        agentContext: NotchAgentContext = NotchAgentContext(),
        preferences: NotchPreferences = NotchPreferences(),
        onSelectTask: @escaping (String) -> Void = { _ in }
    ) {
        self.mascotModel = mascotModel
        self.voiceInteraction = voiceInteraction
        self.agentContext = agentContext
        self.preferences = preferences
        self.onSelectTask = onSelectTask
        panel = NotchPanel(
            contentRect: .zero,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        super.init()
        configurePanel()
        rebuildContent()
        observeScreenChanges()
        observePreferences()
        observePanelMouseEvents()
        observeGlobalMouseUp()
    }

    func showDocked() {
        show(activate: false)
    }

    func show() {
        show(activate: true)
    }

    func showAgent() {
        if let threadID = mascotModel.relatedThreadID {
            agentContext.store?.selectedThreadID = threadID
        } else if mascotModel.state == .error {
            agentContext.store?.selectedThreadID = nil
        }
        show()
    }

    func updateAgentStore(_ store: AgentStore) {
        agentContext.store = store
    }

    private func show(activate: Bool) {
        let layout = currentLayout()
        if cachedLayout != layout {
            rebuildContent(layout: layout)
        }
        applyFixedLayout(layout)
        if activate {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    private func configurePanel() {
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
            mascotModel: mascotModel,
            voiceInteraction: voiceInteraction,
            agentContext: agentContext,
            layout: layout,
            onVoiceTap: { [weak self] in self?.handleVoiceTap() },
            onSelectTask: onSelectTask
        )

        if let hostingView {
            hostingView.rootView = view
            hostingView.frame = NSRect(origin: .zero, size: layout.panelSize)
            return
        }

        let host = FirstMouseHostingView(rootView: view)
        host.sizingOptions = []
        host.translatesAutoresizingMaskIntoConstraints = true
        host.autoresizingMask = [.width, .height]
        host.wantsLayer = true
        host.layer?.masksToBounds = true
        host.frame = NSRect(origin: .zero, size: layout.panelSize)
        panel.contentView = host
        hostingView = host
    }

    private func observeScreenChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    private func observePreferences() {
        preferenceCancellable = preferences.$physicalWidth
            .combineLatest(preferences.$physicalHeight)
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.preferencesChanged()
            }
    }

    private func observePanelMouseEvents() {
        panel.onMouseEvent = { [weak self] event in
            guard let self else { return }
            switch event.type {
            case .leftMouseDown where self.isMascotHit(event.locationInWindow):
                self.beginVoicePress()
            case .leftMouseUp where self.voicePressArbitrator.isTrackingPress:
                self.endVoicePress()
            default:
                break
            }
        }
    }

    private func observeGlobalMouseUp() {
        globalMouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) {
            [weak self] _ in
            Task { @MainActor in
                guard let self, self.voicePressArbitrator.isTrackingPress else { return }
                self.endVoicePress()
            }
        }
    }

    private func beginVoicePress() {
        voiceHoldTask?.cancel()
        voiceRecordingStartTask?.cancel()
        voiceRecordingStartTask = nil

        switch voicePressArbitrator.begin(
            hasPendingTranscript: voiceInteraction.pendingTranscript != nil
        ) {
        case .cancelPendingTranscript:
            voiceInteraction.cancelPending()
            mascotModel.clearTransient()
        case .scheduleHold:
            let task = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.voiceHoldTask = nil
                guard self.voicePressArbitrator.holdThresholdReached(
                    conversationEnabled: self.voiceInteraction.isConversationEnabled
                ) == .startOneShotRecording else { return }
                self.voiceRecordingStartTask = Task { [weak self] in
                    await self?.voiceInteraction.startRecording()
                }
            }
            voiceHoldTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: task)
        }
    }

    private func endVoicePress() {
        voiceHoldTask?.cancel()
        voiceHoldTask = nil
        let releaseAction = voicePressArbitrator.release()
        voiceRecordingStartTask?.cancel()
        voiceRecordingStartTask = nil
        if releaseAction == .stopOneShotRecording {
            voiceInteraction.stopRecording()
        }
    }

    private func handleVoiceTap() {
        guard voicePressArbitrator.consumeTap() else { return }
        if voiceInteraction.pendingTranscript != nil {
            voiceInteraction.cancelPending()
            mascotModel.clearTransient()
            return
        }
        voiceInteraction.toggleConversation()
    }

    private func isMascotHit(_ point: NSPoint) -> Bool {
        let layout = cachedLayout ?? currentLayout()
        let size = layout.mascotSize
        return NSRect(
            x: (layout.panelSize.width - size) / 2,
            y: layout.panelSize.height - layout.mascotTopOffset - size,
            width: size,
            height: size
        ).contains(point)
    }

    @objc private func screenParametersChanged(_ notification: Notification) {
        let layout = currentLayout()
        rebuildContent(layout: layout)
        applyFixedLayout(layout)
    }

    private func preferencesChanged() {
        let layout = currentLayout()
        rebuildContent(layout: layout)
        applyFixedLayout(layout)
        panel.orderFrontRegardless()
    }

    /// SwiftUI task bubbles have a larger ideal size than the notch surface.
    /// Lock every AppKit sizing path so state changes can only redraw content.
    private func applyFixedLayout(_ layout: NotchLayout) {
        let size = layout.panelSize
        let unconstrained = NSSize(width: 10_000, height: 10_000)
        panel.minSize = .zero
        panel.maxSize = unconstrained
        panel.contentMinSize = .zero
        panel.contentMaxSize = unconstrained
        panel.lockedContentSize = size
        hostingView?.frame = NSRect(origin: .zero, size: size)
        panel.setFrame(panelFrame(for: layout), display: true)
        panel.contentMinSize = size
        panel.contentMaxSize = size
        panel.minSize = size
        panel.maxSize = size
    }

    private func currentLayout() -> NotchLayout {
        NotchGeometry.layout(
            for: targetScreen(),
            physicalNotchOverride: NSSize(
                width: preferences.physicalWidth,
                height: preferences.physicalHeight
            )
        )
    }

    private func targetScreen() -> NSScreen? {
        NotchGeometry.targetScreen()
    }

    private func panelFrame(for layout: NotchLayout) -> NSRect {
        let screenFrame = targetScreen()?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSRect(
            x: screenFrame.midX - layout.panelSize.width / 2,
            y: screenFrame.maxY + layout.topOffset - layout.panelSize.height,
            width: layout.panelSize.width,
            height: layout.panelSize.height
        )
    }
}
