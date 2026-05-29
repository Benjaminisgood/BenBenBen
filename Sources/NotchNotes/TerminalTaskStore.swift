import Combine
import Darwin
import Foundation

struct TerminalProcessInfo: Identifiable, Equatable, Sendable {
    let id: Int32
    let pid: Int32
    let parentPID: Int32
    let processGroupID: Int32
    let tty: String
    let state: String
    let elapsed: String
    let command: String

    var shortCommand: String {
        TerminalTaskStore.shortCommand(command)
    }
}

struct TerminalTask: Identifiable, Equatable, Sendable {
    let id: Int32
    let processGroupID: Int32
    let tty: String
    let leaderPID: Int32
    let representativePID: Int32
    let elapsed: String
    let state: String
    let title: String
    let detail: String
    let command: String
    let processes: [TerminalProcessInfo]
    let isNotchwowManaged: Bool
    let isTerminalAppBacked: Bool

    var processCount: Int {
        processes.count
    }

    var isZombieOnly: Bool {
        !processes.isEmpty && processes.allSatisfy { $0.state.contains("Z") }
    }

    var canReceiveTerminalInput: Bool {
        isTerminalAppBacked
            && !isNotchwowManaged
            && !isZombieOnly
            && tty != "??"
            && tty != "notchwow"
    }
}

@MainActor
final class TerminalTaskStore: ObservableObject {
    @Published private(set) var tasks: [TerminalTask] = []
    @Published var selectedTaskID: TerminalTask.ID?
    @Published var searchQuery = ""
    @Published private(set) var lastRefresh = Date()
    @Published private(set) var isRefreshing = false
    @Published private(set) var terminalSnapshot: TerminalTabSnapshot?
    @Published private(set) var terminalBridgeMessage: String?
    @Published private(set) var terminalOperationIsError = false
    @Published private(set) var isTerminalBridgeBusy = false

    private var refreshTimer: Timer?

    init() {
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    var selectedTask: TerminalTask? {
        guard let selectedTaskID else { return tasks.first }
        return tasks.first { $0.id == selectedTaskID } ?? tasks.first
    }

    var availableTerminalTabs: [String] {
        tasks
            .filter { $0.canReceiveTerminalInput }
            .map { $0.tty }
    }

    var filteredTasks: [TerminalTask] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return tasks }

        return tasks.filter { task in
            task.title.localizedCaseInsensitiveContains(query)
                || task.detail.localizedCaseInsensitiveContains(query)
                || task.tty.localizedCaseInsensitiveContains(query)
                || task.command.localizedCaseInsensitiveContains(query)
                || task.processes.contains { process in
                    process.command.localizedCaseInsensitiveContains(query)
                }
        }
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true

