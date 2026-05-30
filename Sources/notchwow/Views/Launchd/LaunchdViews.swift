import AppKit
import MarkdownEngine
import MarkdownEngineLatex
import SwiftUI

struct LaunchdTopToolsView: View {
    @ObservedObject var jobStore: LaunchdJobStore
    @State private var isShowingSearchResults = false
    @State private var isConfirmingTrash = false

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

                Button {
                    isConfirmingTrash = true
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(MarkdownToolbarButtonStyle())
                .disabled(jobStore.selectedJob == nil)
                .help("Move plist to Trash")
            }
        }
        .confirmationDialog("Move launchd plist to Trash?", isPresented: $isConfirmingTrash) {
            Button("Move to Trash", role: .destructive) {
                guard let job = jobStore.selectedJob else { return }
                jobStore.moveJobToTrash(job)
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
    @ObservedObject var directoryStore: WorkspaceDirectoryStore
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
                settingsStore: settingsStore,
                directoryStore: directoryStore
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
    @ObservedObject var directoryStore: WorkspaceDirectoryStore
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

            Button {
                jobStore.clearOutputLog()
            } label: {
                Image(systemName: "clear")
                    .frame(width: 26, height: 24)
            }
            .buttonStyle(MarkdownToolbarButtonStyle())
            .help("Clear Jobs output")
        }
        .padding(.horizontal, 10)
    }

    private func submitAI() {
        let context = LaunchdAIContext(
            existingJobs: jobStore.jobs,
            availableShellScripts: listScripts(in: WorkspacePaths.shellWorkspaceScriptRoot, ext: "sh"),
            availablePythonScripts: listScripts(in: WorkspacePaths.pythonRoot, ext: "py"),
            availableAppleScripts: listScripts(in: WorkspacePaths.appleScriptRoot, ext: "applescript"),
            selectedJob: jobStore.selectedJob,
            launchdPath: settingsStore.launchdPath,
            pythonExecutablePath: directoryStore.condaPythonExecutableURL.path
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
