import AppKit
import MarkdownEngine
import MarkdownEngineLatex
import SwiftUI

struct MarkdownEditorPanel: View {
    @ObservedObject var store: NoteStore
    @ObservedObject var settingsStore: AppSettingsStore
    let imageStore: LocalImageStore
    @ObservedObject var aiStore: MarkdownAIEditStore
    @ObservedObject var chatStore: MarkdownAIChatStore
    @ObservedObject var fileLockStore: FilePermissionLockStore
    let editorInteractionState: EditorInteractionState
    let size: CGSize

    @State private var aiMode: MarkdownAIMode = .edit

    private let outputHeight: CGFloat = 132
    private let toolbarHeight: CGFloat = 34
    private let separatorHeight: CGFloat = 1

    var body: some View {
        VStack(spacing: 0) {
            MarkdownNoteEditor(
                store: store,
                imageStore: imageStore,
                fileLockStore: fileLockStore,
                editorInteractionState: editorInteractionState
            )
            .frame(width: size.width, height: editorHeight)

            Rectangle()
                .fill(.white.opacity(0.045))
                .frame(width: size.width, height: separatorHeight)

            Group {
                switch aiMode {
                case .edit:
                    MarkdownAIReviewView(aiStore: aiStore)
                case .chat:
                    MarkdownAIChatView(chatStore: chatStore)
                }
            }
            .frame(width: size.width, height: outputHeight)

            Rectangle()
                .fill(.white.opacity(0.045))
                .frame(width: size.width, height: separatorHeight)

            MarkdownShortcutToolbar(
                editorInteractionState: editorInteractionState,
                aiStore: aiStore,
                chatStore: chatStore,
                aiMode: $aiMode,
                onSubmitAI: { submitAIEdit() },
                onSubmitChat: submitChat,
                onAcceptAI: acceptAIEdit,
                onRejectAI: aiStore.rejectProposal,
                onOptimizeMarkdown: optimizeCurrentMarkdown,
                onPracticeMarkdown: startPracticeSession,
                onOpenExternally: store.openActiveTabInDefaultEditor,
                isReadOnly: isActiveFileLocked
            )
                .frame(width: size.width, height: toolbarHeight)
                .background(Color(red: 0.055, green: 0.055, blue: 0.065))
        }
    }

    private var editorHeight: CGFloat {
        max(size.height - outputHeight - toolbarHeight - separatorHeight * 2, 120)
    }

    private var isActiveFileLocked: Bool {
        fileLockStore.isLocked(store.activeTab.fileURL)
    }

    private func submitAIEdit(selectedRange explicitRange: NSRange? = nil) {
        guard !isActiveFileLocked else { return }
        let range = explicitRange
            ?? editorInteractionState.currentSelectionRange()
            ?? store.selectionRange(for: store.activeTabID)
        store.updateSelection(for: store.activeTabID, range: range)
        aiStore.submit(
            settings: settingsStore,
            tabID: store.activeTabID,
            fileName: store.activeTab.fileName,
            fullText: store.text,
            selectedRange: range
        )
    }

    private func optimizeCurrentMarkdown() {
        guard !isActiveFileLocked else { return }
        guard !aiStore.isRunning else { return }
        withAnimation(.easeOut(duration: 0.15)) {
            aiMode = .edit
        }
        aiStore.input = """
        请优化整篇 Markdown 文件：保留事实和原意，改善标题层级、段落结构、表达清晰度、列表组织和 Markdown 格式。不要添加不存在的信息。
        """
        submitAIEdit(selectedRange: NSRange(location: 0, length: (store.text as NSString).length))
    }

    private func startPracticeSession() {
        guard !chatStore.isRunning else { return }
        withAnimation(.easeOut(duration: 0.15)) {
            aiMode = .chat
        }
        chatStore.input = """
        请基于这篇 Markdown 笔记出一组学习练习题，包含：5 道快速回忆题、3 道理解应用题、1 道综合题，并在最后给出简洁答案。
        """
        submitChat()
    }

