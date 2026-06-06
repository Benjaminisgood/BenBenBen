import SwiftUI

private struct ScriptSearchResult: Identifiable {
    let id: String
    let kind: ScriptDocumentKind
    let title: String
    let detail: String
    let systemImage: String
}

private struct ScriptCommandLaunchContext {
    let command: String
    let workingDirectoryURL: URL
    let bootstrapURL: URL?
    let environment: [String: String]
}

struct ScriptsTopToolsView: View {
    @ObservedObject var scriptsState: ScriptsModuleState
    @ObservedObject var shellWorkspaceStore: ShellWorkspaceStore
    @ObservedObject var appleScriptStore: CodeFileStore
    @ObservedObject var commandStore: ShellCommandStore
    @ObservedObject var terminalRunner: CommandRunner
    @State private var isShowingSearchResults = false
    @State private var isConfirmingTrash = false

    var body: some View {
        HStack(spacing: 8) {
            ScriptKindPicker(scriptsState: scriptsState)

            ActiveFileBadge(
                title: activeTitle,
                detail: activeDetail,
                systemImage: scriptsState.activeKind.systemImage
            )

            if let error = activeError {
                StoreErrorBadge(message: error)
            }

            ToolbarSearchField(
                placeholder: "scripts",
                query: $scriptsState.scriptSearchQuery,
                resultCount: scriptSearchResults.count,
                isShowingResults: $isShowingSearchResults
            ) {
                ScriptsSearchResultsPopover(
                    results: Array(scriptSearchResults.prefix(36)),
                    activeKind: scriptsState.activeKind,
                    activeShellWorkspaceID: shellWorkspaceStore.activeWorkspaceID,
                    activeAppleScriptFileID: appleScriptStore.activeFileID
                ) { result in
                    selectSearchResult(result)
                    scriptsState.scriptSearchQuery = ""
                    isShowingSearchResults = false
                }
            }

            TopToolbarButtonStrip {
                Button {
                    syncActiveScriptsFromDisk()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(MarkdownToolbarButtonStyle())
                .help("Sync Scripts")

                Button {
                    addActiveScript()
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(MarkdownToolbarButtonStyle())
                .help("New Script")

                Button {
                    isConfirmingTrash = true
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(MarkdownToolbarButtonStyle())
                .help("Move Script to Trash")
            }
        }
        .confirmationDialog("Move script to Trash?", isPresented: $isConfirmingTrash) {
            Button("Move to Trash", role: .destructive) {
                moveActiveScriptToTrash()
            }
        }
        .onAppear {
            syncRunnerStorage()
        }
        .onChange(of: shellWorkspaceStore.activeWorkspaceID) { _, _ in
            syncRunnerStorage()
        }
    }

    private var activeTitle: String {
        switch scriptsState.activeKind {
        case .shell:
            return shellWorkspaceStore.activeWorkspace.scriptURL.lastPathComponent
        case .appleScript:
            return appleScriptStore.activeFile.fileName
        }
    }

    private var activeDetail: String {
        switch scriptsState.activeKind {
        case .shell:
            return shellWorkspaceStore.activeWorkspace.scriptURL.path
        case .appleScript:
            return appleScriptStore.activeFile.filePath
        }
    }

    private var activeError: String? {
        switch scriptsState.activeKind {
        case .shell:
            return shellWorkspaceStore.lastError
        case .appleScript:
            return appleScriptStore.lastError
        }
    }

    private var scriptSearchResults: [ScriptSearchResult] {
        let query = scriptsState.scriptSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }

        let shellResults = shellWorkspaceStore.workspaces
            .filter { workspace in
                workspace.title.localizedCaseInsensitiveContains(query)
                    || workspace.scriptURL.lastPathComponent.localizedCaseInsensitiveContains(query)
                    || workspace.scriptURL.path.localizedCaseInsensitiveContains(query)
            }
            .map { workspace in
                ScriptSearchResult(
                    id: workspace.id,
                    kind: .shell,
                    title: workspace.scriptURL.lastPathComponent,
                    detail: workspace.scriptURL.path,
                    systemImage: "dollarsign.square"
                )
            }

        let appleScriptResults = appleScriptStore.files
            .filter { file in
                file.fileName.localizedCaseInsensitiveContains(query)
                    || file.filePath.localizedCaseInsensitiveContains(query)
            }
            .map { file in
                ScriptSearchResult(
                    id: file.id.uuidString,
                    kind: .appleScript,
                    title: file.fileName,
                    detail: file.filePath,
                    systemImage: "command.square"
                )
            }

        return shellResults + appleScriptResults
    }

    private func selectSearchResult(_ result: ScriptSearchResult) {
        scriptsState.selectKind(result.kind)
        switch result.kind {
        case .shell:
            shellWorkspaceStore.selectWorkspace(result.id)
            syncRunnerStorage()
        case .appleScript:
            guard let id = UUID(uuidString: result.id) else { return }
            appleScriptStore.selectFile(id)
        }
    }

    private func syncActiveScriptsFromDisk() {
        switch scriptsState.activeKind {
        case .shell:
            shellWorkspaceStore.syncFromDisk()
            syncRunnerStorage()
        case .appleScript:
            appleScriptStore.syncFromDisk()
        }
        commandStore.refresh()
    }

    private func addActiveScript() {
        switch scriptsState.activeKind {
        case .shell:
            shellWorkspaceStore.addWorkspace()
            syncRunnerStorage()
        case .appleScript:
            appleScriptStore.addFile()
        }
        commandStore.refresh()
    }

    private func moveActiveScriptToTrash() {
        switch scriptsState.activeKind {
        case .shell:
            terminalRunner.stop()
            shellWorkspaceStore.moveActiveWorkspaceToTrash()
        case .appleScript:
            appleScriptStore.moveActiveFileToTrash()
        }
        commandStore.refresh()
    }

    private func syncRunnerStorage() {
        let workspace = shellWorkspaceStore.activeWorkspace
        terminalRunner.usePersistence(
            inputURL: workspace.inputURL,
            outputURL: workspace.transcriptURL
        )
    }
}

private struct ScriptKindPicker: View {
    @ObservedObject var scriptsState: ScriptsModuleState

    var body: some View {
        HStack(spacing: 3) {
            ForEach(ScriptDocumentKind.allCases) { kind in
                Button {
                    scriptsState.selectKind(kind)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: kind.systemImage)
                            .frame(width: 14)
                        Text(kind.shortTitle)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .lineLimit(1)
                    }
                    .frame(height: 22)
                    .padding(.horizontal, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(FilePillButtonStyle(isSelected: scriptsState.activeKind == kind))
                .help("Script language")
            }
        }
        .padding(.horizontal, 3)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.white.opacity(0.035))
        )
    }
}

