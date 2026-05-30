import Combine
import Foundation

struct CondaEnvironment: Identifiable, Equatable, Sendable {
    var id: String { name }
    let name: String
    let path: String
    let isActive: Bool
    let isFrozen: Bool

    var url: URL {
        URL(fileURLWithPath: path, isDirectory: true)
    }

    var displayName: String {
        var labels = [name]
        if isActive {
            labels.append("active")
        }
        if isFrozen {
            labels.append("frozen")
        }
        return labels.joined(separator: " ")
    }
}

struct PythonLaunchConfiguration: Equatable {
    let sessionKey: String
    let executablePath: String
    let arguments: [String]
    let environment: [String: String]
}

@MainActor
final class CondaEnvironmentStore: ObservableObject {
    @Published private(set) var environments: [CondaEnvironment] = []
    @Published private(set) var selectedEnvironmentName: String
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastError: String?

    private static let selectedEnvironmentKey = "notchwow.selectedCondaEnvironment"
    private static let legacySelectedEnvironmentKey = "notchNotes.selectedCondaEnvironment"

    init() {
        selectedEnvironmentName = AppDefaults.string(forKey: Self.selectedEnvironmentKey, migrating: Self.legacySelectedEnvironmentKey)
            ?? "base"
        refresh()
    }

    var selectedEnvironment: CondaEnvironment? {
        environments.first { $0.name == selectedEnvironmentName }
    }

    var condaExecutablePath: String {
        resolveCondaExecutable()
    }

    func select(_ name: String) {
        selectedEnvironmentName = name
        AppDefaults.set(name, forKey: Self.selectedEnvironmentKey, removing: Self.legacySelectedEnvironmentKey)
    }

    func refresh() {
        guard !isRefreshing else { return }

        isRefreshing = true
        lastError = nil
        let condaBin = condaExecutablePath
        let currentSelection = selectedEnvironmentName

        DispatchQueue.global(qos: .userInitiated).async {
            let result = Self.loadEnvironments(condaBin: condaBin)

            Task { @MainActor in
                self.isRefreshing = false

                switch result {
                case .success(let loadedEnvironments):
                    self.environments = loadedEnvironments

                    if loadedEnvironments.contains(where: { $0.name == currentSelection }) {
                        self.select(currentSelection)
                    } else if let activeEnvironment = loadedEnvironments.first(where: \.isActive) {
                        self.select(activeEnvironment.name)
                    } else if let firstEnvironment = loadedEnvironments.first {
                        self.select(firstEnvironment.name)
                    }

                case .failure(let error):
                    self.lastError = error.localizedDescription
                }
            }
        }
    }

    func condaCommand(_ arguments: String) -> String {
        "\(condaExecutablePath.shellEscaped) \(arguments)"
    }

    func runPythonFileDisplayCommand(filePath: String) -> String {
        URL(fileURLWithPath: filePath).lastPathComponent
    }

    func pythonLaunchConfiguration(bridgeScript: String) -> PythonLaunchConfiguration {
        if let pythonExecutablePath {
            var environment = ["PYTHONUNBUFFERED": "1"]

            if let selectedEnvironmentPath {
                let binPath = URL(fileURLWithPath: selectedEnvironmentPath, isDirectory: true)
                    .appendingPathComponent("bin", isDirectory: true)
                    .path
                let inheritedPath = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
                environment["CONDA_PREFIX"] = selectedEnvironmentPath
                environment["PATH"] = "\(binPath):\(inheritedPath)"
            }

            return PythonLaunchConfiguration(
                sessionKey: "\(selectedEnvironmentName)|\(pythonExecutablePath)",
                executablePath: pythonExecutablePath,
                arguments: ["-u", "-c", bridgeScript],
                environment: environment
            )
        }

        let condaBin = condaExecutablePath
        let condaArguments = [
            "run",
            "--no-capture-output",
            "-n",
            selectedEnvironmentName,
            "python",
            "-u",
            "-c",
            bridgeScript
        ]

        if condaBin.hasPrefix("/") {
            return PythonLaunchConfiguration(
                sessionKey: "\(selectedEnvironmentName)|\(condaBin)",
                executablePath: condaBin,
                arguments: condaArguments,
                environment: ["PYTHONUNBUFFERED": "1"]
            )
        }

        return PythonLaunchConfiguration(
            sessionKey: "\(selectedEnvironmentName)|env:\(condaBin)",
            executablePath: "/usr/bin/env",
            arguments: [condaBin] + condaArguments,
            environment: ["PYTHONUNBUFFERED": "1"]
        )
    }

    private var selectedEnvironmentPath: String? {
        if let selectedEnvironment {
            return selectedEnvironment.path
        }

        if selectedEnvironmentName == "base" {
            return condaRootURL.path
        }

        let inferredPath = condaRootURL
            .appendingPathComponent("envs", isDirectory: true)
            .appendingPathComponent(selectedEnvironmentName, isDirectory: true)
            .path
        guard FileManager.default.fileExists(atPath: inferredPath) else { return nil }
        return inferredPath
    }

    private var pythonExecutablePath: String? {
        guard let selectedEnvironmentPath else { return nil }
        let path = URL(fileURLWithPath: selectedEnvironmentPath, isDirectory: true)
            .appendingPathComponent("bin/python", isDirectory: false)
            .path
        guard FileManager.default.isExecutableFile(atPath: path) else { return nil }
        return path
    }

    var condaRootURL: URL {
        WorkspacePaths.condaRoot
    }

    private func resolveCondaExecutable() -> String {
        let preferredPath = WorkspacePaths.condaExecutable.path
        if FileManager.default.isExecutableFile(atPath: preferredPath) {
            return preferredPath
        }

        return "conda"
    }

    private nonisolated static func loadEnvironments(condaBin: String) -> Result<[CondaEnvironment], Error> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "\(condaBin.shellEscaped) info --envs"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            guard process.terminationStatus == 0 else {
                throw CondaEnvironmentError.commandFailed(output.trimmingCharacters(in: .whitespacesAndNewlines))
            }

            return .success(parseEnvironments(from: output))
        } catch {
            return .failure(error)
        }
    }

    private nonisolated static func parseEnvironments(from output: String) -> [CondaEnvironment] {
        output
            .components(separatedBy: .newlines)
            .compactMap(parseEnvironmentLine)
    }

    private nonisolated static func parseEnvironmentLine(_ line: String) -> CondaEnvironment? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }

        let parts = trimmed
            .split { $0 == " " || $0 == "\t" }
            .map(String.init)

        guard let path = parts.last, path.hasPrefix("/") else { return nil }
        let statusMarkers = Set(["*", "+"])
        let name = parts.first { !statusMarkers.contains($0) }
            ?? URL(fileURLWithPath: path).lastPathComponent

        return CondaEnvironment(
            name: name,
            path: path,
            isActive: parts.contains("*"),
            isFrozen: parts.contains("+")
        )
    }
}

enum CondaEnvironmentError: LocalizedError {
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let output):
            return output.isEmpty ? "conda info --envs failed" : output
        }
    }
}