    private func acceptAIEdit() {
        guard !isActiveFileLocked else { return }
        guard let proposal = aiStore.proposal else { return }
        guard proposal.tabID == store.activeTabID,
              proposal.originalDocument == store.text else {
            aiStore.markProposalStale()
            return
        }
        guard let nextText = proposal.proposedDocument() else {
            aiStore.markProposalInvalid()
            return
        }

        let nextSelection = NSRange(
            location: proposal.range.location,
            length: proposal.replacementText.utf16.count
        )
        store.updateText(nextText)
        store.updateSelection(for: store.activeTabID, range: nextSelection)
        editorInteractionState.restoreSelection(nextSelection)
        editorInteractionState.requestLayoutRefresh()
        aiStore.acceptProposal()
    }

    private func submitChat() {
        chatStore.submit(
            settings: settingsStore,
            markdownContent: store.text,
            fileName: store.activeTab.fileName
        )
    }
}
struct MarkdownTopToolsView: View {
    @ObservedObject var store: NoteStore
    @ObservedObject var fileLockStore: FilePermissionLockStore
    let editorInteractionState: EditorInteractionState
    @State private var isShowingSearchResults = false
    @State private var isConfirmingTrash = false

    var body: some View {
        HStack(spacing: 8) {
            ActiveFileBadge(
                title: store.activeTab.title,
                detail: store.activeTab.filePath ?? store.activeTab.fileName,
                systemImage: "doc.text"
            )

            FilePermissionLockButton(
                lockStore: fileLockStore,
                fileURL: store.activeTab.fileURL
            )

            if let error = store.lastError {
                StoreErrorBadge(message: error)
            }
            if let error = fileLockStore.lastError {
                StoreErrorBadge(message: error)
            }

            ToolbarSearchField(
                placeholder: "md",
                query: $store.searchQuery,
                resultCount: store.filteredTabs.count,
                isShowingResults: $isShowingSearchResults
            ) {
                MarkdownSearchResultsPopover(
                    tabs: Array(store.filteredTabs.prefix(32)),
                    activeTabID: store.activeTabID
                ) { tab in
                    rememberCurrentSelection()
                    store.selectTab(tab.id)
                    store.searchQuery = ""
                    isShowingSearchResults = false
                }
            }

            TopToolbarButtonStrip {
                Button {
                    store.syncFromDisk()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(MarkdownToolbarButtonStyle())
                .help("Sync Markdown")

                Button {
                    rememberCurrentSelection()
                    store.addTab()
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(MarkdownToolbarButtonStyle())
                .help("New Markdown")

                Button {
                    isConfirmingTrash = true
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(MarkdownToolbarButtonStyle())
                .help("Move Markdown file to Trash")
            }
        }
        .confirmationDialog("Move Markdown file to Trash?", isPresented: $isConfirmingTrash) {
            Button("Move to Trash", role: .destructive) {
                store.moveActiveTabToTrash()
            }
        }
    }

    private func rememberCurrentSelection() {
        guard let range = editorInteractionState.currentSelectionRange() else { return }
        store.updateSelection(for: store.activeTabID, range: range)
    }
}
struct MarkdownWorkspaceView: View {
    @ObservedObject var store: NoteStore
    @ObservedObject var settingsStore: AppSettingsStore
    let imageStore: LocalImageStore
    @ObservedObject var markdownAIStore: MarkdownAIEditStore
    @ObservedObject var markdownAIChatStore: MarkdownAIChatStore
    @ObservedObject var fileLockStore: FilePermissionLockStore
    let editorInteractionState: EditorInteractionState
    @ObservedObject var directoryStore: WorkspaceDirectoryStore
    let size: CGSize

    var body: some View {
        MarkdownEditorPanel(
            store: store,
            settingsStore: settingsStore,
            imageStore: imageStore,
            aiStore: markdownAIStore,
            chatStore: markdownAIChatStore,
            fileLockStore: fileLockStore,
            editorInteractionState: editorInteractionState,
            size: size
        )
        .frame(width: size.width, height: size.height)
        .onAppear {
            useMarkdownWorkingDirectory()
        }
        .onChange(of: directoryStore.markdownWorkingDirectory) { _, _ in
            useMarkdownWorkingDirectory()
        }
    }

    private func useMarkdownWorkingDirectory() {
        let root = directoryStore.markdownWorkingDirectoryURL
        store.useMarkdownRoot(root)
        imageStore.useMarkdownRoot(root)
    }
}

struct MarkdownSearchResultsPopover: View {
    let tabs: [NoteTab]
    let activeTabID: UUID
    let onSelect: (NoteTab) -> Void

    var body: some View {
        SearchResultsContainer {
            if tabs.isEmpty {
                EmptySearchResultView()
            } else {
                ForEach(tabs) { tab in
                    Button {
                        onSelect(tab)
                    } label: {
                        SearchResultRow(
                            systemImage: tab.id == activeTabID ? "doc.text.fill" : "doc.text",
                            title: tab.title,
                            detail: tab.fileName
                        )
                    }
                    .buttonStyle(FilePillButtonStyle(isSelected: tab.id == activeTabID))
                    .help(tab.fileName)
                }
            }
        }
    }
}
enum MarkdownAIMode {
    case edit
    case chat
}

struct MarkdownAIChatView: View {
    @ObservedObject var chatStore: MarkdownAIChatStore

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if chatStore.messages.isEmpty {
                    Text("Ask anything about this note — quiz me, summarize, explain...")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.42))
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(10)
                } else {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(chatStore.messages) { message in
                            AIChatBubble(message: message)
                                .id(message.id)
                        }

                        if chatStore.isRunning {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.small)
                                    .scaleEffect(0.5)
                                    .frame(width: 12, height: 12)
                                Text("Thinking...")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.42))
                            }
                            .padding(.horizontal, 10)
                            .id("loading")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.vertical, 6)
                }
            }
            .onChange(of: chatStore.messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    if let last = chatStore.messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    } else if chatStore.isRunning {
                        proxy.scrollTo("loading", anchor: .bottom)
                    }
                }
            }
        }
        .background(Color(red: 0.035, green: 0.037, blue: 0.044))
    }
}

