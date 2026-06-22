import AppKit
import MarkdownEngine
import MarkdownEngineLatex
import SwiftUI

struct PythonTopToolsView: View {
    @ObservedObject var codeStore: CodeFileStore
    @ObservedObject var fileLockStore: FilePermissionLockStore
    @ObservedObject var runner: PythonReplRunner
    @State private var isShowingSearchResults = false
    @State private var isConfirmingTrash = false

    var body: some View {
        HStack(spacing: 8) {
            ActiveFileBadge(
                title: codeStore.activeFile.fileName,
                detail: codeStore.activeFile.filePath,
                systemImage: "curlybraces.square"
            )

            FilePermissionLockButton(
                lockStore: fileLockStore,
                fileURL: codeStore.activeFile.fileURL
            )

            if let error = codeStore.lastError {
                StoreErrorBadge(message: error)
            }
            if let error = fileLockStore.lastError {
                StoreErrorBadge(message: error)
            }

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
                    isConfirmingTrash = true
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(MarkdownToolbarButtonStyle())
                .help("Move Python file to Trash")
            }
        }
        .confirmationDialog("Move Python file to Trash?", isPresented: $isConfirmingTrash) {
            Button("Move to Trash", role: .destructive) {
                codeStore.moveActiveFileToTrash()
            }
        }
    }
}
struct PythonWorkspaceView: View {
    @ObservedObject var codeStore: CodeFileStore
    @ObservedObject var fileLockStore: FilePermissionLockStore
    @ObservedObject var condaStore: CondaEnvironmentStore
    @ObservedObject var directoryStore: WorkspaceDirectoryStore
    @ObservedObject var settingsStore: AppSettingsStore
    @ObservedObject var aiStore: ScriptAIEditStore
    @ObservedObject var runner: PythonReplRunner
    @State private var toolbarMode: ScriptToolbarMode = .run
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
            .disabled(fileLockStore.isLocked(codeStore.activeFile.fileURL))
            .frame(width: size.width, height: editorHeight)

            Rectangle()
                .fill(.white.opacity(0.045))
                .frame(width: size.width, height: separatorHeight)

            Group {
                if toolbarMode == .run {
                    OutputView(output: pythonOutputText)
                } else {
                    ScriptAIReviewView(aiStore: aiStore)
                }
            }
                .frame(width: size.width, height: outputHeight)

            Rectangle()
                .fill(.white.opacity(0.045))
                .frame(width: size.width, height: separatorHeight)

            PythonCommandToolbar(
                codeStore: codeStore,
                fileLockStore: fileLockStore,
                condaStore: condaStore,
                directoryStore: directoryStore,
                settingsStore: settingsStore,
                aiStore: aiStore,
                toolbarMode: $toolbarMode,
                runner: runner
            )
            .frame(width: size.width, height: toolbarHeight)
            .background(Color(red: 0.055, green: 0.055, blue: 0.065))
        }
        .onAppear {
            syncPythonIntegration()
        }
        .onChange(of: directoryStore.pythonProjectDirectory) { _, _ in
            syncPythonIntegration()
        }
        .onChange(of: directoryStore.condaRootDirectory) { _, _ in
            syncPythonIntegration()
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

    private func syncPythonIntegration() {
        runner.useWorkingDirectory(directoryStore.pythonProjectDirectoryURL)
        condaStore.useCondaRoot(directoryStore.condaRootDirectoryURL)
    }
}

struct PythonCommandToolbar: View {
    @ObservedObject var codeStore: CodeFileStore
    @ObservedObject var fileLockStore: FilePermissionLockStore
    @ObservedObject var condaStore: CondaEnvironmentStore
    @ObservedObject var directoryStore: WorkspaceDirectoryStore
    @ObservedObject var settingsStore: AppSettingsStore
    @ObservedObject var aiStore: ScriptAIEditStore
    @Binding var toolbarMode: ScriptToolbarMode
    @ObservedObject var runner: PythonReplRunner
    @State private var isShowingEnvironmentPicker = false

    var body: some View {
        HStack(spacing: 8) {
            OpenCurrentFileInVSCodeButton {
                codeStore.persistActiveFile()
                directoryStore.openFileInVSCode(codeStore.activeFile.fileURL)
            }

            PythonEnvironmentPicker(
                condaStore: condaStore,
                isShowingEnvironmentPicker: $isShowingEnvironmentPicker
            )

            ScriptToolbarModeButton(mode: $toolbarMode)

            if toolbarMode == .run {
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

                Button {
                    runner.clear()
                } label: {
                    Image(systemName: "clear")
                        .frame(width: 26, height: 24)
                }
                .buttonStyle(MarkdownToolbarButtonStyle())
                .help("Clear Python output")
            } else {
                ScriptAIEditorControls(
                    settingsStore: settingsStore,
                    aiStore: aiStore,
                    language: .python,
                    fileName: codeStore.activeFile.fileName,
                    script: codeStore.text,
                    onApply: codeStore.updateText,
                    isReadOnly: fileLockStore.isLocked(codeStore.activeFile.fileURL)
                )
            }
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

// MARK: - AppleScript
