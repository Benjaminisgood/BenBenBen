import Combine
import Foundation

@MainActor
final class PythonReplRunner: ObservableObject, @unchecked Sendable {
    @Published var input = ""
    @Published private(set) var output: String
    @Published private(set) var isRunning = false
    @Published private(set) var prompt = ">>>"

    private static let protocolPrefix = "__NOTCHWOW_REPL__"
    private static let outputLimit = 200_000

    static let bridgeScript = """
    import code
    import contextlib
    import json
    import sys
    import traceback

    _SENTINEL = "__NOTCHWOW_REPL__"
    _PROTOCOL_OUT = sys.stdout
    _CONSOLE = code.InteractiveConsole()

    def _emit(payload):
        _PROTOCOL_OUT.write(_SENTINEL + json.dumps(payload, ensure_ascii=False) + "\\n")
        _PROTOCOL_OUT.flush()

    class _ProtocolWriter:
        def write(self, text):
            if text:
                _emit({"type": "chunk", "text": text})
            return len(text)

        def flush(self):
            pass

    def _run_line(source):
        with contextlib.redirect_stdout(_ProtocolWriter()), contextlib.redirect_stderr(_ProtocolWriter()):
            more = _CONSOLE.push(source)
        _emit({"type": "done", "more": bool(more)})

    def _run_file(path):
        with open(path, "r", encoding="utf-8") as source_file:
            source = source_file.read()

        had_file = "__file__" in _CONSOLE.locals
        previous_file = _CONSOLE.locals.get("__file__")
        _CONSOLE.locals["__file__"] = path

        try:
            with contextlib.redirect_stdout(_ProtocolWriter()), contextlib.redirect_stderr(_ProtocolWriter()):
                try:
                    exec(compile(source, path, "exec"), _CONSOLE.locals, _CONSOLE.locals)
                except BaseException:
                    traceback.print_exc()
        finally:
            if had_file:
                _CONSOLE.locals["__file__"] = previous_file
            else:
                _CONSOLE.locals.pop("__file__", None)

        _emit({"type": "done", "more": False})

    _emit({"type": "ready"})

    for line in sys.stdin:
        try:
            request = json.loads(line)
            if request.get("type") == "file":
                _run_file(request["path"])
            else:
                _run_line(request.get("source", ""))
        except BaseException:
            with contextlib.redirect_stdout(_ProtocolWriter()), contextlib.redirect_stderr(_ProtocolWriter()):
                traceback.print_exc()
            _emit({"type": "done", "more": False})
    """

    private var workingDirectory: URL
    private let outputPersistenceURL: URL?
    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var readBuffer = ""
    private var sessionKey: String?
    private var needsMoreInput = false
    private var isStopping = false

    init(workingDirectory: URL, outputPersistenceURL: URL? = nil) {
        self.workingDirectory = workingDirectory
        self.outputPersistenceURL = outputPersistenceURL
        let persistedOutput = Self.loadText(from: outputPersistenceURL) ?? ""
        self.output = String(persistedOutput.suffix(Self.outputLimit))
        persistOutput()
    }

    func run(configuration: PythonLaunchConfiguration) {
        let source = input
        guard !isRunning else { return }
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || needsMoreInput else { return }
        guard ensureProcess(configuration: configuration) else { return }

        appendOutput("\(prompt) \(source)\n")
        input = ""
        isRunning = true
        sendRequest(["type": "line", "source": source])
    }

    func runFile(configuration: PythonLaunchConfiguration, filePath: String, displayName: String) {
        guard !isRunning else { return }
        guard ensureProcess(configuration: configuration) else { return }

        appendOutput(">>> exec(open(\(Self.pythonStringLiteral(displayName))).read())\n")
        needsMoreInput = false
        prompt = ">>>"
        isRunning = true
        sendRequest(["type": "file", "path": filePath])
    }

    func stop() {
        stopProcess(announce: true)
    }

    func clear() {
        output = ""
        persistOutput()
    }

