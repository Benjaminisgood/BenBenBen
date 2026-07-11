import AppKit
import MarkdownEngine
import MarkdownEngineLatex
import SwiftUI

struct ShellTopToolsView: View {
    @ObservedObject var workspaceStore: ShellWorkspaceStore
    @ObservedObject var runner: CommandRunner
    @State private var isShowingSearchResults = false
    @State private var isConfirmingTrash = false

    var body: some View {
        HStack(spacing: 8) {
            ActiveFileBadge(
                title: workspaceStore.activeWorkspace.title,
                detail: workspaceStore.activeWorkspace.detail,
                systemImage: "dollarsign.square"
            )

            if let error = workspaceStore.lastError {
                StoreErrorBadge(message: error)
            }

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
                    isConfirmingTrash = true
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(MarkdownToolbarButtonStyle())
                .help("Move Shell workspace to Trash")
            }
        }
        .confirmationDialog("Move Shell workspace to Trash?", isPresented: $isConfirmingTrash) {
            Button("Move to Trash", role: .destructive) {
                runner.stop()
                workspaceStore.moveActiveWorkspaceToTrash()
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
struct ShellPane: View {
    @ObservedObject var commandStore: ShellCommandStore
    @ObservedObject var workspaceStore: ShellWorkspaceStore
    @ObservedObject var directoryStore: WorkspaceDirectoryStore
    @ObservedObject var settingsStore: AppSettingsStore
    @ObservedObject var aiStore: ScriptAIEditStore
    @ObservedObject var runner: CommandRunner
    @State private var toolbarMode: ScriptToolbarMode = .run
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

            Group {
                if toolbarMode == .run {
                    OutputView(output: shellOutputText)
                } else {
                    ScriptAIReviewView(aiStore: aiStore)
                }
            }
                .frame(width: size.width, height: outputHeight)

            Rectangle()
                .fill(.white.opacity(0.045))
                .frame(width: size.width, height: separatorHeight)

            ShellInputToolbar(
                commandStore: commandStore,
                workspaceStore: workspaceStore,
                settingsStore: settingsStore,
                aiStore: aiStore,
                toolbarMode: $toolbarMode,
                runner: runner
            )
                .frame(width: size.width, height: toolbarHeight)
                .background(Color(red: 0.055, green: 0.055, blue: 0.065))
        }
        .onAppear {
            syncShellIntegration()
        }
        .onChange(of: directoryStore.shellWorkingDirectory) { _, _ in
            syncShellIntegration()
        }
        .onChange(of: directoryStore.benshellRootDirectory) { _, _ in
            syncShellIntegration()
        }
    }

    private var editorHeight: CGFloat {
        max(size.height - outputHeight - toolbarHeight - separatorHeight * 2, 120)
    }

    private var shellOutputText: String {
        guard runner.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return runner.output
        }

        let status = runner.isRunning ? "running" : "ready"
        return """
        Shell \(status)
        workspace \(workspaceStore.activeWorkspace.title)
        cwd       \(directoryStore.shellWorkingDirectoryURL.path)
        """
    }

    private func syncShellIntegration() {
        runner.useWorkingDirectory(directoryStore.shellWorkingDirectoryURL)
        runner.useShellConfiguration(
            bootstrapURL: directoryStore.benshellInitScriptURL,
            environment: ["BENSHELL_HOME": directoryStore.benshellRootDirectoryURL.path]
        )
        commandStore.useBenshellRoot(directoryStore.benshellRootDirectoryURL)
    }
}

struct ShellInputToolbar: View {
    @ObservedObject var commandStore: ShellCommandStore
    @ObservedObject var workspaceStore: ShellWorkspaceStore
    @ObservedObject var settingsStore: AppSettingsStore
    @ObservedObject var aiStore: ScriptAIEditStore
    @Binding var toolbarMode: ScriptToolbarMode
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

            ScriptToolbarModeButton(mode: $toolbarMode)

            if toolbarMode == .run {
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

                Button {
                    runner.clear()
                } label: {
                    Image(systemName: "clear")
                        .frame(width: 26, height: 24)
                }
                .buttonStyle(MarkdownToolbarButtonStyle())
                .help("Clear Shell output")
            } else {
                ScriptAIEditorControls(
                    settingsStore: settingsStore,
                    aiStore: aiStore,
                    language: .shell,
                    fileName: workspaceStore.activeWorkspace.scriptURL.lastPathComponent,
                    script: workspaceStore.scriptText,
                    onApply: workspaceStore.updateScriptText,
                    isReadOnly: false
                )
            }
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
        .help("Scripts toolkit")
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
                            detail: "Scripts command toolkit"
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