struct AIChatBubble: View {
    let message: AIChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            if message.role == .assistant {
                Image(systemName: "sparkles")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.purple.opacity(0.7))
                    .frame(width: 12, alignment: .top)
                    .padding(.top, 2)
            }

            Text(message.content)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(message.role == .user ? 0.88 : 0.72))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(message.role == .user
                              ? Color.white.opacity(0.06)
                              : Color.purple.opacity(0.08))
                )

            if message.role == .user {
                Image(systemName: "person.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 12, alignment: .top)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 10)
    }
}

struct MarkdownAIReviewView: View {
    @ObservedObject var aiStore: MarkdownAIEditStore

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: aiStore.proposal == nil ? "sparkles" : "doc.text.magnifyingglass")
                    .foregroundStyle(.white.opacity(0.58))
                    .frame(width: 16)

                Text(aiStore.statusText)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)

                Spacer(minLength: 0)

                if aiStore.isRunning {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.58)
                        .frame(width: 18, height: 18)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(Color(red: 0.04, green: 0.042, blue: 0.05))

            if let proposal = aiStore.proposal {
                HStack(spacing: 0) {
                    MarkdownAIComparisonColumn(
                        title: proposal.isInsertion ? "Before cursor" : "Before",
                        text: proposal.isInsertion ? "Insert at UTF-16 \(proposal.range.location)" : proposal.originalText
                    )

                    Rectangle()
                        .fill(.white.opacity(0.045))
                        .frame(width: 1)

                    MarkdownAIComparisonColumn(
                        title: proposal.isInsertion ? "Insert" : "After",
                        text: proposal.replacementText
                    )
                }
            } else {
                ScrollView {
                    Text(aiStore.statusText)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.56))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(10)
                }
            }
        }
        .background(Color(red: 0.035, green: 0.037, blue: 0.044))
    }
}

struct MarkdownAIComparisonColumn: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.42))
                .lineLimit(1)

            ScrollView {
                Text(text.isEmpty ? " " : text)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.76))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(10)
    }
}

struct MarkdownShortcutToolbar: View {
    let editorInteractionState: EditorInteractionState
    @ObservedObject var aiStore: MarkdownAIEditStore
    @ObservedObject var chatStore: MarkdownAIChatStore
    @Binding var aiMode: MarkdownAIMode
    let onSubmitAI: () -> Void
    let onSubmitChat: () -> Void
    let onAcceptAI: () -> Void
    let onRejectAI: () -> Void
    let onOptimizeMarkdown: () -> Void
    let onPracticeMarkdown: () -> Void
    let onOpenExternally: () -> Void
    let isReadOnly: Bool

