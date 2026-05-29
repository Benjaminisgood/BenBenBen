import AppKit
import MarkdownEngine
import MarkdownEngineLatex
import SwiftUI

private let leftPickerPopoverAnchor = UnitPoint(x: 1, y: 0.5)

@MainActor
final class DrawerState: ObservableObject {
    @Published var isExpanded = false
    @Published var revealProgress: CGFloat = 0
}

struct NotebookView: View {
    @ObservedObject var store: NoteStore
    @ObservedObject var settingsStore: AppSettingsStore
    let imageStore: LocalImageStore
    @ObservedObject var markdownAIStore: MarkdownAIEditStore
    @ObservedObject var markdownAIChatStore: MarkdownAIChatStore
    @ObservedObject var drawerState: DrawerState
    @ObservedObject var editorInteractionState: EditorInteractionState
    @ObservedObject var workbenchState: WorkbenchState
    @ObservedObject var pythonStore: CodeFileStore
    @ObservedObject var shellCommandStore: ShellCommandStore
    @ObservedObject var shellWorkspaceStore: ShellWorkspaceStore
    @ObservedObject var terminalTaskStore: TerminalTaskStore
    @ObservedObject var launchdJobStore: LaunchdJobStore
    @ObservedObject var launchdAIAgent: LaunchdAIAgent
    @ObservedObject var condaStore: CondaEnvironmentStore
    @ObservedObject var directoryStore: WorkspaceDirectoryStore
    @ObservedObject var terminalRunner: CommandRunner
    @ObservedObject var pythonRunner: PythonReplRunner
    let layout: NotchLayout
    let onOpenSettings: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            drawer
        }
        .frame(width: layout.expandedSize.width, height: layout.expandedSize.height, alignment: .top)
    }

    private var drawer: some View {
        ZStack(alignment: .top) {
            expandedContent
                .frame(width: layout.expandedSize.width, height: layout.expandedSize.height)
                .transaction { transaction in
                    transaction.animation = nil
                }
                .opacity(expandedContentOpacity)

            compactIcon
        }
        .frame(width: layout.expandedSize.width, height: layout.expandedSize.height, alignment: .top)
        .background(Color(red: 0.02, green: 0.02, blue: 0.025).opacity(0.98))
        .mask(alignment: .top) {
            TopAttachedRoundedShape(radius: cornerRadius)
                .frame(width: revealWidth, height: revealHeight)
        }
        .overlay(alignment: .top) {
            TopAttachedRoundedShape(radius: cornerRadius)
                .stroke(.white.opacity(0.09), lineWidth: 1)
                .frame(width: revealWidth, height: revealHeight)
        }
        .contentShape(Rectangle())
        .allowsHitTesting(drawerState.isExpanded)
    }

    private var expandedContent: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    WorkbenchModeControl(workbenchState: workbenchState)

                    Spacer()

                    WorkbenchTopToolsView(
                        workbenchState: workbenchState,
                        noteStore: store,
                        editorInteractionState: editorInteractionState,
                        pythonStore: pythonStore,
                        shellCommandStore: shellCommandStore,
                        shellWorkspaceStore: shellWorkspaceStore,
                        terminalTaskStore: terminalTaskStore,
                        launchdJobStore: launchdJobStore,
                        terminalRunner: terminalRunner,
                        pythonRunner: pythonRunner
                    )

                    Button(action: onOpenSettings) {
                        Image(systemName: "gearshape")
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(DarkIconButtonStyle())
                    .help("Settings")
                }
                .frame(height: toolbarHeight, alignment: .center)

                WorkbenchContentView(
                    workbenchState: workbenchState,
                    store: store,
                    settingsStore: settingsStore,
                    imageStore: imageStore,
                    markdownAIStore: markdownAIStore,
                    markdownAIChatStore: markdownAIChatStore,
                    editorInteractionState: editorInteractionState,
                    pythonStore: pythonStore,
                    shellCommandStore: shellCommandStore,
                    shellWorkspaceStore: shellWorkspaceStore,
                    terminalTaskStore: terminalTaskStore,
                    launchdJobStore: launchdJobStore,
                    launchdAIAgent: launchdAIAgent,
                    condaStore: condaStore,
                    directoryStore: directoryStore,
                    terminalRunner: terminalRunner,
                    pythonRunner: pythonRunner,
                    size: workspaceSize
                )
                .frame(width: workspaceSize.width, height: workspaceSize.height)
                .background(Color(red: 0.06, green: 0.06, blue: 0.07))
            }
        }
        .padding(.top, toolbarTopPadding)
        .padding(.horizontal, contentHorizontalPadding)
        .padding(.bottom, contentBottomPadding)
        .onAppear {
            editorInteractionState.onSelectionChange = { [weak store] range in
                guard let store else { return }
                store.updateSelection(for: store.activeTabID, range: range)
            }
            editorInteractionState.restoreSelection(store.selectionRange(for: store.activeTabID))
        }
        .onChange(of: store.activeTabID) { _, newTabID in
            editorInteractionState.restoreSelection(store.selectionRange(for: newTabID))
            editorInteractionState.requestLayoutRefresh(resetScroll: false)
        }
        .onChange(of: workbenchState.activeMode) { _, mode in
            guard mode == .markdown else { return }
            editorInteractionState.restoreSelection(store.selectionRange(for: store.activeTabID))
            editorInteractionState.requestLayoutRefresh(resetScroll: false)
        }
    }

    private var compactIcon: some View {
        Image(systemName: "note.text")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white.opacity(0.82))
            .frame(width: layout.compactSize.width, height: layout.compactSize.height)
            .opacity(1 - drawerState.revealProgress)
    }

    private var revealWidth: CGFloat {
        interpolate(from: layout.compactSize.width, to: layout.expandedSize.width)
    }

    private var revealHeight: CGFloat {
        interpolate(from: layout.compactSize.height, to: layout.expandedSize.height)
    }

    private var cornerRadius: CGFloat {
        interpolate(from: 12, to: 18)
    }

    private var expandedContentOpacity: CGFloat {
        let progress = drawerState.revealProgress
        return min(max((progress - 0.42) / 0.34, 0), 1)
    }

    private var workspaceSize: CGSize {
        CGSize(
            width: layout.expandedSize.width - contentHorizontalPadding * 2,
            height: layout.expandedSize.height - toolbarTopPadding - contentBottomPadding - toolbarHeight - contentSpacing
        )
    }

    private var toolbarTopPadding: CGFloat {
        layout.compactSize.height + 6
    }

    private var contentHorizontalPadding: CGFloat {
        18
    }

    private var contentBottomPadding: CGFloat {
        18
    }

    private var toolbarHeight: CGFloat {
        28
    }

    private var contentSpacing: CGFloat {
        10
    }

    private func interpolate(from start: CGFloat, to end: CGFloat) -> CGFloat {
        start + (end - start) * drawerState.revealProgress
    }
}

