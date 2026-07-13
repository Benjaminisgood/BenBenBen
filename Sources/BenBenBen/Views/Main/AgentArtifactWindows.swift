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

struct AgentSharedWindowContext: Equatable, Sendable {
    let kind: AgentArtifactKind
    let files: [URL]
    let selectedFile: URL?
    let isFocused: Bool
}

@MainActor
final class AgentArtifactStore: ObservableObject {
    let kind: AgentArtifactKind
    @Published private(set) var files: [URL] = []
    @Published private(set) var openURLs: [URL] = []
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
        openURLs.removeAll { !FileManager.default.fileExists(atPath: $0.path) }
        isRefreshing = false
        guard let selectedURL else {
            if let first = files.first { select(first) }
            return
        }
        guard FileManager.default.fileExists(atPath: selectedURL.path) else {
            if let first = files.first {
                select(first)
            } else {
                self.selectedURL = nil
                loadSelected()
            }
            return
        }
        let date = modificationDate(for: selectedURL)
        guard date != selectedModificationDate, saveTask == nil else { return }
        loadSelected(external: true)
    }

    func select(_ url: URL) {
        saveNow()
        if !openURLs.contains(url) {
            openURLs.append(url)
        }
        selectedURL = url
        loadSelected()
    }

    func closeTab(_ url: URL) {
        guard let index = openURLs.firstIndex(of: url) else { return }
        if selectedURL == url { saveNow() }
        openURLs.remove(at: index)
        guard selectedURL == url else { return }
        if openURLs.isEmpty {
            selectedURL = nil
            loadSelected()
        } else {
            select(openURLs[min(index, openURLs.count - 1)])
        }
    }

    func reloadWorkspace() async {
        saveNow()
        openURLs = []
        selectedURL = nil
        loadSelected()
        await refresh()
    }

    func bestMatchingFile(for spokenText: String) -> URL? {
        let query = Self.searchKey(spokenText)
        return files.filter { url in
            let fullName = Self.searchKey(url.lastPathComponent)
            let baseName = Self.searchKey(url.deletingPathExtension().lastPathComponent)
            return (!baseName.isEmpty && query.contains(baseName))
                || (!fullName.isEmpty && query.contains(fullName))
        }.max { left, right in
            left.deletingPathExtension().lastPathComponent.count
                < right.deletingPathExtension().lastPathComponent.count
        }
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

    private nonisolated static func searchKey(_ value: String) -> String {
        String(value.lowercased().filter { $0.isLetter || $0.isNumber })
    }
}

@MainActor
final class AgentArtifactWindowController {
    private var windows: [AgentArtifactKind: NSWindow] = [:]
    private var stores: [AgentArtifactKind: AgentArtifactStore] = [:]
    private let agentContext: NotchAgentContext
    private let screenContext: ScreenContextMonitor

    init(
        agentContext: NotchAgentContext,
        screenContext: ScreenContextMonitor
    ) {
        self.agentContext = agentContext
        self.screenContext = screenContext
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

    @discardableResult
    func show(_ kind: AgentArtifactKind, matching spokenText: String) async -> URL? {
        _ = window(for: kind)
        guard let store = stores[kind] else { return nil }
        await store.refresh()
        let match = store.bestMatchingFile(for: spokenText)
        if let match { store.select(match) }
        show(kind)
        return match
    }

    func liveContext() -> [AgentSharedWindowContext] {
        AgentArtifactKind.allCases.compactMap { kind in
            guard let window = windows[kind],
                  window.isVisible,
                  !window.isMiniaturized,
                  let store = stores[kind],
                  !store.openURLs.isEmpty else { return nil }
            return AgentSharedWindowContext(
                kind: kind,
                files: store.openURLs,
                selectedFile: store.selectedURL,
                isFocused: window.isKeyWindow
            )
        }
    }

    func reloadWorkspace() async {
        for store in stores.values {
            await store.reloadWorkspace()
        }
    }

    func reveal(_ artifacts: [AgentArtifact]) async {
        let grouped = Dictionary(grouping: artifacts, by: \.kind)
        for kind in AgentArtifactKind.allCases {
            guard let kindArtifacts = grouped[kind], !kindArtifacts.isEmpty else { continue }
            _ = window(for: kind)
            guard let store = stores[kind] else { continue }
            await store.refresh()
            for artifact in kindArtifacts.sorted(by: { $0.modifiedAt < $1.modifiedAt }) {
                store.select(artifact.url)
            }
            show(kind)
        }
    }

    private func window(for kind: AgentArtifactKind) -> NSWindow {
        if let existing = windows[kind] { return existing }
        let store = AgentArtifactStore(kind: kind)
        stores[kind] = store
        let root = AgentArtifactWindowView(
            store: store,
            agentContext: agentContext,
            screenContext: screenContext
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
                    description: Text("对 Ben龙说出目标，产物会自动出现在这里")
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
                tabBar
                Divider()
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

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(store.openURLs, id: \.self) { url in
                    HStack(spacing: 6) {
                        Image(systemName: url == store.selectedURL ? "doc.fill" : "doc")
                            .font(.caption2)
                        Text(url.lastPathComponent)
                            .font(.caption)
                            .lineLimit(1)
                        Button {
                            store.closeTab(url)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .buttonStyle(.plain)
                        .help("关闭标签页")
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(
                        url == store.selectedURL ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08),
                        in: .rect(cornerRadius: 8)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { store.select(url) }
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
        }
        .frame(height: 40)
    }

    private var agentReady: Bool {
        guard let contextStore = agentContext.store else { return false }
        if case .ready = contextStore.connectionState { return true }
        return false
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