    @State private var isConfirmingOptimization = false

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 8) {
                formattingControls
                    .frame(maxWidth: .infinity, alignment: .leading)

                MarkdownAIComposer(
                    aiStore: aiStore,
                    chatStore: chatStore,
                    aiMode: aiMode,
                    onSubmitAI: onSubmitAI,
                    onSubmitChat: onSubmitChat,
                    isReadOnly: isReadOnly
                )
                .frame(width: composerWidth(for: proxy.size.width), height: 26)

                rightControls
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 10)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .confirmationDialog("Optimize current Markdown file?", isPresented: $isConfirmingOptimization) {
            Button("Ask AI to Optimize") {
                onOptimizeMarkdown()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("AI will review the whole file and create an editable proposal before anything is applied.")
        }
    }

    private var formattingControls: some View {
        HStack(spacing: 4) {
            ForEach(MarkdownCommand.allCases) { command in
                Button {
                    editorInteractionState.applyMarkdownCommand(command)
                } label: {
                    MarkdownCommandLabel(command: command)
                        .frame(width: 26, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(MarkdownToolbarButtonStyle())
                .disabled(isReadOnly)
                .help(command.help)
            }

            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    aiMode = aiMode == .edit ? .chat : .edit
                }
            } label: {
                Image(systemName: aiMode == .edit ? "pencil.line" : "bubble.left.fill")
                    .frame(width: 26, height: 24)
            }
            .buttonStyle(MarkdownToolbarButtonStyle())
            .help(aiMode == .edit ? "Switch to Chat mode" : "Switch to Edit mode")
        }
    }

    private var rightControls: some View {
        HStack(spacing: 4) {
            if aiMode == .edit, aiStore.proposal != nil {
                Button(action: onAcceptAI) {
                    Image(systemName: "checkmark")
                        .frame(width: 26, height: 24)
                }
                .buttonStyle(MarkdownToolbarButtonStyle())
                .disabled(aiStore.isRunning || isReadOnly)
                .help("Apply AI edit")

                Button(action: onRejectAI) {
                    Image(systemName: "xmark")
                        .frame(width: 26, height: 24)
                }
                .buttonStyle(MarkdownToolbarButtonStyle())
                .disabled(aiStore.isRunning)
                .help("Reject AI edit")
            }

            if aiMode == .chat, !chatStore.messages.isEmpty {
                Button(action: chatStore.clear) {
                    Image(systemName: "trash")
                        .frame(width: 26, height: 24)
                }
                .buttonStyle(MarkdownToolbarButtonStyle())
                .disabled(chatStore.isRunning)
                .help("Clear chat")
            }

            TopToolbarButtonStrip {
                Button {
                    isConfirmingOptimization = true
                } label: {
                    Image(systemName: "wand.and.sparkles")
                        .frame(width: 26, height: 24)
                }
                .buttonStyle(MarkdownToolbarButtonStyle())
                .disabled(aiStore.isRunning || isReadOnly)
                .help("Optimize this Markdown file")

                Button(action: onPracticeMarkdown) {
                    Image(systemName: "graduationcap")
                        .frame(width: 26, height: 24)
                }
                .buttonStyle(MarkdownToolbarButtonStyle())
                .disabled(chatStore.isRunning)
                .help("Ask AI to create practice questions")

                Button(action: onOpenExternally) {
                    Image(systemName: "arrow.up.forward.square")
                        .frame(width: 26, height: 24)
                }
                .buttonStyle(MarkdownToolbarButtonStyle())
                .help("Open in default editor")
            }
        }
    }

    private func composerWidth(for toolbarWidth: CGFloat) -> CGFloat {
        min(max(toolbarWidth * 0.42, 320), 390)
    }
}

struct MarkdownAIComposer: View {
    @ObservedObject var aiStore: MarkdownAIEditStore
    @ObservedObject var chatStore: MarkdownAIChatStore
    let aiMode: MarkdownAIMode
    let onSubmitAI: () -> Void
    let onSubmitChat: () -> Void
    let isReadOnly: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: aiMode == .edit ? "sparkles" : "bubble.left")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.46))
                .frame(width: 14)

            TextField(
                aiMode == .edit ? "Ask AI to edit" : "Ask about this note...",
                text: aiMode == .edit ? $aiStore.input : $chatStore.input
            )
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.86))
                .disabled(aiMode == .edit ? (aiStore.isRunning || isReadOnly) : chatStore.isRunning)
                .onSubmit {
                    if aiMode == .edit {
                        if aiStore.canSubmit, !isReadOnly { onSubmitAI() }
                    } else {
                        if chatStore.canSubmit { onSubmitChat() }
                    }
                }

            Button(action: aiMode == .edit ? onSubmitAI : onSubmitChat) {
                Image(systemName: "arrow.up")
                    .frame(width: 24, height: 22)
            }
            .buttonStyle(MarkdownToolbarButtonStyle())
            .disabled(aiMode == .edit ? (!aiStore.canSubmit || isReadOnly) : !chatStore.canSubmit)
            .help(aiMode == .edit ? "Ask AI to edit" : "Send message")
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.white.opacity(0.045))
        )
    }
}

