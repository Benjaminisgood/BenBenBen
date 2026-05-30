import AppKit
import Darwin
import Foundation

struct TerminalTabSnapshot: Equatable, Sendable {
    let tty: String
    let contents: String
    let processes: String
    let isBusy: Bool
    let capturedAt: Date
}

enum TerminalBridgeResult<Value: Sendable>: Sendable {
    case success(Value)
    case failure(String)
}

enum TerminalAppBridge {
    private static let bundleIdentifier = "com.apple.Terminal"
    private static let separator = "__NOTCHWOW_FIELD_SEPARATOR__"

    static var isTerminalRunning: Bool {
        commandExitStatus("/usr/bin/pgrep", arguments: ["-x", "Terminal"]) == 0
    }

    @discardableResult
    static func openTerminal() -> Bool {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
    }

    static func openNewWindow(workingDirectory: String? = nil) -> TerminalBridgeResult<Void> {
        let command: String
        if let workingDirectory, !workingDirectory.isEmpty {
            command = "cd \(workingDirectory.shellEscaped)"
        } else {
            command = ""
        }

        switch runAppleScript(newTerminalScript(command: command)) {
        case .success:
            return .success(())
        case .failure(let message):
            openTerminal()
            return .failure(message)
        }
    }

    static func snapshot(forTTY tty: String) -> TerminalBridgeResult<TerminalTabSnapshot> {
        guard isTerminalRunning else {
            return .failure("Terminal.app is not running")
        }

        switch runAppleScript(findTabScript(tty: tty, action: .snapshot)) {
        case .success(let output):
            let fields = parseFields(output)
            guard fields.first == "OK", fields.count >= 5 else {
                return .failure(fields.dropFirst().first ?? output)
            }

            return .success(
                TerminalTabSnapshot(
                    tty: fields[1],
                    contents: fields[4],
                    processes: fields[3],
                    isBusy: fields[2].lowercased() == "true",
                    capturedAt: Date()
                )
            )

        case .failure(let message):
            return .failure(message)
        }
    }

    static func focus(tty: String) -> TerminalBridgeResult<Void> {
        guard isTerminalRunning else {
            return .failure("Terminal.app is not running")
        }

        switch runAppleScript(findTabScript(tty: tty, action: .focus)) {
        case .success(let output):
            let fields = parseFields(output)
            if fields.first == "OK" {
                return .success(())
            }
            return .failure(fields.dropFirst().first ?? output)

        case .failure(let message):
            return .failure(message)
        }
    }

    static func run(command: String, tty: String?, workingDirectory: String?) -> TerminalBridgeResult<Void> {
        let preparedCommand = preparedCommand(command, workingDirectory: workingDirectory)
        guard !preparedCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if let tty {
                return focus(tty: tty)
            }
            return .failure("No Terminal command")
        }

        if let tty {
            switch runAppleScript(findTabScript(tty: tty, action: .run(preparedCommand))) {
            case .success(let output):
                let fields = parseFields(output)
                if fields.first == "OK" {
                    return .success(())
                }
                return .failure(fields.dropFirst().first ?? output)

            case .failure(let message):
                return .failure(message)
            }
        }

