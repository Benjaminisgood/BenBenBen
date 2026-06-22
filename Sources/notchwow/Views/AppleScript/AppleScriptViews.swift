import AppKit
import MarkdownEngine
import MarkdownEngineLatex
import SwiftUI

enum AppleScriptCommand {
    static func runFile(_ filePath: String) -> String {
        "/usr/bin/osacompile -o /dev/null \(filePath.shellEscaped) && /usr/bin/osascript \(filePath.shellEscaped)"
    }
}

struct AppleScriptTopToolsView: View {
    @ObservedObject var codeStore: CodeFileStore
    @ObservedObject var fileLockStore: FilePermissionLockStore
    @ObservedObject var runner: CommandRunner
    @State private var isShowingSearchResults = false
    @State private var isConfirmingTrash = false

    var body: some View {
        HStack(spacing: 8) {
            ActiveFileBadge(
                title: codeStore.activeFile.fileName,
                detail: codeStore.activeFile.filePath,
                systemImage: "command.square"
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
                placeholder: "as",
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
                .help("Sync AppleScript")

                Button {
                    codeStore.addFile()
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(MarkdownToolbarButtonStyle())
                .help("New AppleScript file")

                Button {
                    isConfirmingTrash = true
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(MarkdownToolbarButtonStyle())
                .help("Move AppleScript file to Trash")
            }
        }
        .confirmationDialog("Move AppleScript file to Trash?", isPresented: $isConfirmingTrash) {
            Button("Move to Trash", role: .destructive) {
                codeStore.moveActiveFileToTrash()
            }
        }
    }
}

struct AppleScriptWorkspaceView: View {
    @ObservedObject var codeStore: CodeFileStore
    @ObservedObject var fileLockStore: FilePermissionLockStore
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
                    OutputView(output: appleScriptOutputText)
                } else {
                    ScriptAIReviewView(aiStore: aiStore)
                }
            }
                .frame(width: size.width, height: outputHeight)

            Rectangle()
                .fill(.white.opacity(0.045))
                .frame(width: size.width, height: separatorHeight)

            AppleScriptCommandToolbar(
                codeStore: codeStore,
                fileLockStore: fileLockStore,
                settingsStore: settingsStore,
                aiStore: aiStore,
                toolbarMode: $toolbarMode,
                runner: runner
            )
            .frame(width: size.width, height: toolbarHeight)
            .background(Color(red: 0.055, green: 0.055, blue: 0.065))
        }
        .frame(width: size.width, height: size.height)
        .onAppear {
            runner.useWorkingDirectory(directoryStore.appleScriptDirectoryURL)
        }
        .onChange(of: directoryStore.appleScriptDirectory) { _, _ in
            runner.useWorkingDirectory(directoryStore.appleScriptDirectoryURL)
        }
    }

    private var editorHeight: CGFloat {
        max(size.height - outputHeight - toolbarHeight - separatorHeight * 2, 120)
    }

    private var appleScriptOutputText: String {
        guard runner.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return runner.output
        }

        let status = runner.isRunning ? "running" : "ready"
        return """
        AppleScript \(status)
        file \(codeStore.activeFile.fileName)
        cwd  \(directoryStore.appleScriptDirectoryURL.path)
        run  syntax check, then execute
        """
    }
}

struct AppleScriptCommandToolbar: View {
    @ObservedObject var codeStore: CodeFileStore
    @ObservedObject var fileLockStore: FilePermissionLockStore
    @ObservedObject var settingsStore: AppSettingsStore
    @ObservedObject var aiStore: ScriptAIEditStore
    @Binding var toolbarMode: ScriptToolbarMode
    @ObservedObject var runner: CommandRunner

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "command.square")
                .foregroundStyle(.white.opacity(0.54))
                .frame(width: 15, height: 22)

            ScriptToolbarModeButton(mode: $toolbarMode)

            if toolbarMode == .run {
                Text("▶")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.52))
                    .frame(width: 16, alignment: .leading)

                TextField("osascript -e ...", text: $runner.input)
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
                .help("Run file with osascript")

                Button {
                    runInputCommand()
                } label: {
                    Image(systemName: "arrow.turn.down.left")
                        .frame(width: 26, height: 24)
                }
                .buttonStyle(MarkdownToolbarButtonStyle())
                .disabled(runner.isRunning)
                .help("Run AppleScript input")

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
                .help("Clear AppleScript output")
            } else {
                ScriptAIEditorControls(
                    settingsStore: settingsStore,
                    aiStore: aiStore,
                    language: .appleScript,
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
        codeStore.persistActiveFile()
        let filePath = codeStore.activeFile.filePath
        runner.run(
            AppleScriptCommand.runFile(filePath),
            displayCommand: "osascript \(codeStore.activeFile.fileName)",
            displayPrompt: "▶",
            clearsInputOnRun: false,
            showsSuccessfulExit: true,
            showsFailedExit: true
        )
    }

    private func runInputCommand() {
        let command = runner.input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }
        runner.run(
            "/usr/bin/osascript -e \(command.shellEscaped)",
            displayPrompt: "▶",
            clearsInputOnRun: true,
            showsSuccessfulExit: true,
            showsFailedExit: true
        )
    }
}
