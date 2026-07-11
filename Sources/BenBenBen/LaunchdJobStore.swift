import AppKit
import Combine
import Foundation

struct LaunchdJob: Identifiable, Equatable {
    let id: String
    let label: String
    let plistURL: URL
    let content: String
    let isLoaded: Bool
    let modifiedAt: Date

    var title: String {
        label
    }

    var detail: String {
        plistURL.lastPathComponent
    }
}

@MainActor
final class LaunchdJobStore: ObservableObject {
    @Published private(set) var jobs: [LaunchdJob] = []
    @Published private(set) var loadedLabels: Set<String> = []
    @Published var selectedJobID: String?
    @Published var editingContent: String = "" {
        didSet {
            // Mark dirty when content changes from user editing (not from refresh)
            if !isRefreshing {
                isDirty = true
            }
        }
    }
    @Published var searchQuery: String = ""
    @Published private(set) var isDirty: Bool = false
    private var isRefreshing: Bool = false
    @Published private(set) var operationMessage: String = ""
    @Published private(set) var isOperationError: Bool = false
    @Published private(set) var outputLog: String = ""

    private var refreshTimer: Timer?

    nonisolated static var configuredRoot: URL {
        if let path = AppDefaults.string(
            forKey: "benbenben.launchdPath",
            migrating: ["notchwow.launchdPath", "notchNotes.launchdPath"]
        ),
           !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return WorkspacePaths.launchdRoot
    }