        DispatchQueue.global(qos: .utility).async {
            let nextTasks = Self.loadTasks()

            Task { @MainActor in
                self.applyTasks(nextTasks)
                self.isRefreshing = false
            }
        }
    }

    private func applyTasks(_ nextTasks: [TerminalTask]) {
        let previousTaskID = selectedTaskID
        tasks = nextTasks

        if let selectedTaskID, nextTasks.contains(where: { $0.id == selectedTaskID }) {
            self.selectedTaskID = selectedTaskID
        } else {
            selectedTaskID = nextTasks.first?.id
        }

        if previousTaskID != selectedTaskID {
            terminalSnapshot = nil
            setTerminalOperationMessage(nil)
        }

        lastRefresh = Date()
    }

    func select(_ task: TerminalTask) {
        selectedTaskID = task.id
        terminalSnapshot = nil
        setTerminalOperationMessage(nil)
    }

    func terminateSelectedTask() {
        guard let selectedTask else { return }
        Self.signalProcessGroup(selectedTask.processGroupID, signal: SIGTERM)
        refreshSoon()
    }

    func killSelectedTask() {
        guard let selectedTask else { return }
        Self.signalProcessGroup(selectedTask.processGroupID, signal: SIGKILL)
        refreshSoon()
    }

    func openTerminal() {
        TerminalAppBridge.openTerminal()
    }

    func openNewTerminalWindow(workingDirectory: String = WorkspacePaths.shellRoot.path) {
        runTerminalBridgeOperation {
            TerminalAppBridge.openNewWindow(workingDirectory: workingDirectory)
        } completion: { [weak self] result in
            switch result {
            case .success:
                self?.setTerminalOperationMessage("New Terminal opened")
                self?.refreshSoon()
            case .failure(let message):
                self?.setTerminalOperationMessage(message, isError: true)
                self?.refreshSoon()
            }
        }
    }

    func focusSelectedTerminal() {
        guard let selectedTask else {
            TerminalAppBridge.openTerminal()
            return
        }

        guard !selectedTask.isNotchwowManaged else {
            setTerminalOperationMessage(
                "This task is managed by notchwow. Use the jump button to return to its Shell/Py pane.",
                isError: true
            )
            return
        }

        let tty = selectedTask.tty
        runTerminalBridgeOperation {
            TerminalAppBridge.focus(tty: tty)
        } completion: { [weak self] result in
            switch result {
            case .success:
                self?.setTerminalOperationMessage("Focused")
            case .failure(let message):
                self?.terminalSnapshot = nil
                self?.setTerminalOperationMessage(message, isError: true)
            }
        }
    }

    func refreshSelectedTerminalSnapshot(silent: Bool = false) {
        guard let selectedTask else {
            terminalSnapshot = nil
            setTerminalOperationMessage("No terminal task selected", isError: true)
            return
        }

        let taskID = selectedTask.id
        let tty = selectedTask.tty

        runTerminalBridgeOperation {
            TerminalAppBridge.snapshot(forTTY: tty)
        } completion: { [weak self] result in
            guard let self else { return }
            guard self.selectedTaskID == nil || self.selectedTaskID == taskID else { return }

            switch result {
            case .success(let snapshot):
                self.terminalSnapshot = snapshot
                if !silent {
                    self.setTerminalOperationMessage("Snapshot refreshed")
                }

            case .failure(let message):
                self.terminalSnapshot = nil
                if !silent || self.terminalBridgeMessage == nil {
                    self.setTerminalOperationMessage(message, isError: true)
                }
            }
        }
    }

    func clearTerminalSnapshot() {
        terminalSnapshot = nil
        setTerminalOperationMessage(nil)
    }

    func processSummary(for task: TerminalTask?) -> String {
        guard let task else { return "No terminal task selected" }

        return task.processes.map { process in
            "\(process.pid)  \(process.state)  \(process.elapsed)\n\(process.shortCommand)"
        }
        .joined(separator: "\n\n")
    }

    private func refreshSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.refresh()
        }
    }

    private func setTerminalOperationMessage(_ message: String?, isError: Bool = false) {
        terminalBridgeMessage = message
        terminalOperationIsError = isError
    }

    private func runTerminalBridgeOperation<Value: Sendable>(
        _ operation: @escaping @Sendable () -> TerminalBridgeResult<Value>,
        completion: @escaping @MainActor (TerminalBridgeResult<Value>) -> Void
    ) {
        guard !isTerminalBridgeBusy else { return }
        isTerminalBridgeBusy = true

        DispatchQueue.global(qos: .utility).async {
            let result = operation()

            Task { @MainActor in
                self.isTerminalBridgeBusy = false
                completion(result)
            }
        }
    }

    private nonisolated static func loadTasks() -> [TerminalTask] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,ppid=,pgid=,tty=,stat=,etime=,command="]

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

        guard process.terminationStatus == 0 else { return [] }

        let output = String(data: data, encoding: .utf8) ?? ""
        let allProcesses = output
            .components(separatedBy: .newlines)
            .compactMap(parseProcessLine)
        let parentByPID = Dictionary(uniqueKeysWithValues: allProcesses.map { ($0.pid, $0.parentPID) })
        let commandByPID = Dictionary(uniqueKeysWithValues: allProcesses.map { ($0.pid, $0.command) })
        let currentPID = getpid()
        let processes = allProcesses.filter { process in
            process.tty != "??" || isDescendant(process.pid, of: currentPID, parentByPID: parentByPID)
        }

        let grouped = Dictionary(grouping: processes, by: \.processGroupID)

        return grouped.values
            .compactMap {
                makeTask(
                    from: $0,
                    currentPID: currentPID,
                    parentByPID: parentByPID,
                    commandByPID: commandByPID
                )
            }
            .sorted { lhs, rhs in
                if lhs.tty == rhs.tty {
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }
                return lhs.tty.localizedStandardCompare(rhs.tty) == .orderedAscending
            }
    }

    private nonisolated static func parseProcessLine(_ line: String) -> TerminalProcessInfo? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let parts = trimmed
            .split(maxSplits: 6, omittingEmptySubsequences: true) { $0 == " " || $0 == "\t" }
            .map(String.init)
        guard parts.count >= 7,
              let pid = Int32(parts[0]),
              let parentPID = Int32(parts[1]),
              let processGroupID = Int32(parts[2]) else {
            return nil
        }

        return TerminalProcessInfo(
            id: pid,
            pid: pid,
            parentPID: parentPID,
            processGroupID: processGroupID,
            tty: parts[3],
            state: parts[4],
            elapsed: parts[5],
            command: parts[6]
        )
    }

    private nonisolated static func makeTask(
        from processes: [TerminalProcessInfo],
        currentPID: Int32,
        parentByPID: [Int32: Int32],
        commandByPID: [Int32: String]
    ) -> TerminalTask? {
        guard !processes.isEmpty else { return nil }

        let sortedProcesses = processes.sorted { lhs, rhs in
            if lhs.pid == lhs.processGroupID { return true }
            if rhs.pid == rhs.processGroupID { return false }
            return lhs.pid < rhs.pid
        }

        let leader = sortedProcesses.first { $0.pid == $0.processGroupID } ?? sortedProcesses[0]
        let representative = sortedProcesses.last { process in
            !isWrapperCommand(process.command) && !process.state.contains("Z")
        } ?? leader

        let isManaged = sortedProcesses.contains { process in
            process.tty == "??" && isDescendant(process.pid, of: currentPID, parentByPID: parentByPID)
        }
        let isTerminalAppBacked = sortedProcesses.contains { process in
            hasTerminalAppAncestor(process.pid, parentByPID: parentByPID, commandByPID: commandByPID)
        }
        let tty = isManaged && leader.tty == "??" ? "notchwow" : leader.tty
        let title = managedTitle(for: representative.command) ?? shortCommand(representative.command)
        let detail = "\(tty)  pgid \(leader.processGroupID)  \(sortedProcesses.count) proc"

        return TerminalTask(
            id: leader.processGroupID,
            processGroupID: leader.processGroupID,
            tty: tty,
            leaderPID: leader.pid,
            representativePID: representative.pid,
            elapsed: representative.elapsed,
            state: representative.state,
            title: title,
            detail: detail,
            command: representative.command,
            processes: sortedProcesses,
            isNotchwowManaged: isManaged,
            isTerminalAppBacked: isTerminalAppBacked
        )
    }

    private nonisolated static func isDescendant(
        _ pid: Int32,
        of ancestorPID: Int32,
        parentByPID: [Int32: Int32]
    ) -> Bool {
        var currentPID = pid
        var visited = Set<Int32>()

        while let parentPID = parentByPID[currentPID], parentPID > 0 {
            if parentPID == ancestorPID {
                return true
            }
            guard !visited.contains(parentPID) else { return false }
            visited.insert(parentPID)
            currentPID = parentPID
        }

        return false
    }

    private nonisolated static func hasTerminalAppAncestor(
        _ pid: Int32,
        parentByPID: [Int32: Int32],
        commandByPID: [Int32: String]
    ) -> Bool {
        var currentPID = pid
        var visited = Set<Int32>()

        while currentPID > 0, !visited.contains(currentPID) {
            visited.insert(currentPID)

            if let command = commandByPID[currentPID],
               isTerminalAppCommand(command) {
                return true
            }

            guard let parentPID = parentByPID[currentPID], parentPID != currentPID else {
                return false
            }
            currentPID = parentPID
        }

        return false
    }

    private nonisolated static func isTerminalAppCommand(_ command: String) -> Bool {
        command.contains("/Terminal.app/Contents/MacOS/Terminal")
            || command == "Terminal"
    }

    private nonisolated static func managedTitle(for command: String) -> String? {
        if command.contains("__NOTCHWOW_REPL__") || command.contains("InteractiveConsole") {
            return "notchwow Python REPL"
        }
        return nil
    }

    private nonisolated static func isWrapperCommand(_ command: String) -> Bool {
        let lowered = command.lowercased()
        return lowered.hasPrefix("login ")
            || lowered == "-zsh"
            || lowered == "zsh"
            || lowered.hasPrefix("/bin/zsh")
            || lowered.hasPrefix("/bin/bash")
            || lowered.hasPrefix("-bash")
            || lowered.hasPrefix("screen ")
            || lowered.contains("screen -dm")
    }

    nonisolated static func shortCommand(_ command: String) -> String {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "terminal" }

        let replacements: [(String, String)] = [
            ("/Users/ben/Desktop/", "~/Desktop/"),
            ("/Users/ben/", "~/")
        ]

        var shortened = trimmed
        replacements.forEach { original, replacement in
            shortened = shortened.replacingOccurrences(of: original, with: replacement)
        }

        if shortened.count > 82 {
            return String(shortened.prefix(79)) + "..."
        }

        return shortened
    }

    private nonisolated static func signalProcessGroup(_ processGroupID: Int32, signal: Int32) {
        guard processGroupID > 1 else { return }
        kill(-processGroupID, signal)
    }

    private nonisolated static func workingDirectory(for pid: Int32) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-a", "-p", "\(pid)", "-d", "cwd", "-Fn"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else { return nil }

        return String(data: data, encoding: .utf8)?
            .components(separatedBy: .newlines)
            .first { $0.hasPrefix("n/") }
            .map { String($0.dropFirst()) }
    }
}
