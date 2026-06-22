import AppKit
import MarkdownEngine
import MarkdownEngineLatex
import SwiftUI

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
    @ObservedObject var fileLockStore: FilePermissionLockStore
    @ObservedObject var drawerState: DrawerState
    @ObservedObject var editorInteractionState: EditorInteractionState
    @ObservedObject var workbenchState: WorkbenchState
    @ObservedObject var scriptsState: ScriptsModuleState
    @ObservedObject var pythonStore: CodeFileStore
    @ObservedObject var appleScriptStore: CodeFileStore
    @ObservedObject var shellCommandStore: ShellCommandStore
    @ObservedObject var shellWorkspaceStore: ShellWorkspaceStore
    @ObservedObject var launchdJobStore: LaunchdJobStore
    @ObservedObject var launchdAIAgent: LaunchdAIAgent
    @ObservedObject var shellAIStore: ScriptAIEditStore
    @ObservedObject var pythonAIStore: ScriptAIEditStore
    @ObservedObject var appleScriptAIStore: ScriptAIEditStore
    @ObservedObject var condaStore: CondaEnvironmentStore
    @ObservedObject var directoryStore: WorkspaceDirectoryStore
    @ObservedObject var terminalRunner: CommandRunner
    @ObservedObject var pythonRunner: PythonReplRunner
    @ObservedObject var appleScriptRunner: CommandRunner
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
                        scriptsState: scriptsState,
                        noteStore: store,
                        fileLockStore: fileLockStore,
                        editorInteractionState: editorInteractionState,
                        pythonStore: pythonStore,
                        appleScriptStore: appleScriptStore,
                        shellCommandStore: shellCommandStore,
                        shellWorkspaceStore: shellWorkspaceStore,
                        launchdJobStore: launchdJobStore,
                        terminalRunner: terminalRunner,
                        pythonRunner: pythonRunner,
                        appleScriptRunner: appleScriptRunner
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
                    scriptsState: scriptsState,
                    store: store,
                    settingsStore: settingsStore,
                    imageStore: imageStore,
                    markdownAIStore: markdownAIStore,
                    markdownAIChatStore: markdownAIChatStore,
                    fileLockStore: fileLockStore,
                    editorInteractionState: editorInteractionState,
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
    @ObservedObject var scriptsState: ScriptsModuleState
    @ObservedObject var noteStore: NoteStore
    @ObservedObject var fileLockStore: FilePermissionLockStore
    let editorInteractionState: EditorInteractionState
    @ObservedObject var pythonStore: CodeFileStore
    @ObservedObject var appleScriptStore: CodeFileStore
    @ObservedObject var shellCommandStore: ShellCommandStore
    @ObservedObject var shellWorkspaceStore: ShellWorkspaceStore
    @ObservedObject var launchdJobStore: LaunchdJobStore
    @ObservedObject var terminalRunner: CommandRunner
    @ObservedObject var pythonRunner: PythonReplRunner
    @ObservedObject var appleScriptRunner: CommandRunner

    var body: some View {
        Group {
            switch workbenchState.activeMode {
            case .markdown:
                MarkdownTopToolsView(
                    store: noteStore,
                    fileLockStore: fileLockStore,
                    editorInteractionState: editorInteractionState
                )
            case .scripts:
                ScriptsTopToolsView(
                    scriptsState: scriptsState,
                    shellWorkspaceStore: shellWorkspaceStore,
                    appleScriptStore: appleScriptStore,
                    fileLockStore: fileLockStore,
                    commandStore: shellCommandStore,
                    terminalRunner: terminalRunner
                )
            case .python:
                PythonTopToolsView(
                    codeStore: pythonStore,
                    fileLockStore: fileLockStore,
                    runner: pythonRunner
                )
            case .tasks:
                LaunchdTopToolsView(
                    jobStore: launchdJobStore,
                    fileLockStore: fileLockStore
                )
            }
        }
        .frame(maxWidth: 600, alignment: .trailing)
    }
}
struct WorkbenchContentView: View {
    @ObservedObject var workbenchState: WorkbenchState
    @ObservedObject var scriptsState: ScriptsModuleState
    @ObservedObject var store: NoteStore
    @ObservedObject var settingsStore: AppSettingsStore
    let imageStore: LocalImageStore
    @ObservedObject var markdownAIStore: MarkdownAIEditStore
    @ObservedObject var markdownAIChatStore: MarkdownAIChatStore
    @ObservedObject var fileLockStore: FilePermissionLockStore
    let editorInteractionState: EditorInteractionState
    @ObservedObject var pythonStore: CodeFileStore
    @ObservedObject var appleScriptStore: CodeFileStore
    @ObservedObject var shellCommandStore: ShellCommandStore
    @ObservedObject var shellWorkspaceStore: ShellWorkspaceStore
    @ObservedObject var launchdJobStore: LaunchdJobStore
    @ObservedObject var launchdAIAgent: LaunchdAIAgent
    @ObservedObject var shellAIStore: ScriptAIEditStore
    @ObservedObject var pythonAIStore: ScriptAIEditStore
    @ObservedObject var appleScriptAIStore: ScriptAIEditStore
    @ObservedObject var condaStore: CondaEnvironmentStore
    @ObservedObject var directoryStore: WorkspaceDirectoryStore
    @ObservedObject var terminalRunner: CommandRunner
    @ObservedObject var pythonRunner: PythonReplRunner
    @ObservedObject var appleScriptRunner: CommandRunner
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
                    fileLockStore: fileLockStore,
                    editorInteractionState: editorInteractionState,
                    directoryStore: directoryStore,
                    size: size
                )
            case .scripts:
                ScriptsWorkspaceView(
                    scriptsState: scriptsState,
                    commandStore: shellCommandStore,
                    shellWorkspaceStore: shellWorkspaceStore,
                    fileLockStore: fileLockStore,
                    appleScriptStore: appleScriptStore,
                    directoryStore: directoryStore,
                    settingsStore: settingsStore,
                    shellAIStore: shellAIStore,
                    appleScriptAIStore: appleScriptAIStore,
                    terminalRunner: terminalRunner,
                    size: size
                )
            case .python:
                PythonWorkspaceView(
                    codeStore: pythonStore,
                    fileLockStore: fileLockStore,
                    condaStore: condaStore,
                    directoryStore: directoryStore,
                    settingsStore: settingsStore,
                    aiStore: pythonAIStore,
                    runner: pythonRunner,
                    size: size
                )
            case .tasks:
                LaunchdPane(
                    jobStore: launchdJobStore,
                    fileLockStore: fileLockStore,
                    aiAgent: launchdAIAgent,
                    settingsStore: settingsStore,
                    directoryStore: directoryStore,
                    size: size
                )
            }
        }
    }
}