struct MarkdownEditorPanel: View {
    @ObservedObject var store: NoteStore
    @ObservedObject var settingsStore: AppSettingsStore
    let imageStore: LocalImageStore
    @ObservedObject var aiStore: MarkdownAIEditStore
    @ObservedObject var chatStore: MarkdownAIChatStore
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
                onSubmitAI: submitAIEdit,
                onSubmitChat: submitChat,
                onAcceptAI: acceptAIEdit,
                onRejectAI: aiStore.rejectProposal
            )
                .frame(width: size.width, height: toolbarHeight)
                .background(Color(red: 0.055, green: 0.055, blue: 0.065))
        }
    }

    private var editorHeight: CGFloat {
        max(size.height - outputHeight - toolbarHeight - separatorHeight * 2, 120)
    }

    private func submitAIEdit() {
        let range = editorInteractionState.currentSelectionRange()
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

    private func acceptAIEdit() {
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

struct WorkbenchModeControl: View {
    @ObservedObject var workbenchState: WorkbenchState

    var body: some View {
        HStack(spacing: 4) {
            ForEach(WorkbenchMode.allCases) { mode in
                let isSelected = mode == workbenchState.activeMode
                Button {
                    withAnimation(.easeOut(duration: 0.16)) {
                        workbenchState.select(mode)
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: mode.systemImage)
                            .frame(width: 15)
                        Text(mode.title)
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                    }
                    .frame(height: 26)
                    .padding(.horizontal, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(WorkbenchModeButtonStyle(isSelected: isSelected))
                .help(mode.title)
            }
        }
        .frame(height: 28)
        .padding(.horizontal, 3)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(0.045))
        )
    }
}

struct WorkbenchTopToolsView: View {
    @ObservedObject var workbenchState: WorkbenchState
    @ObservedObject var noteStore: NoteStore
    let editorInteractionState: EditorInteractionState
    @ObservedObject var pythonStore: CodeFileStore
    @ObservedObject var shellCommandStore: ShellCommandStore
    @ObservedObject var shellWorkspaceStore: ShellWorkspaceStore
    @ObservedObject var terminalTaskStore: TerminalTaskStore
    @ObservedObject var launchdJobStore: LaunchdJobStore
    @ObservedObject var terminalRunner: CommandRunner
    @ObservedObject var pythonRunner: PythonReplRunner

    var body: some View {
        Group {
            switch workbenchState.activeMode {
            case .markdown:
                MarkdownTopToolsView(
                    store: noteStore,
                    editorInteractionState: editorInteractionState
                )
            case .terminal:
                ShellTopToolsView(
                    workspaceStore: shellWorkspaceStore,
                    runner: terminalRunner
                )
            case .python:
                PythonTopToolsView(
                    codeStore: pythonStore,
                    runner: pythonRunner
                )
            case .tasks:
                LaunchdTopToolsView(
                    jobStore: launchdJobStore
                )
            }
        }
        .frame(maxWidth: 600, alignment: .trailing)
    }
}

struct MarkdownTopToolsView: View {
    @ObservedObject var store: NoteStore
    let editorInteractionState: EditorInteractionState
    @State private var isShowingSearchResults = false

    var body: some View {
        HStack(spacing: 8) {
            ActiveFileBadge(
                title: store.activeTab.title,
                detail: store.activeTab.filePath ?? store.activeTab.fileName,
                systemImage: "doc.text"
            )

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

            }
        }
    }

    private func rememberCurrentSelection() {
        guard let range = editorInteractionState.currentSelectionRange() else { return }
        store.updateSelection(for: store.activeTabID, range: range)
    }
}

struct PythonTopToolsView: View {
    @ObservedObject var codeStore: CodeFileStore
    @ObservedObject var runner: PythonReplRunner
    @State private var isShowingSearchResults = false

