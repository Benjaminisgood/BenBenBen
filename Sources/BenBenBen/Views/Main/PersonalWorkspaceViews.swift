import AppKit
import SwiftUI

enum PersonalTaskListMode {
    case today
    case inbox

    var title: String {
        switch self {
        case .today: return "Today"
        case .inbox: return "Inbox"
        }
    }

    var systemImage: String {
        switch self {
        case .today: return "sun.max"
        case .inbox: return "tray"
        }
    }
}

struct PersonalTasksView: View {
    let mode: PersonalTaskListMode
    @ObservedObject var store: PersonalWorkspaceStore

    @State private var isCapturing = false
    @State private var taskPendingCompletion: PersonalTaskOccurrence?

    var body: some View {
        Group {
            if store.isRefreshing && store.tasks.isEmpty {
                ProgressView("Reading your workspace…")
            } else if filteredTasks.isEmpty {
                ContentUnavailableView(
                    mode.title,
                    systemImage: mode.systemImage,
                    description: Text(emptyDescription)
                )
            } else {
                List(filteredTasks) { task in
                    PersonalTaskRow(task: task) {
                        taskPendingCompletion = task
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle(mode.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isCapturing = true
                } label: {
                    Label("Capture task", systemImage: "plus")
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await store.refresh(forceReindex: true) }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(store.isRefreshing)
            }
        }
        .sheet(isPresented: $isCapturing) {
            TaskCaptureSheet(store: store)
        }
        .sheet(item: $taskPendingCompletion) { task in
            TaskCompletionApprovalSheet(task: task) {
                Task { await store.complete(task) }
                taskPendingCompletion = nil
            } onCancel: {
                taskPendingCompletion = nil
            }
        }
        .overlay(alignment: .bottom) {
            if let error = store.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.red, in: .capsule)
                    .padding()
            }
        }
    }

    private var filteredTasks: [PersonalTaskOccurrence] {
        store.tasks.filter { task in
            guard !task.isCompleted else { return false }
            switch mode {
            case .today:
                guard let dueDate = task.dueDate else { return false }
                let tomorrow = Calendar.current.startOfDay(for: Date()).addingTimeInterval(86_400)
                return dueDate < tomorrow
            case .inbox:
                return task.sourceURL.standardizedFileURL == store.registry.inboxURL.standardizedFileURL
            }
        }
    }

    private var emptyDescription: String {
        switch mode {
        case .today: return "No due or overdue Markdown tasks."
        case .inbox: return "Capture a thought and BenBenBen will append it to ~/keyoti/mds/Inbox.md."
        }
    }
}

private struct PersonalTaskRow: View {
    let task: PersonalTaskOccurrence
    let requestCompletion: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: requestCompletion) {
                Image(systemName: "circle")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .help("Review the Markdown diff before completing")

            VStack(alignment: .leading, spacing: 7) {
                Text(task.title.isEmpty ? task.rawLine : task.title)
                    .font(.body.weight(.medium))

                HStack(spacing: 8) {
                    if let due = task.dueDateText {
                        Label(due, systemImage: "calendar")
                    }
                    ForEach(task.tags, id: \.self) { tag in
                        Text("#\(tag.rawValue)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Button {
                    NSWorkspace.shared.open(task.sourceURL)
                } label: {
                    Text("\(task.sourceURL.lastPathComponent):\(task.lineNumber)")
                        .font(.caption.monospaced())
                }
                .buttonStyle(.link)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }
}

private struct TaskCompletionApprovalSheet: View {
    let task: PersonalTaskOccurrence
    let onApprove: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Review file change", systemImage: "doc.text.magnifyingglass")
                .font(.title2.bold())

            Text("BenBenBen will change one line in \(task.sourcePath). A content hash is checked again before writing.")
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            VStack(alignment: .leading, spacing: 8) {
                DiffLine(prefix: "−", text: task.rawLine, color: .red)
                DiffLine(prefix: "+", text: completedLine, color: .green)
            }
            .padding(12)
            .background(.black.opacity(0.18), in: .rect(cornerRadius: 12))

            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Approve change", action: onApprove)
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 620)
    }

    private var completedLine: String {
        switch task.sourceSyntax {
        case .checkbox:
            return task.rawLine.replacingOccurrences(of: #"\[ \]"#, with: "[x]", options: .regularExpression)
        case .directive:
            return task.rawLine.replacingOccurrences(
                of: #"^([\t ]*)(?:TODO:|TODO：|todo:|待完成:|note：|NOTE：|注意：)[\t ]*"#,
                with: "$1- [x] ",
                options: .regularExpression
            )
        }
    }
}

private struct DiffLine: View {
    let prefix: String
    let text: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(prefix)
                .foregroundStyle(color)
            Text(text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.callout.monospaced())
    }
}

private struct TaskCaptureSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: PersonalWorkspaceStore

    @State private var title = ""
    @State private var hasDueDate = false
    @State private var dueDate = Date()
    @State private var tags: Set<PersonalTaskTag> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Capture to Inbox")
                .font(.title2.bold())

            TextField("What should Ben remember?", text: $title, axis: .vertical)
                .textFieldStyle(.roundedBorder)

            Toggle("Add due date", isOn: $hasDueDate)
            if hasDueDate {
                DatePicker("Due", selection: $dueDate, displayedComponents: .date)
            }

            HStack {
                ForEach(PersonalTaskTag.allCases, id: \.self) { tag in
                    Toggle("#\(tag.rawValue)", isOn: binding(for: tag))
                        .toggleStyle(.button)
                }
            }

            GroupBox("Markdown preview") {
                Text(preview)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            }

            Text(store.registry.inboxURL.path)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Append to Inbox") {
                    let draft = PersonalTaskDraft(
                        title: title,
                        dueDate: hasDueDate ? dueDate : nil,
                        tags: Array(tags)
                    )
                    Task {
                        if await store.capture(draft) != nil {
                            dismiss()
                        }
                    }
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    private var preview: String {
        var components = ["- [ ] \(title.trimmingCharacters(in: .whitespacesAndNewlines))"]
        if hasDueDate {
            components.append("📅 \(dueDate.formatted(.iso8601.year().month().day()))")
        }
        components.append(contentsOf: tags.sorted { $0.rawValue < $1.rawValue }.map { "#\($0.rawValue)" })
        return components.joined(separator: " ")
    }

    private func binding(for tag: PersonalTaskTag) -> Binding<Bool> {
        Binding(
            get: { tags.contains(tag) },
            set: { enabled in
                if enabled { tags.insert(tag) } else { tags.remove(tag) }
            }
        )
    }
}

struct PersonalSearchResultsView: View {
    @ObservedObject var store: PersonalWorkspaceStore

    var body: some View {
        Group {
            if store.searchResults.isEmpty {
                ContentUnavailableView.search(text: store.query)
            } else {
                List(store.searchResults) { result in
                    Button {
                        NSWorkspace.shared.open(result.fileURL)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Label(result.fileURL.lastPathComponent, systemImage: result.kind.systemImage)
                                    .font(.headline)
                                Spacer()
                                Text("line \(result.line)")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            Text(result.snippet)
                                .lineLimit(3)
                                .foregroundStyle(.secondary)
                            Text(result.path)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Search")
    }
}

private extension PersonalWorkspaceKind {
    var systemImage: String {
        switch self {
        case .markdown: return "doc.text"
        case .shell: return "terminal"
        case .python: return "chevron.left.forwardslash.chevron.right"
        case .appleScript: return "applescript"
        case .launchd: return "clock.arrow.2.circlepath"
        }
    }
}