private struct ScriptsSearchResultsPopover: View {
    let results: [ScriptSearchResult]
    let activeKind: ScriptDocumentKind
    let activeShellWorkspaceID: String
    let activeAppleScriptFileID: UUID
    let onSelect: (ScriptSearchResult) -> Void

    var body: some View {
        SearchResultsContainer {
            if results.isEmpty {
                EmptySearchResultView()
            } else {
                ForEach(results) { result in
                    Button {
                        onSelect(result)
                    } label: {
                        SearchResultRow(
                            systemImage: result.systemImage,
                            title: result.title,
                            detail: result.detail
                        )
                    }
                    .buttonStyle(FilePillButtonStyle(isSelected: isSelected(result)))
                    .help("Script file")
                }
            }
        }
    }

    private func isSelected(_ result: ScriptSearchResult) -> Bool {
        switch result.kind {
        case .shell:
            return activeKind == .shell && result.id == activeShellWorkspaceID
        case .appleScript:
            return activeKind == .appleScript && result.id == activeAppleScriptFileID.uuidString
        }
    }
}

struct ScriptsWorkspaceView: View {
    @ObservedObject var scriptsState: ScriptsModuleState
    @ObservedObject var commandStore: ShellCommandStore
    @ObservedObject var shellWorkspaceStore: ShellWorkspaceStore
    @ObservedObject var appleScriptStore: CodeFileStore
    @ObservedObject var directoryStore: WorkspaceDirectoryStore
    @ObservedObject var settingsStore: AppSettingsStore
    @ObservedObject var shellAIStore: ScriptAIEditStore
    @ObservedObject var appleScriptAIStore: ScriptAIEditStore
    @ObservedObject var terminalRunner: CommandRunner
    @State private var toolbarMode: ScriptToolbarMode = .run
    let size: CGSize

