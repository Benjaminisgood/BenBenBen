import AppKit
import Combine
import SwiftUI
import WebKit

enum AgentArtifactKind: String, CaseIterable, Identifiable, Sendable {
    case html
    case python
    case markdown
    case scripts
    case plist

    var id: String { rawValue }

    var title: String {
        switch self {
        case .html: return "HTML"
        case .python: return "PY"
        case .markdown: return "MD"
        case .scripts: return "SCRIPTS"
        case .plist: return "PLIST"
        }
    }

    var systemImage: String {
        switch self {
        case .html: return "safari"
        case .python: return "chevron.left.forwardslash.chevron.right"
        case .markdown: return "doc.richtext"
        case .scripts: return "terminal"
        case .plist: return "clock.arrow.2.circlepath"
        }
    }

    var roots: [URL] {
        switch self {
        case .html: return [WorkspacePaths.htmlRoot]
        case .python: return [WorkspacePaths.pythonRoot]
        case .markdown: return [WorkspacePaths.markdownRoot]
        case .scripts: return [WorkspacePaths.shellWorkspaceScriptRoot, WorkspacePaths.appleScriptRoot]
        case .plist: return [WorkspacePaths.launchdRoot]
        }
    }

    var extensions: Set<String> {
        switch self {
        case .html: return ["html", "htm"]
        case .python: return ["py"]
        case .markdown: return ["md", "markdown"]
        case .scripts: return ["sh", "zsh", "applescript", "scpt"]
        case .plist: return ["plist"]
        }
    }

    var agentHint: String {
        switch self {
        case .html: return "生成可直接打开的交互页面、报告或小工具"
        case .python: return "分析、教学、科研计算和可复现程序"
        case .markdown: return "知识、文档、学习路径和长期记忆"
        case .scripts: return "Shell 与 AppleScript 自动化"
        case .plist: return "launchd 编排；变更已加载 Job 前必须确认"
        }
    }
}

@MainActor
final class AgentArtifactStore: ObservableObject {
    let kind: AgentArtifactKind
    @Published private(set) var files: [URL] = []
    @Published var selectedURL: URL?
    @Published var text = ""
    @Published private(set) var contentRevision = 0
    @Published private(set) var externalChangeNotice: String?
    @Published private(set) var saveError: String?

    private var selectedModificationDate: Date?
    private var saveTask: Task<Void, Never>?
    private var isApplyingFileContents = false
    private var isRefreshing = false

    init(kind: AgentArtifactKind) {
        self.kind = kind
        Task { await refresh() }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        let artifactKind = kind
        let discovered = await Task.detached(priority: .utility) {
            Self.discover(kind: artifactKind)
        }.value
        files = discovered
        isRefreshing = false
        guard let selectedURL else {
            self.selectedURL = files.first
            loadSelected()
            return
        }
        guard FileManager.default.fileExists(atPath: selectedURL.path) else {
            self.selectedURL = files.first
            loadSelected()
            return
        }
        let date = modificationDate(for: selectedURL)
        guard date != selectedModificationDate, saveTask == nil else { return }
        loadSelected(external: true)
    }

    func select(_ url: URL) {
        saveNow()
        selectedURL = url
        loadSelected()
    }