    var body: some View {
        HStack(spacing: 8) {
            ActiveFileBadge(
                title: codeStore.activeFile.fileName,
                detail: codeStore.activeFile.filePath,
                systemImage: "curlybraces.square"
            )

            ToolbarSearchField(
                placeholder: "py",
                query: $codeStore.searchQuery,
                resultCount: codeStore.filteredFiles.count,
                isShowingResults: $isShowingSearchResults
            ) {
                CodeSearchResultsPopover(
                    files: Array(codeStore.filteredFiles.prefix(32)),
                    activeFileID: codeStore.activeFileID
                ) { file in
                    codeStore.selectFile(file.id)
                    codeStore.searchQuery = ""
                    isShowingSearchResults = false
                }
            }

            TopToolbarButtonStrip {
                Button {
                    codeStore.syncFromDisk()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(MarkdownToolbarButtonStyle())
                .help("Sync Python")

                Button {
                    codeStore.addFile()
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(MarkdownToolbarButtonStyle())
                .help("New Python file")

                Button {
                    runner.clear()
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(MarkdownToolbarButtonStyle())
                .help("Clear Python output")
            }
        }
    }
}

struct ShellTopToolsView: View {
    @ObservedObject var workspaceStore: ShellWorkspaceStore
    @ObservedObject var runner: CommandRunner
    @State private var isShowingSearchResults = false

    var body: some View {
        HStack(spacing: 8) {
            ActiveFileBadge(
                title: workspaceStore.activeWorkspace.title,
                detail: workspaceStore.activeWorkspace.detail,
                systemImage: "dollarsign.square"
            )

            ToolbarSearchField(
                placeholder: "workspace",
                query: $workspaceStore.searchQuery,
                resultCount: workspaceStore.filteredWorkspaces.count,
                isShowingResults: $isShowingSearchResults
            ) {
                ShellWorkspaceSearchResultsPopover(
                    workspaces: Array(workspaceStore.filteredWorkspaces.prefix(32)),
                    activeWorkspaceID: workspaceStore.activeWorkspaceID
                ) { workspace in
                    workspaceStore.selectWorkspace(workspace.id)
                    syncRunnerStorage()
                    workspaceStore.searchQuery = ""
                    isShowingSearchResults = false
                }
            }

            TopToolbarButtonStrip {
                Button {
                    workspaceStore.syncFromDisk()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(MarkdownToolbarButtonStyle())
                .help("Sync Shell workspaces")

                Button {
                    workspaceStore.addWorkspace()
                    syncRunnerStorage()
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(MarkdownToolbarButtonStyle())
                .help("New Shell workspace")

                Button {
                    runner.clear()
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(MarkdownToolbarButtonStyle())
                .help("Clear Shell output")
            }
        }
        .onAppear(perform: syncRunnerStorage)
        .onChange(of: workspaceStore.activeWorkspaceID) { _, _ in
            syncRunnerStorage()
        }
    }

    private func syncRunnerStorage() {
        let workspace = workspaceStore.activeWorkspace
        runner.usePersistence(
            inputURL: workspace.inputURL,
            outputURL: workspace.transcriptURL
        )
    }
}

struct ShellWorkspaceSearchResultsPopover: View {
    let workspaces: [ShellWorkspace]
    let activeWorkspaceID: String
    let onSelect: (ShellWorkspace) -> Void

    var body: some View {
        SearchResultsContainer {
            if workspaces.isEmpty {
                EmptySearchResultView()
            } else {
                ForEach(workspaces) { workspace in
                    Button {
                        onSelect(workspace)
                    } label: {
                        SearchResultRow(
                            systemImage: "dollarsign.square",
                            title: workspace.title,
                            detail: workspace.detail
                        )
                    }
                    .buttonStyle(FilePillButtonStyle(isSelected: workspace.id == activeWorkspaceID))
                    .help(workspace.detail)
                }
            }
        }
    }
}

struct LaunchdTopToolsView: View {
    @ObservedObject var jobStore: LaunchdJobStore
    @State private var isShowingSearchResults = false

    var body: some View {
        HStack(spacing: 8) {
            ActiveFileBadge(
                title: jobStore.selectedJob?.title ?? "Launchd Jobs",
                detail: jobStore.selectedJob?.detail ?? "\(jobStore.jobs.count) plists",
                systemImage: "clock.arrow.2.circlepath"
            )

            ToolbarSearchField(
                placeholder: "plist",
                query: $jobStore.searchQuery,
                resultCount: jobStore.filteredJobs.count,
                isShowingResults: $isShowingSearchResults
            ) {
                LaunchdJobSearchResultsPopover(
                    jobs: Array(jobStore.filteredJobs.prefix(32)),
                    selectedJobID: jobStore.selectedJob?.id
                ) { job in
                    jobStore.select(job)
                    jobStore.searchQuery = ""
                    isShowingSearchResults = false
                }
            }

            TopToolbarButtonStrip {
                Button {
                    jobStore.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(MarkdownToolbarButtonStyle())
                .help("Refresh launchd jobs")

                Button {
                    let template = LaunchdJobStore.plistTemplate(label: "com.notchwow.new-task")
                    jobStore.createJob(filename: "com.notchwow.new-task", content: template)
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(MarkdownToolbarButtonStyle())
                .help("New plist")
            }
        }
    }
}

struct LaunchdJobSearchResultsPopover: View {
    let jobs: [LaunchdJob]
    let selectedJobID: String?
    let onSelect: (LaunchdJob) -> Void

    var body: some View {
        SearchResultsContainer {
            if jobs.isEmpty {
                EmptySearchResultView()
            } else {
                ForEach(jobs) { job in
                    Button {
                        onSelect(job)
                    } label: {
                        SearchResultRow(
                            systemImage: job.isLoaded ? "checkmark.circle.fill" : "circle",
                            title: job.label,
                            detail: job.detail
                        )
                    }
                    .buttonStyle(FilePillButtonStyle(isSelected: job.id == selectedJobID))
                    .help(job.detail)
                }
            }
        }
    }
}

struct LaunchdPane: View {
    @ObservedObject var jobStore: LaunchdJobStore
    @ObservedObject var aiAgent: LaunchdAIAgent
    @ObservedObject var settingsStore: AppSettingsStore
    let size: CGSize

    private let toolbarHeight: CGFloat = 34
    private let outputHeight: CGFloat = 132
    private let separatorHeight: CGFloat = 1

    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: $jobStore.editingContent)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
                .scrollContentBackground(.hidden)
                .background(Color(red: 0.045, green: 0.047, blue: 0.055))
                .frame(width: size.width, height: editorHeight)

            Rectangle()
                .fill(.white.opacity(0.045))
                .frame(width: size.width, height: separatorHeight)

            OutputView(output: launchdOutputText)
                .frame(width: size.width, height: outputHeight)

            Rectangle()
                .fill(.white.opacity(0.045))
                .frame(width: size.width, height: separatorHeight)

            LaunchdInputToolbar(
                jobStore: jobStore,
                aiAgent: aiAgent,
                settingsStore: settingsStore
            )
                .frame(width: size.width, height: toolbarHeight)
                .background(Color(red: 0.055, green: 0.055, blue: 0.065))
        }
        .frame(width: size.width, height: size.height)
        .onChange(of: aiAgent.generatedPlist) { _, plist in
            if let plist {
                jobStore.editingContent = plist
                jobStore.saveEditingContent()
            }
        }
    }

    private var editorHeight: CGFloat {
        max(size.height - outputHeight - toolbarHeight - separatorHeight * 2, 120)
    }

    private var launchdOutputText: String {
        if aiAgent.isRunning {
            return jobStore.outputLog.isEmpty
                ? "AI 生成中..."
                : jobStore.outputLog + "\n[...] AI 生成中..."
        }
        if !aiAgent.lastMessage.isEmpty && !jobStore.outputLog.contains(aiAgent.lastMessage) {
            return jobStore.outputLog.isEmpty
                ? aiAgent.lastMessage
                : jobStore.outputLog + "\n" + aiAgent.lastMessage
        }
        return jobStore.outputLog.isEmpty ? "Ready" : jobStore.outputLog
    }
}

struct LaunchdInputToolbar: View {
    @ObservedObject var jobStore: LaunchdJobStore
    @ObservedObject var aiAgent: LaunchdAIAgent
    @ObservedObject var settingsStore: AppSettingsStore
    @State private var isShowingLoadedPicker = false

    var body: some View {
        HStack(spacing: 8) {
            LaunchdLoadedJobPicker(
                jobStore: jobStore,
                isShowingPicker: $isShowingLoadedPicker
            )

            LaunchdAIInputField(aiAgent: aiAgent) {
                submitAI()
            }

            Button {
                submitAI()
            } label: {
                Image(systemName: "sparkles")
                    .frame(width: 26, height: 24)
            }
            .buttonStyle(MarkdownToolbarButtonStyle())
            .disabled(!aiAgent.canSubmit)
            .help("AI 生成 plist")

            Button {
                jobStore.saveEditingContent()
            } label: {
                Image(systemName: "square.and.arrow.down")
                    .frame(width: 26, height: 24)
            }
            .buttonStyle(MarkdownToolbarButtonStyle())
            .disabled(jobStore.selectedJob == nil)
            .help("Save plist")

            Button {
                guard let job = jobStore.selectedJob else { return }
                if job.isLoaded {
                    jobStore.unloadJob(job)
                } else {
                    jobStore.loadJob(job)
                }
            } label: {
                Image(systemName: jobStore.selectedJob?.isLoaded == true ? "stop.fill" : "play.fill")
                    .frame(width: 26, height: 24)
            }
            .buttonStyle(MarkdownToolbarButtonStyle())
            .disabled(jobStore.selectedJob == nil)
            .help(jobStore.selectedJob?.isLoaded == true ? "Unload (stop)" : "Load (start)")
        }
        .padding(.horizontal, 10)
    }

    private func submitAI() {
        let context = LaunchdAIContext(
            existingJobs: jobStore.jobs,
            availableShellScripts: listScripts(in: WorkspacePaths.shellWorkspaceScriptRoot, ext: "sh"),
            availablePythonScripts: listScripts(in: WorkspacePaths.pythonRoot, ext: "py"),
            selectedJob: jobStore.selectedJob,
            launchdPath: settingsStore.launchdPath
        )
        aiAgent.submit(settings: settingsStore, context: context)
    }

    private func listScripts(in directory: URL, ext: String) -> [String] {
        (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]))?.filter { $0.pathExtension == ext }.map { $0.lastPathComponent } ?? []
    }
}

struct LaunchdLoadedJobPicker: View {
    @ObservedObject var jobStore: LaunchdJobStore
    @Binding var isShowingPicker: Bool

    private var loadedCount: Int {
        jobStore.loadedJobs.count
    }

    var body: some View {
        Button {
            isShowingPicker.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "play.circle.fill")
                    .frame(width: 15)

                Text("\(loadedCount) active")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.38))
            }
            .foregroundStyle(.white.opacity(0.78))
            .frame(width: 108, height: 24, alignment: .leading)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(FilePillButtonStyle(isSelected: isShowingPicker))
        .help("Loaded jobs")
        .popover(
            isPresented: $isShowingPicker,
            attachmentAnchor: .point(UnitPoint(x: 1, y: 0.5)),
            arrowEdge: .top
        ) {
            LaunchdJobSearchResultsPopover(
                jobs: jobStore.loadedJobs,
                selectedJobID: jobStore.selectedJob?.id
            ) { job in
                jobStore.select(job)
                isShowingPicker = false
            }
        }
    }
}