        switch runAppleScript(newTerminalScript(command: preparedCommand)) {
        case .success:
            return .success(())
        case .failure(let message):
            return .failure(message)
        }
    }

    private static func preparedCommand(_ command: String, workingDirectory: String?) -> String {
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCommand.isEmpty else { return "" }
        guard let workingDirectory, !workingDirectory.isEmpty else { return trimmedCommand }
        return "cd \(workingDirectory.shellEscaped) && \(trimmedCommand)"
    }

    private enum TabAction {
        case snapshot
        case focus
        case run(String)
    }

    private static func findTabScript(tty: String, action: TabAction) -> String {
        let actionBody: String

        switch action {
        case .snapshot:
            actionBody = """
                              set tabContents to contents of aTab as text
                              set tabProcesses to my joinList(processes of aTab, ", ")
                              return "OK" & sep & tabTTY & sep & (busy of aTab as text) & sep & tabProcesses & sep & tabContents
            """

        case .focus:
            actionBody = """
                              activate
                              set selected tab of aWindow to aTab
                              set index of aWindow to 1
                              return "OK"
            """

        case .run(let command):
            actionBody = """
                              activate
                              set selected tab of aWindow to aTab
                              set index of aWindow to 1
                              do script \(appleScriptString(command)) in aTab
                              return "OK"
            """
        }

        return """
        on normalizeTTY(rawTTY)
            set ttyText to rawTTY as text
            if ttyText starts with "/dev/" then
                if (length of ttyText) > 5 then return text 6 thru -1 of ttyText
            end if
            return ttyText
        end normalizeTTY

        on joinList(itemsToJoin, delimiter)
            set oldDelimiters to AppleScript's text item delimiters
            set AppleScript's text item delimiters to delimiter
            set joinedText to itemsToJoin as text
            set AppleScript's text item delimiters to oldDelimiters
            return joinedText
        end joinList

        set targetTTY to \(appleScriptString(normalizedTTY(tty)))
        set sep to \(appleScriptString(separator))

        tell application "Terminal"
            if (count of windows) = 0 then return "ERR" & sep & "Terminal.app has no windows"

            repeat with windowIndex from 1 to count of windows
                set aWindow to window windowIndex
                repeat with tabIndex from 1 to count of tabs of aWindow
                    set aTab to tab tabIndex of aWindow
                    set tabTTY to my normalizeTTY(tty of aTab)
                    if tabTTY is targetTTY then
        \(actionBody)
                    end if
                end repeat
            end repeat
        end tell

        return "ERR" & sep & "No Terminal.app tab matches " & targetTTY
        """
    }

    private static func newTerminalScript(command: String) -> String {
        """
        tell application "Terminal"
            activate
            do script \(appleScriptString(command))
            return "OK"
        end tell
        """
    }

    private static func normalizedTTY(_ tty: String) -> String {
        if tty.hasPrefix("/dev/") {
            return String(tty.dropFirst(5))
        }
        return tty
    }

    private static func parseFields(_ output: String) -> [String] {
        output.components(separatedBy: separator)
    }

    private static func appleScriptString(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n", with: "\" & linefeed & \"")
        return "\"\(escaped)\""
    }

    private static func runAppleScript(_ source: String) -> TerminalBridgeResult<String> {
        let identifier = UUID().uuidString
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("notchwow-osascript-\(identifier).out")
        let errorURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("notchwow-osascript-\(identifier).err")

        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        FileManager.default.createFile(atPath: errorURL.path, contents: nil)

        guard let outputHandle = try? FileHandle(forWritingTo: outputURL),
              let errorHandle = try? FileHandle(forWritingTo: errorURL) else {
            return .failure("Could not create Terminal automation output files")
        }

        defer {
            try? outputHandle.close()
            try? errorHandle.close()
            try? FileManager.default.removeItem(at: outputURL)
            try? FileManager.default.removeItem(at: errorURL)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        process.standardOutput = outputHandle
        process.standardError = errorHandle

        do {
            try process.run()
        } catch {
            return .failure(error.localizedDescription)
        }

        guard waitForExit(process, timeout: 4.0) else {
            process.terminate()
            if !waitForExit(process, timeout: 0.4) {
                kill(process.processIdentifier, SIGKILL)
                _ = waitForExit(process, timeout: 0.4)
            }
            return .failure("Terminal automation timed out")
        }

        try? outputHandle.synchronize()
        try? errorHandle.synchronize()

        let output = (try? String(contentsOf: outputURL, encoding: .utf8)) ?? ""
        let errorOutput = (try? String(contentsOf: errorURL, encoding: .utf8)) ?? ""

        guard process.terminationStatus == 0 else {
            let message = errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            return .failure(message.isEmpty ? output : message)
        }

        return .success(output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func commandExitStatus(_ executable: String, arguments: [String]) -> Int32? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        guard waitForExit(process, timeout: 1.0) else {
            process.terminate()
            return nil
        }

        return process.terminationStatus
    }

    private static func waitForExit(_ process: Process, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            if Date() >= deadline {
                return false
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        process.waitUntilExit()
        return true
    }
}