    func userEdited(_ newText: String) {
        guard !isApplyingFileContents else { return }
        text = newText
        scheduleSave()
    }

    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        guard let selectedURL else { return }
        do {
            try text.write(to: selectedURL, atomically: true, encoding: .utf8)
            selectedModificationDate = modificationDate(for: selectedURL)
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(650))
            guard let self, !Task.isCancelled else { return }
            self.saveTask = nil
            self.saveNow()
        }
    }

    private nonisolated static func discover(kind: AgentArtifactKind) -> [URL] {
        let manager = FileManager.default
        var discovered: [URL] = []
        for root in kind.roots {
            try? manager.createDirectory(at: root, withIntermediateDirectories: true)
            guard let enumerator = manager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let url as URL in enumerator where kind.extensions.contains(url.pathExtension.lowercased()) {
                discovered.append(url)
            }
        }
        return discovered.sorted {
            (modificationDate(for: $0) ?? .distantPast) > (modificationDate(for: $1) ?? .distantPast)
        }
    }

    private func loadSelected(external: Bool = false) {
        guard let selectedURL else {
            isApplyingFileContents = true
            text = ""
            isApplyingFileContents = false
            selectedModificationDate = nil
            contentRevision &+= 1
            return
        }
        do {
            let loaded = try String(contentsOf: selectedURL, encoding: .utf8)
            isApplyingFileContents = true
            text = loaded
            isApplyingFileContents = false
            selectedModificationDate = modificationDate(for: selectedURL)
            contentRevision &+= 1
            saveError = nil
            externalChangeNotice = external ? "Codex 或外部程序刚刚更新了此文件" : nil
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func modificationDate(for url: URL) -> Date? {
        Self.modificationDate(for: url)
    }

    private nonisolated static func modificationDate(for url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}

@MainActor
final class AgentArtifactWindowController {
    private var windows: [AgentArtifactKind: NSWindow] = [:]
    private var stores: [AgentArtifactKind: AgentArtifactStore] = [:]
    private let agentContext: NotchAgentContext
    private let screenContext: ScreenContextMonitor
    private let onPrompt: (String, URL?) async -> AgentPromptSubmissionResult

    init(
        agentContext: NotchAgentContext,
        screenContext: ScreenContextMonitor,
        onPrompt: @escaping (String, URL?) async -> AgentPromptSubmissionResult
    ) {
        self.agentContext = agentContext
        self.screenContext = screenContext
        self.onPrompt = onPrompt
    }

    func showAll() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(width: min(760, visible.width * 0.58), height: min(610, visible.height * 0.72))

        for (index, kind) in AgentArtifactKind.allCases.enumerated() {
            let window = window(for: kind)
            let offset = CGFloat(index) * 26
            window.setFrame(
                NSRect(
                    x: visible.midX - size.width / 2 + offset - 52,
                    y: visible.midY - size.height / 2 - offset + 52,
                    width: size.width,
                    height: size.height
                ),
                display: true
            )
            window.orderFront(nil)
        }
        windows[.markdown]?.makeKeyAndOrderFront(nil)
    }

    func show(_ kind: AgentArtifactKind) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window(for: kind).makeKeyAndOrderFront(nil)
    }

    func reveal(_ artifacts: [AgentArtifact]) async {
        var newestByKind: [AgentArtifactKind: AgentArtifact] = [:]
        for artifact in artifacts where newestByKind[artifact.kind] == nil {
            newestByKind[artifact.kind] = artifact
        }

        for artifact in newestByKind.values.sorted(by: { $0.modifiedAt < $1.modifiedAt }) {
            _ = window(for: artifact.kind)
            guard let store = stores[artifact.kind] else { continue }
            await store.refresh()
            store.select(artifact.url)
            show(artifact.kind)
        }
    }

    private func window(for kind: AgentArtifactKind) -> NSWindow {
        if let existing = windows[kind] { return existing }
        let store = AgentArtifactStore(kind: kind)
        stores[kind] = store
        let root = AgentArtifactWindowView(
            store: store,
            agentContext: agentContext,
            screenContext: screenContext,
            onPrompt: onPrompt
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 740, height: 580),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Ben龙 · \(kind.title) 共同窗口"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenAuxiliary]
        window.contentView = NSHostingView(rootView: root)
        windows[kind] = window
        return window
    }
}

private struct AgentArtifactWindowView: View {
    @ObservedObject var store: AgentArtifactStore
    @ObservedObject var agentContext: NotchAgentContext
    @ObservedObject var screenContext: ScreenContextMonitor
    let onPrompt: (String, URL?) async -> AgentPromptSubmissionResult