struct LaunchdAIInputField: View {
    @ObservedObject var aiAgent: LaunchdAIAgent
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "sparkles")
                .foregroundStyle(.white.opacity(0.54))
                .frame(width: 15, height: 22)

            TextField("描述你要自动化的任务...", text: $aiAgent.input)
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(aiAgent.isRunning ? 0.38 : 0.9))
                .disabled(aiAgent.isRunning)
                .onSubmit(onSubmit)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .frame(height: 26, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.white.opacity(0.045))
        )
    }
}

struct TopToolbarButtonStrip<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 3) {
            content
        }
        .padding(.horizontal, 3)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.white.opacity(0.035))
        )
    }
}

struct ToolbarSearchField<Results: View>: View {
    let placeholder: String
    @Binding var query: String
    let resultCount: Int
    @Binding var isShowingResults: Bool
    @ViewBuilder let results: () -> Results

    @FocusState private var isFocused: Bool

    private var hasQuery: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.white.opacity(0.62))
                .frame(width: 16, height: 22)

            TextField(placeholder, text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.88))
                .focused($isFocused)
                .onChange(of: query) { _, nextQuery in
                    isShowingResults = !nextQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }

            if hasQuery {
                Text("\(resultCount)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.42))
                    .frame(minWidth: 22, alignment: .trailing)
            }
        }
        .padding(.horizontal, 8)
        .frame(width: 188, height: 28, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.white.opacity(isFocused ? 0.065 : 0.045))
        )
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .popover(isPresented: $isShowingResults, arrowEdge: .bottom) {
            results()
        }
    }
}

struct WorkbenchContentView: View {
    @ObservedObject var workbenchState: WorkbenchState
    @ObservedObject var store: NoteStore
    @ObservedObject var settingsStore: AppSettingsStore
    let imageStore: LocalImageStore
    @ObservedObject var markdownAIStore: MarkdownAIEditStore
    @ObservedObject var markdownAIChatStore: MarkdownAIChatStore
    let editorInteractionState: EditorInteractionState
    @ObservedObject var pythonStore: CodeFileStore
    @ObservedObject var shellCommandStore: ShellCommandStore
    @ObservedObject var shellWorkspaceStore: ShellWorkspaceStore
    @ObservedObject var terminalTaskStore: TerminalTaskStore
    @ObservedObject var launchdJobStore: LaunchdJobStore
    @ObservedObject var launchdAIAgent: LaunchdAIAgent
    @ObservedObject var condaStore: CondaEnvironmentStore
    @ObservedObject var directoryStore: WorkspaceDirectoryStore
    @ObservedObject var terminalRunner: CommandRunner
    @ObservedObject var pythonRunner: PythonReplRunner
    let size: CGSize

    var body: some View {
        Group {
            switch workbenchState.activeMode {
            case .markdown:
                MarkdownWorkspaceView(
                    store: store,
                    settingsStore: settingsStore,
                    imageStore: imageStore,
                    markdownAIStore: markdownAIStore,
                    markdownAIChatStore: markdownAIChatStore,
                    editorInteractionState: editorInteractionState,
                    directoryStore: directoryStore,
                    size: size
                )
            case .terminal:
                ShellPane(
                    commandStore: shellCommandStore,
                    workspaceStore: shellWorkspaceStore,
                    directoryStore: directoryStore,
                    runner: terminalRunner,
                    size: size
                )
            case .python:
                PythonWorkspaceView(
                    codeStore: pythonStore,
                    condaStore: condaStore,
                    directoryStore: directoryStore,
                    runner: pythonRunner,
                    size: size
                )
            case .tasks:
                LaunchdPane(
                    jobStore: launchdJobStore,
                    aiAgent: launchdAIAgent,
                    settingsStore: settingsStore,
                    size: size
                )
            }
        }
    }
}

struct MarkdownWorkspaceView: View {
    @ObservedObject var store: NoteStore
    @ObservedObject var settingsStore: AppSettingsStore
    let imageStore: LocalImageStore
    @ObservedObject var markdownAIStore: MarkdownAIEditStore
    @ObservedObject var markdownAIChatStore: MarkdownAIChatStore
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

struct MarkdownFileBar: View {
    @ObservedObject var store: NoteStore
    let editorInteractionState: EditorInteractionState
    @State private var isShowingSearchResults = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.white.opacity(0.46))
                .frame(width: 16)

            TextField("filename", text: $store.searchQuery)
                .textFieldStyle(.plain)
                .foregroundStyle(.white.opacity(0.88))
                .font(.system(size: 12))
                .onChange(of: store.searchQuery) { _, query in
                    isShowingSearchResults = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }

            if !store.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("\(store.filteredTabs.count)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.42))
                    .frame(minWidth: 22, alignment: .trailing)
            }

            ActiveFileBadge(
                title: store.activeTab.title,
                detail: store.activeTab.filePath ?? store.activeTab.fileName,
                systemImage: "doc.text"
            )

            Button {
                store.syncFromDisk()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 24, height: 22)
            }
            .buttonStyle(MarkdownToolbarButtonStyle())
            .help("Sync")

            Button {
                rememberCurrentSelection()
                store.addTab()
            } label: {
                Image(systemName: "plus")
                    .frame(width: 24, height: 22)
            }
            .buttonStyle(MarkdownToolbarButtonStyle())
            .help("New file")
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.white.opacity(0.045))
        )
        .popover(isPresented: $isShowingSearchResults, arrowEdge: .bottom) {
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
    }

    private func rememberCurrentSelection() {
        guard let range = editorInteractionState.currentSelectionRange() else { return }
        store.updateSelection(for: store.activeTabID, range: range)
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

struct PythonWorkspaceView: View {
    @ObservedObject var codeStore: CodeFileStore
    @ObservedObject var condaStore: CondaEnvironmentStore
    @ObservedObject var directoryStore: WorkspaceDirectoryStore
    @ObservedObject var runner: PythonReplRunner
    let size: CGSize

    private let outputHeight: CGFloat = 132
    private let toolbarHeight: CGFloat = 34
    private let separatorHeight: CGFloat = 1

    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: Binding(
                get: { codeStore.text },
                set: { codeStore.updateText($0) }
            ))
            .font(.system(size: 13, design: .monospaced))
            .foregroundStyle(.white.opacity(0.9))
            .scrollContentBackground(.hidden)
            .background(Color(red: 0.045, green: 0.047, blue: 0.055))
            .frame(width: size.width, height: editorHeight)

            Rectangle()
                .fill(.white.opacity(0.045))
                .frame(width: size.width, height: separatorHeight)

            OutputView(output: pythonOutputText)
                .frame(width: size.width, height: outputHeight)

            Rectangle()
                .fill(.white.opacity(0.045))
                .frame(width: size.width, height: separatorHeight)

            PythonCommandToolbar(
                codeStore: codeStore,
                condaStore: condaStore,
                runner: runner
            )
            .frame(width: size.width, height: toolbarHeight)
            .background(Color(red: 0.055, green: 0.055, blue: 0.065))
        }
        .onAppear {
            runner.useWorkingDirectory(directoryStore.pythonProjectDirectoryURL)
        }
        .onChange(of: directoryStore.pythonProjectDirectory) { _, _ in
            runner.useWorkingDirectory(directoryStore.pythonProjectDirectoryURL)
        }
    }

    private var editorHeight: CGFloat {
        max(size.height - outputHeight - toolbarHeight - separatorHeight * 2, 120)
    }

    private var pythonOutputText: String {
        guard runner.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return runner.output
        }

        let status = runner.isRunning ? "running" : "ready"
        return """
        Python \(status)
        env  \(condaStore.selectedEnvironmentName)
        file \(codeStore.activeFile.fileName)
        cwd  \(directoryStore.pythonProjectDirectoryURL.path)
        """
    }
}