    private let outputHeight: CGFloat = 132
    private let toolbarHeight: CGFloat = 34
    private let separatorHeight: CGFloat = 1

    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: Binding(
                get: { activeScriptText },
                set: { nextText in updateActiveScriptText(nextText) }
            ))
            .font(.system(size: 13, design: .monospaced))
            .foregroundStyle(.white.opacity(0.9))
            .scrollContentBackground(.hidden)
            .background(Color(red: 0.045, green: 0.047, blue: 0.055))
            .frame(width: size.width, height: editorHeight)

            Rectangle()
                .fill(.white.opacity(0.045))
                .frame(width: size.width, height: separatorHeight)

            Group {
                if toolbarMode == .run {
                    ScriptsCommandPreviewView(
                        scriptsState: scriptsState,
                        commandStore: commandStore,
                        directoryStore: directoryStore,
                        activeFileName: activeFileName,
                        activeFilePath: activeFileURL.path,
                        historyPath: activeHistoryPath
                    )
                } else {
                    ScriptAIReviewView(aiStore: activeAIStore)
                }
            }
            .frame(width: size.width, height: outputHeight)

            Rectangle()
                .fill(.white.opacity(0.045))
                .frame(width: size.width, height: separatorHeight)

            ScriptsCommandToolbar(
                scriptsState: scriptsState,
                commandStore: commandStore,
                shellWorkspaceStore: shellWorkspaceStore,
                appleScriptStore: appleScriptStore,
                directoryStore: directoryStore,
                settingsStore: settingsStore,
                shellAIStore: shellAIStore,
                appleScriptAIStore: appleScriptAIStore,
                toolbarMode: $toolbarMode
            )
            .frame(width: size.width, height: toolbarHeight)
            .background(Color(red: 0.055, green: 0.055, blue: 0.065))
        }
        .frame(width: size.width, height: size.height)
        .onAppear(perform: syncScriptsIntegration)
        .onChange(of: directoryStore.shellWorkingDirectory) { _, _ in
            syncScriptsIntegration()
        }
        .onChange(of: directoryStore.benshellRootDirectory) { _, _ in
            syncScriptsIntegration()
        }
        .onChange(of: directoryStore.appleScriptDirectory) { _, _ in
            syncScriptsIntegration()
        }
        .onChange(of: scriptsState.activeKind) { _, _ in
            commandStore.refresh()
        }
    }

    private var editorHeight: CGFloat {
        max(size.height - outputHeight - toolbarHeight - separatorHeight * 2, 120)
    }

    private var activeScriptText: String {
        switch scriptsState.activeKind {
        case .shell:
            return shellWorkspaceStore.scriptText
        case .appleScript:
            return appleScriptStore.text
        }
    }

    private var activeFileName: String {
        switch scriptsState.activeKind {
        case .shell:
            return shellWorkspaceStore.activeWorkspace.scriptURL.lastPathComponent
        case .appleScript:
            return appleScriptStore.activeFile.fileName
        }
    }

    private var activeFileURL: URL {
        switch scriptsState.activeKind {
        case .shell:
            return shellWorkspaceStore.activeWorkspace.scriptURL
        case .appleScript:
            return appleScriptStore.activeFile.fileURL
        }
    }

    private var activeHistoryPath: String {
        switch scriptsState.activeKind {
        case .shell:
            return shellWorkspaceStore.activeWorkspace.transcriptURL.path
        case .appleScript:
            return WorkspacePaths.appleScriptOutputFile.path
        }
    }

    private var activeAIStore: ScriptAIEditStore {
        switch scriptsState.activeKind {
        case .shell:
            return shellAIStore
        case .appleScript:
            return appleScriptAIStore
        }
    }

    private func updateActiveScriptText(_ nextText: String) {
        switch scriptsState.activeKind {
        case .shell:
            shellWorkspaceStore.updateScriptText(nextText)
        case .appleScript:
            appleScriptStore.updateText(nextText)
        }
        commandStore.refresh()
    }

    private func syncScriptsIntegration() {
        terminalRunner.useWorkingDirectory(directoryStore.shellWorkingDirectoryURL)
        terminalRunner.useShellConfiguration(
            bootstrapURL: directoryStore.benshellInitScriptURL,
            environment: ["BENSHELL_HOME": directoryStore.benshellRootDirectoryURL.path]
        )
        commandStore.useBenshellRoot(directoryStore.benshellRootDirectoryURL)
    }
}