    init() {
        refresh()
        cleanupOrphanedServices()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    var selectedJob: LaunchdJob? {
        guard let selectedJobID else { return jobs.first }
        return jobs.first { $0.id == selectedJobID } ?? jobs.first
    }

    var loadedJobs: [LaunchdJob] {
        jobs.filter { $0.isLoaded }
    }

    var filteredJobs: [LaunchdJob] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return jobs }
        return jobs.filter { job in
            job.label.localizedCaseInsensitiveContains(query)
                || job.detail.localizedCaseInsensitiveContains(query)
        }
    }

    func select(_ job: LaunchdJob) {
        selectedJobID = job.id
        isRefreshing = true
        editingContent = job.content
        isRefreshing = false
        isDirty = false
    }

    func refresh() {
        try? FileManager.default.createDirectory(at: Self.configuredRoot, withIntermediateDirectories: true)
        let loaded = Self.queryLoadedLabels()
        loadedLabels = loaded
        let scanned = Self.scanPlistFiles(loadedLabels: loaded)
        jobs = scanned

        // Don't overwrite user edits that haven't been saved yet
        guard !isDirty else { return }

        isRefreshing = true
        if let selectedJobID,
           let updated = scanned.first(where: { $0.id == selectedJobID }) {
            editingContent = updated.content
        } else if let first = scanned.first, selectedJobID == nil {
            editingContent = first.content
        }
        isRefreshing = false
    }

    func saveEditingContent() {
        guard let job = selectedJob else {
            setMessage("No job selected", isError: true)
            return
        }
        if let message = FilePermissionLock.modificationBlockedMessage(for: job.plistURL, action: "Save") {
            setMessage(message, isError: true)
            appendLog(message)
            return
        }

        do {
            try editingContent.write(to: job.plistURL, atomically: true, encoding: .utf8)

            // Auto-rename file to match Label
            if let newLabel = Self.extractLabel(from: editingContent) {
                let expectedFilename = "\(newLabel).plist"
                let currentFilename = job.plistURL.lastPathComponent
                if expectedFilename != currentFilename {
                    let targetURL = WorkspacePaths.uniquedFileURL(
                        stem: newLabel,
                        fileExtension: "plist",
                        in: Self.configuredRoot,
                        excluding: job.plistURL
                    )
                    try FileManager.default.moveItem(at: job.plistURL, to: targetURL)
                    selectedJobID = targetURL.lastPathComponent
                    appendLog("Renamed \(currentFilename) → \(targetURL.lastPathComponent)")
                }
            }

            setMessage("Saved \(selectedJobID ?? job.detail)")
            appendLog("Saved \(selectedJobID ?? job.detail)")
            isDirty = false
            refresh()
        } catch {
            setMessage("Save failed: \(error.localizedDescription)", isError: true)
            appendLog("⚠ Save failed: \(error.localizedDescription)")
        }
    }

    func createJob(filename: String, content: String) {
        let sanitized = WorkspacePaths.sanitizedFileStem(filename, fallback: "com.benbenben.task")
        let url = WorkspacePaths.uniquedFileURL(
            stem: sanitized,
            fileExtension: "plist",
            in: Self.configuredRoot
        )

        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            refresh()
            if let created = jobs.first(where: { $0.plistURL == url }) {
                select(created)
            }
            setMessage("Created \(url.lastPathComponent)")
            appendLog("Created \(url.lastPathComponent)")
        } catch {
            setMessage("Create failed: \(error.localizedDescription)", isError: true)
            appendLog("⚠ Create failed: \(error.localizedDescription)")
        }
    }

    func loadJob(_ job: LaunchdJob) {
        let uid = getuid()
        let domain = "gui/\(uid)"
        let result = Self.runLaunchctl(["bootstrap", domain, job.plistURL.path])
        if result.success {
            setMessage("Loaded \(job.label)")
            appendLog("▶ Loaded \(job.label)")
        } else if result.output.contains("already bootstrapped") || result.output.contains("service already loaded") {
            setMessage("\(job.label) already loaded")
            appendLog("▶ \(job.label) already loaded")
        } else {
            setMessage("Load failed: \(result.output)", isError: true)
            appendLog("⚠ Load failed [\(job.label)]: \(result.output)")
        }
        refresh()
    }

    func unloadJob(_ job: LaunchdJob) {
        let uid = getuid()
        let target = "gui/\(uid)/\(job.label)"
        let result = Self.runLaunchctl(["bootout", target])
        if result.success {
            setMessage("Unloaded \(job.label)")
            appendLog("⏹ Unloaded \(job.label)")
        } else {
            setMessage("Unload failed: \(result.output)", isError: true)
            appendLog("⚠ Unload failed [\(job.label)]: \(result.output)")
        }
        refresh()
    }

    func loadAllJobs() {
        let pendingJobs = jobs.filter { !$0.isLoaded }
        guard !pendingJobs.isEmpty else {
            setMessage("All jobs already loaded")
            appendLog("▶ All jobs already loaded")
            return
        }

        let uid = getuid()
        let domain = "gui/\(uid)"
        var loadedCount = 0
        var failedLabels: [String] = []

        for job in pendingJobs {
            let result = Self.runLaunchctl(["bootstrap", domain, job.plistURL.path])
            if result.success || result.output.contains("already bootstrapped") || result.output.contains("service already loaded") {
                loadedCount += 1
            } else {
                failedLabels.append(job.label)
                appendLog("⚠ Load failed [\(job.label)]: \(result.output)")
            }
        }

        if failedLabels.isEmpty {
            setMessage("Loaded \(loadedCount) jobs")
            appendLog("▶ Loaded \(loadedCount) jobs")
        } else {
            setMessage("Loaded \(loadedCount), failed \(failedLabels.count)", isError: true)
            appendLog("⚠ Loaded \(loadedCount), failed: \(failedLabels.joined(separator: ", "))")
        }
        refresh()
    }

    func unloadAllLoadedJobs() {
        let activeJobs = loadedJobs
        guard !activeJobs.isEmpty else {
            setMessage("No loaded jobs")
            appendLog("⏹ No loaded jobs")
            return
        }

        let uid = getuid()
        var unloadedCount = 0
        var failedLabels: [String] = []

        for job in activeJobs {
            let target = "gui/\(uid)/\(job.label)"
            let result = Self.runLaunchctl(["bootout", target])
            if result.success {
                unloadedCount += 1
            } else {
                failedLabels.append(job.label)
                appendLog("⚠ Unload failed [\(job.label)]: \(result.output)")
            }
        }

        if failedLabels.isEmpty {
            setMessage("Unloaded \(unloadedCount) jobs")
            appendLog("⏹ Unloaded \(unloadedCount) jobs")
        } else {
            setMessage("Unloaded \(unloadedCount), failed \(failedLabels.count)", isError: true)
            appendLog("⚠ Unloaded \(unloadedCount), failed: \(failedLabels.joined(separator: ", "))")
        }
        refresh()
    }

    func moveJobToTrash(_ job: LaunchdJob) {
        if let message = FilePermissionLock.modificationBlockedMessage(for: job.plistURL, action: "Move to Trash") {
            setMessage(message, isError: true)
            appendLog(message)
            return
        }
        if job.isLoaded {
            let uid = getuid()
            let target = "gui/\(uid)/\(job.label)"
            _ = Self.runLaunchctl(["bootout", target])
        }

        NSWorkspace.shared.recycle([job.plistURL]) { [weak self] _, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.setMessage("Move to Trash failed: \(error.localizedDescription)", isError: true)
                    self.appendLog("Move to Trash failed: \(error.localizedDescription)")
                    return
                }
                if self.selectedJobID == job.id {
                    self.selectedJobID = nil
                    self.editingContent = ""
                }
                self.setMessage("Moved \(job.detail) to Trash")
                self.appendLog("Moved \(job.detail) to Trash")
                self.refresh()
            }
        }
    }

    func clearOutputLog() {
        outputLog = ""
    }

    func appendLog(_ message: String) {
        let timestamp = Self.logTimestamp()
        let line = "[\(timestamp)] \(message)"
        if outputLog.isEmpty {
            outputLog = line
        } else {
            outputLog += "\n\(line)"
        }
    }

    // MARK: - Orphan Cleanup

    private func cleanupOrphanedServices() {
        let knownLabels = Set(jobs.map(\.label))
        let orphans = loadedLabels.filter { label in
            label.hasPrefix("com.benbenben.") && !knownLabels.contains(label)
        }

        guard !orphans.isEmpty else { return }

        let uid = getuid()
        for label in orphans {
            let target = "gui/\(uid)/\(label)"
            let result = Self.runLaunchctl(["bootout", target])
            if result.success {
                appendLog("🧹 Cleaned orphan: \(label)")
            }
        }

        // Re-query after cleanup
        loadedLabels = Self.queryLoadedLabels()
    }

    // MARK: - Template

    nonisolated static func plistTemplate(label: String) -> String {
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": ["/bin/zsh", "-c", "echo \"Hello from \(label)\""],
            "StartInterval": 300,
            "StandardOutPath": "/tmp/\(label).stdout.log",
            "StandardErrorPath": "/tmp/\(label).stderr.log"
        ]

        guard let data = try? PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        ) else {
            return ""
        }

        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Private

    private func setMessage(_ message: String, isError: Bool = false) {
        operationMessage = message
        isOperationError = isError
    }

    private nonisolated static func logTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }

    private nonisolated static func scanPlistFiles(loadedLabels: Set<String>) -> [LaunchdJob] {
        let manager = FileManager.default
        let root = configuredRoot

        guard let files = try? manager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return files
            .filter { $0.pathExtension == "plist" }
            .compactMap { url -> LaunchdJob? in
                guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                let attrs = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                let modDate = attrs?.contentModificationDate ?? Date.distantPast
                let label = extractLabel(from: content) ?? url.deletingPathExtension().lastPathComponent

                return LaunchdJob(
                    id: url.lastPathComponent,
                    label: label,
                    plistURL: url,
                    content: content,
                    isLoaded: loadedLabels.contains(label),
                    modifiedAt: modDate
                )
            }
            .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    nonisolated static func extractLabel(from plistContent: String) -> String? {
        guard let data = plistContent.data(using: .utf8),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data,
                  options: [],
                  format: nil
              ) as? [String: Any],
              let value = plist["Label"] as? String else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private nonisolated static func queryLoadedLabels() -> Set<String> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["list"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8) else { return [] }

        // launchctl list output: PID\tStatus\tLabel
        let labels = output
            .components(separatedBy: .newlines)
            .dropFirst() // header line
            .compactMap { line -> String? in
                let parts = line.split(separator: "\t", maxSplits: 2)
                guard parts.count >= 3 else { return nil }
                return String(parts[2])
            }

        return Set(labels)
    }

    private nonisolated static func runLaunchctl(_ arguments: [String]) -> (success: Bool, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            return (false, error.localizedDescription)
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (process.terminationStatus == 0, output)
    }
}