struct PythonCommandToolbar: View {
    @ObservedObject var codeStore: CodeFileStore
    @ObservedObject var condaStore: CondaEnvironmentStore
    @ObservedObject var runner: PythonReplRunner
    @State private var isShowingEnvironmentPicker = false

    var body: some View {
        HStack(spacing: 8) {
            PythonEnvironmentPicker(
                condaStore: condaStore,
                isShowingEnvironmentPicker: $isShowingEnvironmentPicker
            )

            Text(runner.prompt)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.52))
                .frame(width: 24, alignment: .leading)

            TextField("Python", text: $runner.input)
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.84))
                .onSubmit(runInputCommand)

            Button {
                runActiveFile()
            } label: {
                Image(systemName: "play.fill")
                    .frame(width: 26, height: 24)
            }
            .buttonStyle(MarkdownToolbarButtonStyle())
            .disabled(runner.isRunning)
            .help("Run file in selected environment")

            Button {
                runInputCommand()
            } label: {
                Image(systemName: "arrow.turn.down.left")
                    .frame(width: 26, height: 24)
            }
            .buttonStyle(MarkdownToolbarButtonStyle())
            .disabled(runner.isRunning)
            .help("Run Python input")

            Button {
                runner.stop()
            } label: {
                Image(systemName: "stop.fill")
                    .frame(width: 26, height: 24)
            }
            .buttonStyle(MarkdownToolbarButtonStyle())
            .disabled(!runner.isRunning)
            .help("Stop")
        }
        .padding(.horizontal, 10)
    }

    private func runActiveFile() {
        runner.runFile(
            configuration: condaStore.pythonLaunchConfiguration(bridgeScript: PythonReplRunner.bridgeScript),
            filePath: codeStore.activeFile.filePath,
            displayName: condaStore.runPythonFileDisplayCommand(filePath: codeStore.activeFile.filePath)
        )
    }

    private func runInputCommand() {
        runner.run(
            configuration: condaStore.pythonLaunchConfiguration(bridgeScript: PythonReplRunner.bridgeScript)
        )
    }
}

struct PythonEnvironmentPicker: View {
    @ObservedObject var condaStore: CondaEnvironmentStore
    @Binding var isShowingEnvironmentPicker: Bool

    var body: some View {
        Button {
            isShowingEnvironmentPicker.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "shippingbox")
                    .frame(width: 15)

                Text(condaStore.selectedEnvironmentName)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.38))
            }
            .foregroundStyle(.white.opacity(0.78))
            .frame(width: 118, height: 24, alignment: .leading)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(FilePillButtonStyle(isSelected: isShowingEnvironmentPicker))
        .help("Python environment")
        .popover(
            isPresented: $isShowingEnvironmentPicker,
            attachmentAnchor: .point(leftPickerPopoverAnchor),
            arrowEdge: .top
        ) {
            SearchResultsContainer {
                if condaStore.environments.isEmpty {
                    EmptySearchResultView()
                } else {
                    ForEach(condaStore.environments) { environment in
                        Button {
                            condaStore.select(environment.name)
                            isShowingEnvironmentPicker = false
                        } label: {
                            SearchResultRow(
                                systemImage: environment.name == condaStore.selectedEnvironmentName ? "shippingbox.fill" : "shippingbox",
                                title: environment.displayName,
                                detail: environment.path
                            )
                        }
                        .buttonStyle(FilePillButtonStyle(isSelected: environment.name == condaStore.selectedEnvironmentName))
                        .help(environment.path)
                    }
                }

                Button {
                    condaStore.refresh()
                } label: {
                    SearchResultRow(
                        systemImage: "arrow.clockwise",
                        title: "Refresh",
                        detail: "Reload conda environments"
                    )
                }
                .buttonStyle(FilePillButtonStyle(isSelected: false))
            }
        }
    }
}

struct EnvironmentPicker: View {
    @ObservedObject var condaStore: CondaEnvironmentStore

    var body: some View {
        Menu {
            ForEach(condaStore.environments) { environment in
                Button {
                    condaStore.select(environment.name)
                } label: {
                    HStack {
                        Text(environment.displayName)
                        if environment.name == condaStore.selectedEnvironmentName {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }

            if condaStore.environments.isEmpty {
                Text(condaStore.lastError ?? "No conda environments")
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "shippingbox")
                    .frame(width: 14)
                Text(condaStore.selectedEnvironmentName)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.42))
            }
            .frame(height: 24)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(FilePillButtonStyle(isSelected: false))
        .help("Conda environment")
    }
}

struct CodeFileBar: View {
    @ObservedObject var codeStore: CodeFileStore
    @State private var isShowingSearchResults = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.white.opacity(0.46))
                .frame(width: 16)

            TextField("filename", text: $codeStore.searchQuery)
                .textFieldStyle(.plain)
                .foregroundStyle(.white.opacity(0.88))
                .font(.system(size: 12))
                .onChange(of: codeStore.searchQuery) { _, query in
                    isShowingSearchResults = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }

            if !codeStore.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("\(codeStore.filteredFiles.count)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.42))
                    .frame(minWidth: 22, alignment: .trailing)
            }

            ActiveFileBadge(
                title: codeStore.activeFile.fileName,
                detail: codeStore.activeFile.filePath,
                systemImage: "curlybraces.square"
            )

            Button {
                codeStore.syncFromDisk()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 24, height: 22)
            }
            .buttonStyle(MarkdownToolbarButtonStyle())
            .help("Sync")

            Button {
                codeStore.addFile()
            } label: {
                Image(systemName: "plus")
                    .frame(width: 24, height: 22)
            }
            .buttonStyle(MarkdownToolbarButtonStyle())
            .help("New file")
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.white.opacity(0.045))
        )
        .popover(isPresented: $isShowingSearchResults, arrowEdge: .bottom) {
            CodeSearchResultsPopover(
                files: Array(codeStore.filteredFiles.prefix(32)),
                activeFileID: codeStore.activeFileID
            ) { file in
                codeStore.selectFile(file.id)
                codeStore.searchQuery = ""
                isShowingSearchResults = false
            }
        }
    }
}

struct CodeSearchResultsPopover: View {
    let files: [CodeFile]
    let activeFileID: UUID
    let onSelect: (CodeFile) -> Void