private struct ScriptsCommandPreviewView: View {
    @ObservedObject var scriptsState: ScriptsModuleState
    @ObservedObject var commandStore: ShellCommandStore
    @ObservedObject var directoryStore: WorkspaceDirectoryStore
    let activeFileName: String
    let activeFilePath: String
    let historyPath: String

    var body: some View {
        OutputView(output: previewText)
    }

    private var previewText: String {
        let toolkit = commandStore.selectedToolkit
        let candidates = commandStore.filteredCommands(
            in: toolkit.name,
            matching: scriptsState.commandSearchQuery
        )

        guard let command = scriptsState.selectedCommand(from: candidates) else {
            return """
            Scripts command launcher
            toolkit \(toolkit.name)
            active  \(activeFileName)
            file    \(activeFilePath)
            status  No commands found in selected toolkit
            """
        }

        let context = launchContext(for: command)
        let environmentText = context.environment.isEmpty
            ? "(none)"
            : context.environment
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: " ")
        let bootstrapText = context.bootstrapURL?.path ?? "(none)"
        let status = scriptsState.lastLaunchStatus ?? "ready"

        return """
        Scripts command launcher
        toolkit \(toolkit.name)
        command \(command.command)
        cwd     \(context.workingDirectoryURL.path)
        env     \(environmentText)
        source  \(bootstrapText)
        file    \(activeFileName)
        path    \(activeFilePath)
        history \(historyPath)
        status  \(status)
        """
    }

    private func launchContext(for item: ShellCommandItem) -> ScriptCommandLaunchContext {
        switch item.kind {
        case .benshell:
            return ScriptCommandLaunchContext(
                command: item.command,
                workingDirectoryURL: directoryStore.shellWorkingDirectoryURL,
                bootstrapURL: directoryStore.benshellInitScriptURL,
                environment: ["BENSHELL_HOME": directoryStore.benshellRootDirectoryURL.path]
            )
        case .shellScript:
            return ScriptCommandLaunchContext(
                command: item.command,
                workingDirectoryURL: directoryStore.shellWorkingDirectoryURL,
                bootstrapURL: nil,
                environment: ["KEYOTI_HOME": WorkspacePaths.root.path]
            )
        case .appleScript:
            return ScriptCommandLaunchContext(
                command: item.command,
                workingDirectoryURL: directoryStore.appleScriptDirectoryURL,
                bootstrapURL: nil,
                environment: [:]
            )
        }
    }
}

private struct ScriptsCommandToolbar: View {
    @ObservedObject var scriptsState: ScriptsModuleState
    @ObservedObject var commandStore: ShellCommandStore
    @ObservedObject var shellWorkspaceStore: ShellWorkspaceStore
    @ObservedObject var appleScriptStore: CodeFileStore
    @ObservedObject var directoryStore: WorkspaceDirectoryStore
    @ObservedObject var settingsStore: AppSettingsStore
    @ObservedObject var shellAIStore: ScriptAIEditStore
    @ObservedObject var appleScriptAIStore: ScriptAIEditStore
    @Binding var toolbarMode: ScriptToolbarMode
    @State private var isShowingToolkitPicker = false
    @State private var isShowingCommandPicker = false