struct MarkdownCommandLabel: View {
    let command: MarkdownCommand

    var body: some View {
        switch command {
        case .bold:
            Image(systemName: "bold")
        case .italic:
            Image(systemName: "italic")
        case .strikethrough:
            Image(systemName: "strikethrough")
        case .inlineCode:
            Text("`")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
        case .link:
            Image(systemName: "link")
        case .quote:
            Image(systemName: "quote.opening")
        case .unorderedList:
            Image(systemName: "list.bullet")
        case .orderedList:
            Image(systemName: "list.number")
        case .todoList:
            Image(systemName: "checklist")
        }
    }
}
struct MarkdownNoteEditor: View {
    @ObservedObject var store: NoteStore
    let imageStore: LocalImageStore
    @ObservedObject var fileLockStore: FilePermissionLockStore
    let editorInteractionState: EditorInteractionState
    @State private var isWikiLinkActive = false
    @State private var pendingInlineReplacement: InlineReplacementRequest?
    private static let latexRenderer = SwiftMathBridge()

    var body: some View {
        NativeTextViewWrapper(
            text: Binding(
                get: { store.text },
                set: { store.updateText($0) }
            ),
            isWikiLinkActive: $isWikiLinkActive,
            pendingInlineReplacement: $pendingInlineReplacement,
            configuration: configuration,
            fontName: "SF Pro",
            fontSize: 15,
            documentId: store.activeTabID.uuidString,
            isEditable: !fileLockStore.isLocked(store.activeTab.fileURL),
            onPasteImage: savePastedImage,
            onLinkClick: openWikiLink
        )
        .background {
            EditorFocusBinder(state: editorInteractionState)
        }
    }

    private func openWikiLink(_ target: String) {
        if let range = editorInteractionState.currentSelectionRange() {
            store.updateSelection(for: store.activeTabID, range: range)
        }
        store.openWikiLinkTarget(target)
    }

    private func savePastedImage(_ pasteboard: NSPasteboard) -> String? {
        imageStore.saveImage(from: pasteboard)
    }

    private var configuration: MarkdownEditorConfiguration {
        let theme = MarkdownEditorTheme(
            bodyText: NSColor(white: 0.92, alpha: 1),
            mutedText: NSColor(white: 0.58, alpha: 1),
            disabledText: NSColor(white: 0.38, alpha: 1),
            headingMarker: NSColor(white: 0.44, alpha: 1),
            link: NSColor.systemBlue,
            incompleteLink: NSColor.systemBlue.withAlphaComponent(0.75),
            highlightBackground: NSColor.systemYellow.withAlphaComponent(0.32),
            findMatchHighlight: NSColor.systemYellow.withAlphaComponent(0.55),
            findCurrentMatchHighlight: NSColor.systemYellow,
            latexLightModeText: .white,
            latexDarkModeText: .white,
            strikethroughColor: NSColor(white: 0.62, alpha: 1)
        )

        let services = MarkdownEditorServices(
            wikiLinks: store.wikiLinkResolver,
            images: imageStore,
            latex: Self.latexRenderer
        )

        return MarkdownEditorConfiguration(
            theme: theme,
            services: services,
            lists: ListStyle(indentPerLevel: 18, extraLineHeight: 1),
            imageEmbed: ImageEmbedStyle(fallbackMaxWidth: 440, paragraphSpacing: 6, imageGap: 6),
            overscroll: OverscrollPolicy(percent: 0, maxPoints: 0, minPoints: 0),
            dragSelection: DragSelectionPolicy(movementThreshold: 8, edgeTriggerDistance: 8, scrollStepPerTick: 4, ticksPerSecond: 30),
            scrollers: .vertical,
            textInsets: TextInsets(horizontal: 12, vertical: 12)
        )
    }
}