    var body: some View {
        SearchResultsContainer {
            if files.isEmpty {
                EmptySearchResultView()
            } else {
                ForEach(files) { file in
                    Button {
                        onSelect(file)
                    } label: {
                        SearchResultRow(
                            systemImage: file.id == activeFileID ? "curlybraces.square.fill" : "curlybraces.square",
                            title: file.fileName,
                            detail: file.filePath
                        )
                    }
                    .buttonStyle(FilePillButtonStyle(isSelected: file.id == activeFileID))
                    .help(file.fileName)
                }
            }
        }
    }
}

struct ActiveFileBadge: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.48))
                .frame(width: 14)

            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)

            if !detail.isEmpty, detail != title {
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.36))
                    .lineLimit(1)
            }
        }
        .frame(minWidth: 0, maxWidth: 260, alignment: .leading)
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.white.opacity(0.035))
        )
        .help(detail)
    }
}

struct SearchResultsContainer<Content: View>: View {
    let content: Content
    let width: CGFloat
    let height: CGFloat

    init(width: CGFloat = 260, height: CGFloat = 260, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.width = width
        self.height = height
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                content
            }
            .padding(6)
        }
        .frame(width: width, height: height)
        .background(Color(red: 0.04, green: 0.042, blue: 0.05))
    }
}

struct SearchResultRow: View {
    let systemImage: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.white.opacity(0.58))
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(1)

                if !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.48))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "return")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.42))
        }
        .frame(minHeight: 34)
        .padding(.horizontal, 10)
        .contentShape(Rectangle())
    }
}

struct EmptySearchResultView: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.white.opacity(0.42))
                .frame(width: 16)

            Text("No results")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.48))

            Spacer(minLength: 0)
        }
        .frame(height: 34)
        .padding(.horizontal, 10)
    }
}

struct ShellPane: View {
    @ObservedObject var commandStore: ShellCommandStore
    @ObservedObject var workspaceStore: ShellWorkspaceStore
    @ObservedObject var directoryStore: WorkspaceDirectoryStore
    @ObservedObject var runner: CommandRunner
    let size: CGSize

    private let outputHeight: CGFloat = 132
    private let toolbarHeight: CGFloat = 34
    private let separatorHeight: CGFloat = 1

    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: Binding(
                get: { workspaceStore.scriptText },
                set: { workspaceStore.updateScriptText($0) }
            ))
            .font(.system(size: 13, design: .monospaced))
            .foregroundStyle(.white.opacity(0.9))
            .scrollContentBackground(.hidden)
            .background(Color(red: 0.045, green: 0.047, blue: 0.055))
            .frame(width: size.width, height: editorHeight)

            Rectangle()
                .fill(.white.opacity(0.045))
                .frame(width: size.width, height: separatorHeight)

            OutputView(output: runner.output)
                .frame(width: size.width, height: outputHeight)

            Rectangle()
                .fill(.white.opacity(0.045))
                .frame(width: size.width, height: separatorHeight)

            ShellInputToolbar(
                commandStore: commandStore,
                workspaceStore: workspaceStore,
                runner: runner
            )
                .frame(width: size.width, height: toolbarHeight)
                .background(Color(red: 0.055, green: 0.055, blue: 0.065))
        }
        .onAppear {
            runner.useWorkingDirectory(directoryStore.shellWorkingDirectoryURL)
        }
        .onChange(of: directoryStore.shellWorkingDirectory) { _, _ in
            runner.useWorkingDirectory(directoryStore.shellWorkingDirectoryURL)
        }
    }

    private var editorHeight: CGFloat {
        max(size.height - outputHeight - toolbarHeight - separatorHeight * 2, 120)
    }
}

struct ShellInputToolbar: View {
    @ObservedObject var commandStore: ShellCommandStore
    @ObservedObject var workspaceStore: ShellWorkspaceStore
    @ObservedObject var runner: CommandRunner
    @State private var isShowingCommandSuggestions = false
    @State private var isShowingToolkitPicker = false

    private var suggestedCommands: [ShellCommandItem] {
        Array(commandStore.filteredCommands(
            in: commandStore.selectedToolkit.name,
            matching: runner.input
        ).prefix(24))
    }

    var body: some View {
        HStack(spacing: 8) {
            ShellToolkitPicker(
                commandStore: commandStore,
                isShowingToolkitPicker: $isShowingToolkitPicker
            ) {
                updateSuggestionVisibility(for: runner.input)
            }

            Text("$")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.52))
                .frame(width: 18, alignment: .leading)

            TextField("Shell command", text: $runner.input)
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
                .onChange(of: runner.input) { _, nextInput in
                    updateSuggestionVisibility(for: nextInput)
                }
                .onSubmit {
                    runner.run(clearsInputOnRun: true)
                    isShowingCommandSuggestions = false
                }

            Button {
                runScript()
                isShowingCommandSuggestions = false
            } label: {
                Image(systemName: "play.fill")
                    .frame(width: 26, height: 24)
            }
            .buttonStyle(MarkdownToolbarButtonStyle())
            .disabled(runner.isRunning)
            .help("Run Shell script")

            Button {
                runner.run(clearsInputOnRun: true)
                isShowingCommandSuggestions = false
            } label: {
                Image(systemName: "arrow.turn.down.left")
                    .frame(width: 26, height: 24)
            }
            .buttonStyle(MarkdownToolbarButtonStyle())
            .disabled(runner.isRunning)
            .help("Run Shell input")

            Button {
                runner.stop()
            } label: {
                Image(systemName: "stop.fill")
                    .frame(width: 26, height: 24)
            }
            .buttonStyle(MarkdownToolbarButtonStyle())
            .disabled(!runner.isRunning)
            .help("Stop")
        }
        .padding(.horizontal, 10)
        .popover(isPresented: $isShowingCommandSuggestions, arrowEdge: .top) {
            ShellSearchResultsPopover(
                commands: suggestedCommands,
                activeCommand: runner.input,
                isRunning: runner.isRunning
            ) { item in
                runner.input = item.command
                runner.run(item.command, clearsInputOnRun: true)
                isShowingCommandSuggestions = false
            }
        }
    }

    private func runScript() {
        let workspace = workspaceStore.activeWorkspace
        workspaceStore.updateScriptText(workspaceStore.scriptText)
        runner.run(
            "/bin/zsh \(workspace.scriptURL.path.shellEscaped)",
            displayCommand: workspace.scriptURL.lastPathComponent,
            displayPrompt: "$ file>"
        )
    }

    private func updateSuggestionVisibility(for input: String) {
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        isShowingCommandSuggestions = !trimmedInput.isEmpty && !suggestedCommands.isEmpty && !runner.isRunning
    }
}

struct ShellToolkitPicker: View {
    @ObservedObject var commandStore: ShellCommandStore
    @Binding var isShowingToolkitPicker: Bool
    let onSelect: () -> Void

    var body: some View {
        Button {
            isShowingToolkitPicker.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: commandStore.selectedToolkit.systemImage)
                    .frame(width: 15)

                Text(commandStore.selectedToolkit.name)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.38))
            }
            .foregroundStyle(.white.opacity(0.78))
            .frame(width: 118, height: 24, alignment: .leading)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(FilePillButtonStyle(isSelected: isShowingToolkitPicker))
        .help("Shell toolkit")
        .popover(
            isPresented: $isShowingToolkitPicker,
            attachmentAnchor: .point(leftPickerPopoverAnchor),
            arrowEdge: .top
        ) {
            SearchResultsContainer {
                ForEach(commandStore.toolkits) { toolkit in
                    Button {
                        commandStore.selectToolkit(toolkit.name)
                        isShowingToolkitPicker = false
                        onSelect()
                    } label: {
                        SearchResultRow(
                            systemImage: toolkit.systemImage,
                            title: toolkit.name,
                            detail: "Benshell command toolkit"
                        )
                    }
                    .buttonStyle(FilePillButtonStyle(isSelected: toolkit.name == commandStore.selectedToolkit.name))
                }

                Button {
                    commandStore.refresh()
                    onSelect()
                } label: {
                    SearchResultRow(
                        systemImage: "arrow.clockwise",
                        title: "Refresh",
                        detail: "Reload Benshell commands"
                    )
                }
                .buttonStyle(FilePillButtonStyle(isSelected: false))
            }
        }
    }
}