    func useWorkingDirectory(_ url: URL) {
        guard workingDirectory.standardizedFileURL.path != url.standardizedFileURL.path else { return }
        stopProcess(announce: false)
        workingDirectory = url
    }

    private func ensureProcess(configuration: PythonLaunchConfiguration) -> Bool {
        if process != nil, sessionKey == configuration.sessionKey {
            return true
        }

        stopProcess(announce: false)
        readBuffer = ""
        needsMoreInput = false
        prompt = ">>>"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: configuration.executablePath)
        process.arguments = configuration.arguments
        process.currentDirectoryURL = workingDirectory

        var environment = ProcessInfo.processInfo.environment
        configuration.environment.forEach { key, value in
            environment[key] = value
        }
        process.environment = environment

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        let outputHandle = outputPipe.fileHandleForReading
        outputHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }

            let text = String(data: data, encoding: .utf8) ?? ""
            Task { @MainActor in
                self?.handleProcessOutput(text)
            }
        }

        process.terminationHandler = { [weak self] finishedProcess in
            outputHandle.readabilityHandler = nil
            Task { @MainActor in
                guard self?.process === finishedProcess else { return }
                if self?.isRunning == true, self?.isStopping == false {
                    self?.appendOutput("\n[python exited]\n")
                }
                self?.cleanupProcess()
            }
        }

        self.process = process
        self.inputPipe = inputPipe
        self.outputPipe = outputPipe
        self.sessionKey = configuration.sessionKey
        self.isStopping = false

        do {
            try process.run()
            return true
        } catch {
            appendOutput("\(error.localizedDescription)\n")
            cleanupProcess()
            return false
        }
    }

    private func stopProcess(announce: Bool) {
        guard let process else { return }
        isStopping = true
        if process.isRunning {
            process.terminate()
        }
        if announce {
            appendOutput("\n[python stopped]\n")
        }
        cleanupProcess()
    }

    private func cleanupProcess() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        try? inputPipe?.fileHandleForWriting.close()
        process = nil
        inputPipe = nil
        outputPipe = nil
        readBuffer = ""
        sessionKey = nil
        needsMoreInput = false
        prompt = ">>>"
        isRunning = false
        isStopping = false
    }

    private func sendRequest(_ request: [String: Any]) {
        do {
            let data = try JSONSerialization.data(withJSONObject: request)
            inputPipe?.fileHandleForWriting.write(data)
            inputPipe?.fileHandleForWriting.write(Data([0x0A]))
        } catch {
            appendOutput("\(error.localizedDescription)\n")
            isRunning = false
        }
    }

    private func handleProcessOutput(_ text: String) {
        readBuffer += text

        while let newlineRange = readBuffer.range(of: "\n") {
            let line = String(readBuffer[..<newlineRange.lowerBound])
            readBuffer.removeSubrange(readBuffer.startIndex...newlineRange.lowerBound)
            handleProtocolLine(line)
        }
    }

    private func handleProtocolLine(_ line: String) {
        guard line.hasPrefix(Self.protocolPrefix) else {
            appendOutput(line + "\n")
            return
        }

        let jsonText = String(line.dropFirst(Self.protocolPrefix.count))
        guard let data = jsonText.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = payload["type"] as? String else {
            return
        }

        switch type {
        case "chunk":
            appendOutput(payload["text"] as? String ?? "")
        case "done":
            needsMoreInput = payload["more"] as? Bool ?? false
            prompt = needsMoreInput ? "..." : ">>>"
            isRunning = false
        default:
            break
        }
    }

    private func appendOutput(_ text: String) {
        output += text
        if output.count > Self.outputLimit {
            output = String(output.suffix(Self.outputLimit))
        }
        persistOutput()
    }

    private func persistOutput() {
        guard let outputPersistenceURL else { return }
        Self.writeText(output, to: outputPersistenceURL)
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

    private nonisolated static func pythonStringLiteral(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let literal = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return literal
    }
}