    var body: some View {
        HStack(spacing: 8) {
            OpenCurrentFileInVSCodeButton {
                openActiveFileInVSCode()
            }

            ShellToolkitPicker(
                commandStore: commandStore,
                isShowingToolkitPicker: $isShowingToolkitPicker
            ) {
                scriptsState.lastLaunchStatus = nil
            }

            ScriptToolbarModeButton(mode: $toolbarMode)

            if toolbarMode == .run {
                Button {
                    isShowingCommandPicker.toggle()
                } label: {
                    Image(systemName: "list.bullet")
                        .frame(width: 26, height: 24)
                }
                .buttonStyle(MarkdownToolbarButtonStyle())
                .help("Show commands in selected toolkit")

                TextField("Find command", text: $scriptsState.commandSearchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.84))
                    .onChange(of: scriptsState.commandSearchQuery) { _, nextQuery in
                        isShowingCommandPicker = !nextQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    }
                    .onSubmit {
                        launchBestCommand()
                    }

                Button {
                    launchBestCommand()
                } label: {
                    Image(systemName: "play.fill")
                        .frame(width: 26, height: 24)
                }
                .buttonStyle(MarkdownToolbarButtonStyle())
                .disabled(bestCommand == nil)
                .help("Run selected command in Terminal")
            } else {
                ScriptAIEditorControls(
                    settingsStore: settingsStore,
                    aiStore: activeAIStore,
                    language: scriptsState.activeKind.scriptLanguage,
                    fileName: activeFileName,
                    script: activeScriptText,
                    onApply: { nextText in updateActiveScriptText(nextText) }
                )
            }
        }
        .padding(.horizontal, 10)
        .popover(isPresented: $isShowingCommandPicker, arrowEdge: .top) {
            ShellSearchResultsPopover(
                commands: Array(commandCandidates.prefix(36)),
                activeCommand: bestCommand?.command ?? "",
                isRunning: false
            ) { item in
                scriptsState.selectCommand(item)
                launchCommand(item)
                isShowingCommandPicker = false
            }
        }
    }

    private var commandCandidates: [ShellCommandItem] {
        commandStore.filteredCommands(
            in: commandStore.selectedToolkit.name,
            matching: scriptsState.commandSearchQuery
        )
    }

    private var bestCommand: ShellCommandItem? {
        scriptsState.selectedCommand(from: commandCandidates)
    }

    private var activeAIStore: ScriptAIEditStore {
        switch scriptsState.activeKind {
        case .shell:
            return shellAIStore
        case .appleScript:
            return appleScriptAIStore
        }
    }

    private var activeFileName: String {
        switch scriptsState.activeKind {
        case .shell:
            return shellWorkspaceStore.activeWorkspace.scriptURL.lastPathComponent
        case .appleScript:
            return appleScriptStore.activeFile.fileName
        }
    }

    private var activeScriptText: String {
        switch scriptsState.activeKind {
        case .shell:
            return shellWorkspaceStore.scriptText
        case .appleScript:
            return appleScriptStore.text
        }
    }

    private var activeFileURL: URL {
        switch scriptsState.activeKind {
        case .shell:
            return shellWorkspaceStore.activeWorkspace.scriptURL
        case .appleScript:
            return appleScriptStore.activeFile.fileURL
        }
    }

    private func updateActiveScriptText(_ nextText: String) {
        switch scriptsState.activeKind {
        case .shell:
            shellWorkspaceStore.updateScriptText(nextText)
        case .appleScript:
            appleScriptStore.updateText(nextText)
        }
        commandStore.refresh()
    }

    private func openActiveFileInVSCode() {
        persistActiveScript()
        directoryStore.openFileInVSCode(activeFileURL)
    }

    private func persistActiveScript() {
        switch scriptsState.activeKind {
        case .shell:
            shellWorkspaceStore.updateScriptText(shellWorkspaceStore.scriptText)
        case .appleScript:
            appleScriptStore.persistActiveFile()
        }
        commandStore.refresh()
    }

    private func launchBestCommand() {
        guard let bestCommand else { return }
        scriptsState.selectCommand(bestCommand)
        launchCommand(bestCommand)
    }

    private func launchCommand(_ item: ShellCommandItem) {
        let context = launchContext(for: item)
        let didLaunch = TerminalAppBridge.run(
            command: context.command,
            workingDirectory: context.workingDirectoryURL.path,
            bootstrapURL: context.bootstrapURL,
            environment: context.environment
        )
        scriptsState.lastLaunchStatus = didLaunch
            ? "launched in Terminal"
            : "Terminal launch failed"
    }

    private func launchContext(for item: ShellCommandItem) -> ScriptCommandLaunchContext {
        switch item.kind {
        case .benshell:
            return ScriptCommandLaunchContext(
                command: item.command,
                workingDirectoryURL: directoryStore.shellWorkingDirectoryURL,
                bootstrapURL: directoryStore.benshellInitScriptURL,
                environment: ["BENSHELL_HOME": directoryStore.benshellRootDirectoryURL.path]
            )
        case .shellScript:
            return ScriptCommandLaunchContext(
                command: item.command,
                workingDirectoryURL: directoryStore.shellWorkingDirectoryURL,
                bootstrapURL: nil,
                environment: ["KEYOTI_HOME": WorkspacePaths.root.path]
            )
        case .appleScript:
            return ScriptCommandLaunchContext(
                command: item.command,
                workingDirectoryURL: directoryStore.appleScriptDirectoryURL,
                bootstrapURL: nil,
                environment: [:]
            )
        }
    }
}