struct ShellCommandCatalogView: View {
    @ObservedObject var commandStore: ShellCommandStore
    @ObservedObject var runner: CommandRunner
    @Binding var query: String
    @State private var isShowingSearchResults = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.white.opacity(0.46))
                .frame(width: 16)

            TextField("commands", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.88))
                .onChange(of: query) { _, nextQuery in
                    isShowingSearchResults = !nextQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }

            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("\(filteredCommands.count)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.42))
                    .frame(minWidth: 22, alignment: .trailing)
            }

            ActiveFileBadge(
                title: runner.input.isEmpty ? "Shell session" : runner.input,
                detail: runner.storagePath,
                systemImage: "dollarsign.square"
            )

            Button {
                commandStore.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 24, height: 22)
            }
            .buttonStyle(MarkdownToolbarButtonStyle())
            .help("Refresh commands")

            Button {
                NSWorkspace.shared.open(WorkspacePaths.shellRoot)
            } label: {
                Image(systemName: "folder")
                    .frame(width: 24, height: 22)
            }
            .buttonStyle(MarkdownToolbarButtonStyle())
            .help("Open Shell storage")
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.white.opacity(0.045))
        )
        .popover(isPresented: $isShowingSearchResults, arrowEdge: .bottom) {
            ShellSearchResultsPopover(
                commands: Array(filteredCommands.prefix(40)),
                activeCommand: runner.input,
                isRunning: runner.isRunning
            ) { item in
                runner.input = item.command
                runner.run(item.command, clearsInputOnRun: true)
                query = ""
                isShowingSearchResults = false
            }
        }
    }

    private var filteredCommands: [ShellCommandItem] {
        commandStore.filteredCommands(matching: query)
    }
}

struct ShellSearchResultsPopover: View {
    let commands: [ShellCommandItem]
    let activeCommand: String
    let isRunning: Bool
    let onSelect: (ShellCommandItem) -> Void

    var body: some View {
        SearchResultsContainer {
            if commands.isEmpty {
                EmptySearchResultView()
            } else {
                ForEach(commands) { item in
                    Button {
                        onSelect(item)
                    } label: {
                        SearchResultRow(
                            systemImage: item.systemImage,
                            title: item.command,
                            detail: item.summary.isEmpty ? item.group : "\(item.group)  \(item.summary)"
                        )
                    }
                    .buttonStyle(FilePillButtonStyle(isSelected: item.command == activeCommand))
                    .disabled(isRunning)
                    .help(item.command)
                }
            }
        }
    }
}

struct CommandPane: View {
    let title: String
    let systemImage: String
    @ObservedObject var runner: CommandRunner
    let size: CGSize

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(.white.opacity(0.54))
                    .frame(width: 16)

                TextField(title, text: $runner.input)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                    .onSubmit {
                        runner.run(clearsInputOnRun: true)
                    }

                Button {
                    runner.run(clearsInputOnRun: true)
                } label: {
                    Image(systemName: "play.fill")
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(MarkdownToolbarButtonStyle())
                .disabled(runner.isRunning)
                .help("Run")

                Button {
                    runner.stop()
                } label: {
                    Image(systemName: "stop.fill")
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(MarkdownToolbarButtonStyle())
                .disabled(!runner.isRunning)
                .help("Stop")

                Button {
                    runner.clear()
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(MarkdownToolbarButtonStyle())
                .help("Clear")
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(.white.opacity(0.045))
            )

            OutputView(output: runner.output)
                .frame(width: size.width, height: max(size.height - 38, 120))
        }
    }
}

struct OutputView: View {
    let output: String
    private let bottomID = "output-bottom"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(output.isEmpty ? " " : output)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.76))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)

                    Color.clear
                        .frame(height: 1)
                        .id(bottomID)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(10)
            }
            .background(Color(red: 0.035, green: 0.037, blue: 0.044))
            .onAppear {
                proxy.scrollTo(bottomID, anchor: .bottom)
            }
            .onChange(of: output) { _, _ in
                DispatchQueue.main.async {
                    proxy.scrollTo(bottomID, anchor: .bottom)
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

    var body: some View {
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
                .help(command.help)
            }

            Spacer(minLength: 0)

            if aiMode == .edit, aiStore.proposal != nil {
                Button(action: onAcceptAI) {
                    Image(systemName: "checkmark")
                        .frame(width: 26, height: 24)
                }
                .buttonStyle(MarkdownToolbarButtonStyle())
                .disabled(aiStore.isRunning)
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
                    .disabled(aiMode == .edit ? aiStore.isRunning : chatStore.isRunning)
                    .onSubmit {
                        if aiMode == .edit {
                            if aiStore.canSubmit { onSubmitAI() }
                        } else {
                            if chatStore.canSubmit { onSubmitChat() }
                        }
                    }

                Button(action: aiMode == .edit ? onSubmitAI : onSubmitChat) {
                    Image(systemName: "arrow.up")
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(MarkdownToolbarButtonStyle())
                .disabled(aiMode == .edit ? !aiStore.canSubmit : !chatStore.canSubmit)
                .help(aiMode == .edit ? "Ask AI to edit" : "Send message")
            }
            .padding(.leading, 8)
            .padding(.trailing, 4)
            .frame(width: 282, height: 26)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(.white.opacity(0.045))
            )
        }
        .padding(.horizontal, 10)
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

struct TabPagerControl: View {
    @ObservedObject var store: NoteStore
    let editorInteractionState: EditorInteractionState
    @Namespace private var tabAnimation

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Button {
                rememberCurrentSelection()
                withAnimation(tabSwitchAnimation) {
                    store.removeActiveTab()
                }
            } label: {
                Image(systemName: "minus")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(TabIconButtonStyle())
            .disabled(store.tabs.count <= 1)
            .help("Remove current tab")

            HStack(spacing: 6) {
                ForEach(store.tabs) { tab in
                    let isSelected = tab.id == store.activeTabID
                    Button {
                        rememberCurrentSelection()
                        withAnimation(tabSwitchAnimation) {
                            store.selectTab(tab.id)
                        }
                    } label: {
                        Capsule()
                            .fill(isSelected ? Color.white.opacity(0.82) : Color.white.opacity(0.34))
                            .frame(width: isSelected ? 20 : 6, height: 6)
                            .frame(width: 26, height: 24)
                            .contentShape(Rectangle())
                            .matchedGeometryEffect(id: tab.id, in: tabAnimation)
                            .animation(tabSwitchAnimation, value: isSelected)
                    }
                    .buttonStyle(TabDotButtonStyle(isSelected: isSelected))
                    .help("Switch tab")
                }
            }
            .frame(minWidth: 20, alignment: .center)
            .frame(height: 28, alignment: .center)

            Button {
                rememberCurrentSelection()
                withAnimation(tabSwitchAnimation) {
                    store.addTab()
                }
            } label: {
                Image(systemName: "plus")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(TabIconButtonStyle())
            .help("New tab")
        }
        .frame(height: 28, alignment: .center)
        .padding(.horizontal, 2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(0.045))
        )
    }

    private var tabSwitchAnimation: Animation {
        .spring(response: 0.26, dampingFraction: 0.82)
    }

    private func rememberCurrentSelection() {
        guard let range = editorInteractionState.currentSelectionRange() else { return }
        store.updateSelection(for: store.activeTabID, range: range)
    }
}

