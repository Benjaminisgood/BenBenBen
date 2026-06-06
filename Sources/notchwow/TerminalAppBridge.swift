import Foundation

enum TerminalAppBridge {
    static func openNewWindow(workingDirectory: String) -> Bool {
        run(command: "", workingDirectory: workingDirectory)
    }

    static func run(
        command: String,
        workingDirectory: String,
        bootstrapURL: URL? = nil,
        environment: [String: String] = [:]
    ) -> Bool {
        var parts = ["cd -- \(workingDirectory.shellEscaped)"]

        let exports = environment
            .sorted { $0.key < $1.key }
            .map { key, value in "export \(key)=\(value.shellEscaped)" }
        parts.append(contentsOf: exports)

        if let bootstrapURL {
            parts.append("source \(bootstrapURL.path.shellEscaped)")
        }

        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCommand.isEmpty {
            parts.append(trimmedCommand)
        }

        let terminalCommand = parts.joined(separator: "; ")
        return runTerminalScript(terminalCommand)
    }

    private static func runTerminalScript(_ command: String) -> Bool {
        let escapedCommand = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = """
        tell application "Terminal"
            activate
            do script "\(escapedCommand)"
        end tell
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                return false
            }
            return true
        } catch {
            return false
        }
    }
}