    @State private var draft = ""
    @State private var isSubmitting = false
    @State private var submissionMessage: String?
    @State private var submissionFailed = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                fileList
                    .frame(minWidth: 170, idealWidth: 220, maxWidth: 280)
                editor
                    .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            composer
        }
        .background(.regularMaterial)
        .task {
            while !Task.isCancelled {
                await store.refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
        .onDisappear { store.saveNow() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Label(store.kind.title, systemImage: store.kind.systemImage)
                .font(.headline)
            Text(store.kind.agentHint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Label(screenContext.status.label, systemImage: screenContext.isEnabled ? "eye.fill" : "eye.slash")
                .font(.caption2)
                .foregroundStyle(screenContext.isEnabled ? .green : .secondary)
            Circle()
                .fill(agentReady ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
            Text(agentReady ? "Codex" : "连接中")
                .font(.caption2)
        }
        .padding(.horizontal, 14)
        .padding(.top, 30)
        .padding(.bottom, 9)
    }

    private var fileList: some View {
        List(selection: Binding(
            get: { store.selectedURL },
            set: { if let url = $0 { store.select(url) } }
        )) {
            if store.files.isEmpty {
                ContentUnavailableView(
                    "等待 Agent 创建 \(store.kind.title)",
                    systemImage: store.kind.systemImage,
                    description: Text("在下方告诉 Ben龙 你要的产物")
                )
            } else {
                ForEach(store.files, id: \.self) { url in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(url.lastPathComponent).lineLimit(1)
                        Text(relativePath(url))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .tag(url)
                }
            }
        }
        .listStyle(.sidebar)
    }

    private var editor: some View {
        VStack(spacing: 0) {
            if let url = store.selectedURL {
                HStack {
                    Text(url.path)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    if let notice = store.externalChangeNotice {
                        Text(notice).font(.caption2).foregroundStyle(.green)
                    }
                    if let error = store.saveError {
                        Text(error).font(.caption2).foregroundStyle(.red).lineLimit(1)
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 28)

                if store.kind == .html {
                    LocalHTMLArtifactView(url: url, revision: store.contentRevision)
                        .background(Color.white)
                } else {
                    TextEditor(text: Binding(
                        get: { store.text },
                        set: { value in store.userEdited(value) }
                    ))
                        .font(.system(.body, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(.black.opacity(0.12))
                }
            } else {
                ContentUnavailableView(
                    "这是 Agent 驱动的共同画布",
                    systemImage: "sparkles",
                    description: Text("描述目标后，Codex 会在约定目录创建文件并让它自动出现在这里。")
                )
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                if isSubmitting {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "sparkles")
                }
                TextField("告诉 Ben龙 要在这个共同窗口完成什么…", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...3)
                    .disabled(isSubmitting)
                    .onSubmit(send)
                Button(isSubmitting ? "提交中" : "交给 Codex", systemImage: "arrow.up") { send() }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        isSubmitting
                            || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
            }
            if let submissionMessage {
                Text(submissionMessage)
                    .font(.caption2)
                    .foregroundStyle(submissionFailed ? Color.red : Color.green)
                    .lineLimit(2)
            }
        }
        .padding(10)
    }

    private var agentReady: Bool {
        guard let contextStore = agentContext.store else { return false }
        if case .ready = contextStore.connectionState { return true }
        return false
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSubmitting else { return }
        store.saveNow()
        isSubmitting = true
        submissionFailed = false
        submissionMessage = "正在创建独立任务…"
        let focusedFile = store.selectedURL

        Task { @MainActor in
            let result = await onPrompt("在 \(store.kind.title) 共同窗口中：\(text)", focusedFile)
            isSubmitting = false
            switch result {
            case .accepted:
                draft = ""
                submissionFailed = false
                submissionMessage = "已交给 Codex，正在作为独立任务运行"
            case .rejected(let message):
                submissionFailed = true
                submissionMessage = message
            }
        }
    }

    private func relativePath(_ url: URL) -> String {
        url.path.replacingOccurrences(of: WorkspacePaths.root.path + "/", with: "")
    }
}

private struct LocalHTMLArtifactView: NSViewRepresentable {
    let url: URL
    let revision: Int

    final class Coordinator {
        var loadedToken: String?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsMagnification = true
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let standardizedURL = url.standardizedFileURL
        let token = "\(standardizedURL.path)#\(revision)"
        guard context.coordinator.loadedToken != token else { return }
        context.coordinator.loadedToken = token
        webView.loadFileURL(
            standardizedURL,
            allowingReadAccessTo: WorkspacePaths.htmlRoot.standardizedFileURL
        )
    }
}