struct CompactNotchView: View {
    let layout: NotchLayout

    var body: some View {
        Image(systemName: "note.text")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white.opacity(0.82))
            .frame(width: layout.compactSize.width, height: layout.compactSize.height)
            .background(Color(red: 0.02, green: 0.02, blue: 0.025).opacity(0.98))
            .clipShape(TopAttachedRoundedShape(radius: 12))
            .overlay(
                TopAttachedRoundedShape(radius: 12)
                    .stroke(.white.opacity(0.09), lineWidth: 1)
            )
            .pointingHandCursor()
    }
}

struct MarkdownNoteEditor: View {
    @ObservedObject var store: NoteStore
    let imageStore: LocalImageStore
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
            isEditable: true,
            onPasteImage: savePastedImage
        )
        .background {
            EditorFocusBinder(state: editorInteractionState)
        }
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

struct TopAttachedRoundedShape: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = min(radius, rect.width / 2, rect.height / 2)
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - radius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()

        return path
    }
}

struct DarkIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RoundedHoverButtonBody(
            configuration: configuration,
            font: .system(size: 13, weight: .semibold),
            normalOpacity: 0.055,
            hoverOpacity: 0.085,
            pressedOpacity: 0.12,
            strokeOpacity: 0.06,
            foregroundOpacity: 0.76,
            pressedForegroundOpacity: 0.55
        )
    }
}

struct TabIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RoundedHoverButtonBody(
            configuration: configuration,
            font: .system(size: 11, weight: .bold),
            normalOpacity: 0,
            hoverOpacity: 0.065,
            pressedOpacity: 0.10,
            strokeOpacity: 0,
            foregroundOpacity: 0.72,
            pressedForegroundOpacity: 0.48
        )
    }
}

struct TabDotButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        RoundedHoverButtonBody(
            configuration: configuration,
            font: .system(size: 11, weight: .semibold),
            normalOpacity: isSelected ? 0.045 : 0,
            hoverOpacity: isSelected ? 0.075 : 0.055,
            pressedOpacity: isSelected ? 0.10 : 0.08,
            strokeOpacity: 0,
            foregroundOpacity: 0.72,
            pressedForegroundOpacity: 0.58
        )
    }
}

struct MarkdownToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RoundedHoverButtonBody(
            configuration: configuration,
            font: .system(size: 11, weight: .semibold),
            normalOpacity: 0,
            hoverOpacity: 0.065,
            pressedOpacity: 0.10,
            strokeOpacity: 0,
            foregroundOpacity: 0.66,
            hoverForegroundOpacity: 0.84,
            pressedForegroundOpacity: 0.54
        )
    }
}

struct WorkbenchModeButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        RoundedHoverButtonBody(
            configuration: configuration,
            font: nil,
            normalOpacity: isSelected ? 0.14 : 0,
            hoverOpacity: isSelected ? 0.18 : 0.07,
            pressedOpacity: 0.22,
            strokeOpacity: isSelected ? 0.10 : 0,
            foregroundOpacity: isSelected ? 0.92 : 0.58,
            hoverForegroundOpacity: 0.9,
            pressedForegroundOpacity: 0.72
        )
    }
}

struct FilePillButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        RoundedHoverButtonBody(
            configuration: configuration,
            font: nil,
            normalOpacity: isSelected ? 0.12 : 0.045,
            hoverOpacity: isSelected ? 0.16 : 0.08,
            pressedOpacity: 0.18,
            strokeOpacity: isSelected ? 0.10 : 0.04,
            foregroundOpacity: isSelected ? 0.9 : 0.68,
            hoverForegroundOpacity: 0.9,
            pressedForegroundOpacity: 0.68
        )
    }
}

private struct RoundedHoverButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let font: Font?
    let normalOpacity: CGFloat
    let hoverOpacity: CGFloat
    let pressedOpacity: CGFloat
    let strokeOpacity: CGFloat
    let foregroundOpacity: CGFloat
    let hoverForegroundOpacity: CGFloat
    let pressedForegroundOpacity: CGFloat

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    init(
        configuration: ButtonStyle.Configuration,
        font: Font?,
        normalOpacity: CGFloat,
        hoverOpacity: CGFloat,
        pressedOpacity: CGFloat,
        strokeOpacity: CGFloat,
        foregroundOpacity: CGFloat,
        hoverForegroundOpacity: CGFloat? = nil,
        pressedForegroundOpacity: CGFloat
    ) {
        self.configuration = configuration
        self.font = font
        self.normalOpacity = normalOpacity
        self.hoverOpacity = hoverOpacity
        self.pressedOpacity = pressedOpacity
        self.strokeOpacity = strokeOpacity
        self.foregroundOpacity = foregroundOpacity
        self.hoverForegroundOpacity = hoverForegroundOpacity ?? foregroundOpacity
        self.pressedForegroundOpacity = pressedForegroundOpacity
    }

    var body: some View {
        configuration.label
            .font(font)
            .foregroundStyle(.white.opacity(currentForegroundOpacity))
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(.white.opacity(currentBackgroundOpacity))
            )
            .animation(.easeOut(duration: 0.10), value: isHovering)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
            .onHover { hovering in
                guard isEnabled else { return }
                isHovering = hovering
            }
            .pointingHandCursor(isEnabled: isEnabled)
    }

    private var currentBackgroundOpacity: CGFloat {
        guard isEnabled else { return 0 }
        if configuration.isPressed {
            return pressedOpacity
        }
        return isHovering ? hoverOpacity : normalOpacity
    }

    private var currentForegroundOpacity: CGFloat {
        guard isEnabled else { return 0.22 }
        if configuration.isPressed {
            return pressedForegroundOpacity
        }
        return isHovering ? hoverForegroundOpacity : foregroundOpacity
    }
}

private extension View {
    func pointingHandCursor(isEnabled: Bool = true) -> some View {
        modifier(PointingHandCursorModifier(isEnabled: isEnabled))
    }
}

private struct PointingHandCursorModifier: ViewModifier {
    let isEnabled: Bool
    @State private var isCursorActive = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                if hovering, isEnabled, !isCursorActive {
                    NSCursor.pointingHand.push()
                    isCursorActive = true
                } else if (!hovering || !isEnabled), isCursorActive {
                    NSCursor.pop()
                    isCursorActive = false
                }
            }
            .onChange(of: isEnabled) { _, enabled in
                if !enabled, isCursorActive {
                    NSCursor.pop()
                    isCursorActive = false
                }
            }
            .onDisappear {
                if isCursorActive {
                    NSCursor.pop()
                    isCursorActive = false
                }
            }
    }
}
