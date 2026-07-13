import AppKit
import Combine
import SwiftUI

@MainActor
final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
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
        panel.setFrame(panelFrame(for: layout), display: true)
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
            onSelectTask: onSelectTask
        )

        if let hostingView {
            hostingView.rootView = view
            return
        }

        let host = FirstMouseHostingView(rootView: view)
        host.sizingOptions = []
        host.translatesAutoresizingMaskIntoConstraints = true
        host.autoresizingMask = [.width, .height]
        host.wantsLayer = true
        host.layer?.masksToBounds = true
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

    @objc private func screenParametersChanged(_ notification: Notification) {
        let layout = currentLayout()
        rebuildContent(layout: layout)
        panel.setFrame(panelFrame(for: layout), display: true)
    }

    private func preferencesChanged() {
        let layout = currentLayout()
        rebuildContent(layout: layout)
        panel.setFrame(panelFrame(for: layout), display: true)
        panel.orderFrontRegardless()
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
