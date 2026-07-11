import Combine
import Darwin
import Foundation

@MainActor
final class CommandRunner: ObservableObject, @unchecked Sendable {
    @Published var input: String {
        didSet {
            persistInput()
        }
    }
    @Published private(set) var output: String
    @Published private(set) var isRunning = false

    private var workingDirectory: URL
    private var shellBootstrapURL: URL?
    private var environment: [String: String]
    private var inputPersistenceURL: URL?
    private var outputPersistenceURL: URL?
    private let showsCommandTimestamps: Bool
    private var process: Process?
    private var outputPipe: Pipe?
    private var showsSuccessfulExit = true
    private var showsFailedExit = true
    private let outputLimit = 200_000

    init(
        workingDirectory: URL,
        input: String = "",
        output: String = "",
        shellBootstrapURL: URL? = nil,
        environment: [String: String] = [:],
        inputPersistenceURL: URL? = nil,
        outputPersistenceURL: URL? = nil,
        showsCommandTimestamps: Bool = false
    ) {
        self.workingDirectory = workingDirectory
        self.shellBootstrapURL = shellBootstrapURL
        self.environment = environment
        self.inputPersistenceURL = inputPersistenceURL
        self.outputPersistenceURL = outputPersistenceURL
        self.showsCommandTimestamps = showsCommandTimestamps
        self.input = Self.loadText(from: inputPersistenceURL) ?? input
        self.output = Self.loadText(from: outputPersistenceURL) ?? output
        persistInput()
        persistOutput()
    }

    var workingDirectoryPath: String {
        workingDirectory.path
    }

    var storagePath: String {
        outputPersistenceURL?.path ?? workingDirectory.path
    }

    func run(
        _ commandOverride: String? = nil,
        displayCommand: String? = nil,
        displayPrompt: String = "$",
        clearsInputOnRun: Bool = false,
        showsSuccessfulExit: Bool = true,
        showsFailedExit: Bool = true
    ) {
        let command = (commandOverride ?? input).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty, !isRunning else { return }

        WorkspacePaths.ensureDirectories()
        let commandForDisplay = displayCommand ?? command
        let timestamp = showsCommandTimestamps ? "[\(Self.timestampString())] " : ""
        appendOutput("\n\(timestamp)\(displayPrompt) \(commandForDisplay)\n")
        self.showsSuccessfulExit = showsSuccessfulExit
        self.showsFailedExit = showsFailedExit
        isRunning = true
        if clearsInputOnRun {
            input = ""
        }

        let workingDirectory = workingDirectory
        let preparedCommand = preparedCommand(command)
        let preparedEnvironment = preparedEnvironment()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", preparedCommand]
        process.currentDirectoryURL = workingDirectory
        process.environment = preparedEnvironment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        self.process = process
        outputPipe = pipe

        let outputHandle = pipe.fileHandleForReading
        outputHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }

            let text = String(data: data, encoding: .utf8) ?? ""
            Task { @MainActor in
                self?.appendOutput(text)
            }
        }

        process.terminationHandler = { [weak self] finishedProcess in
            outputHandle.readabilityHandler = nil
            let status = finishedProcess.terminationStatus

            Task { @MainActor in
                guard self?.process === finishedProcess else { return }
                if status == 0 {
                    if self?.showsSuccessfulExit == true {
                        self?.appendOutput("\n[exit \(status)]\n")
                    }
                } else if self?.showsFailedExit == true {
                    self?.appendOutput("\n[exit \(status)]\n")
                }
                self?.isRunning = false
                self?.process = nil
                self?.outputPipe = nil
                self?.showsSuccessfulExit = true
                self?.showsFailedExit = true
            }
        }

        do {
            try process.run()
        } catch {
            outputHandle.readabilityHandler = nil
            appendOutput("\(error.localizedDescription)\n")
            isRunning = false
            self.process = nil
            outputPipe = nil
            self.showsSuccessfulExit = true
            self.showsFailedExit = true
        }
    }

    func stop() {
        guard let process else { return }
        let pid = process.processIdentifier

        DispatchQueue.global(qos: .userInitiated).async {
            Self.terminateProcessTree(rootPID: pid, signal: SIGTERM)
            Thread.sleep(forTimeInterval: 0.7)

            if process.isRunning {
                Self.terminateProcessTree(rootPID: pid, signal: SIGKILL)
            }
        }
    }

    func clear() {
        output = ""
        persistOutput()
    }

    func useWorkingDirectory(_ url: URL) {
        guard !isRunning else { return }
        workingDirectory = url
    }

    func useShellConfiguration(bootstrapURL: URL?, environment: [String: String]) {
        guard !isRunning else { return }
        shellBootstrapURL = bootstrapURL
        self.environment = environment
    }

    func usePersistence(
        inputURL: URL?,
        outputURL: URL?,
        defaultInput: String = ""
    ) {
        guard !isRunning else { return }
        guard inputPersistenceURL?.path != inputURL?.path || outputPersistenceURL?.path != outputURL?.path else { return }

        inputPersistenceURL = inputURL
        outputPersistenceURL = outputURL
        input = Self.loadText(from: inputURL) ?? defaultInput
        output = Self.loadText(from: outputURL) ?? ""
        persistInput()
        persistOutput()
    }

    private func appendOutput(_ text: String) {
        output += text

        if output.count > outputLimit {
            output = String(output.suffix(outputLimit))
        }

        persistOutput()
    }

    private func persistInput() {
        guard let inputPersistenceURL else { return }
        Self.writeText(input, to: inputPersistenceURL)
    }

    private func persistOutput() {
        guard let outputPersistenceURL else { return }
        Self.writeText(output, to: outputPersistenceURL)
    }

    private func preparedCommand(_ command: String) -> String {
        guard let shellBootstrapURL else { return command }

        return """
        source \(shellBootstrapURL.path.shellEscaped)
        \(command)
        """
    }

    private func preparedEnvironment() -> [String: String] {
        var nextEnvironment = ProcessInfo.processInfo.environment
        environment.forEach { key, value in
            nextEnvironment[key] = value
        }
        return nextEnvironment
    }

    private nonisolated static func terminateProcessTree(rootPID: Int32, signal: Int32) {
        childProcessIDs(parentPID: rootPID).forEach { childPID in
            terminateProcessTree(rootPID: childPID, signal: signal)
        }

        kill(rootPID, signal)
    }

    private nonisolated static func childProcessIDs(parentPID: Int32) -> [Int32] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,ppid="]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        return output
            .components(separatedBy: .newlines)
            .compactMap { line -> Int32? in
                let parts = line
                    .split { $0 == " " || $0 == "\t" }
                    .compactMap { Int32($0) }

                guard parts.count >= 2, parts[1] == parentPID else { return nil }
                return parts[0]
            }
    }

    private nonisolated static func loadText(from url: URL?) -> String? {
        guard let url else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private nonisolated static func writeText(_ text: String, to url: URL) {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    private nonisolated static func timestampString() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: Date())
    }
}
