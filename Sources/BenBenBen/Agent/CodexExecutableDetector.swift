import Foundation

enum CodexExecutableDetector {
    static func detect(
        preferredPath: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) async throws -> CodexInstallation {
        let candidates = candidateURLs(preferredPath: preferredPath, environment: environment)

        if let preferredPath, !preferredPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let candidate = candidates.first else {
                throw CodexBridgeError.executableNotRunnable(preferredPath)
            }
            return try await probe(candidate)
        }

        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate.path) {
            if let installation = try? await probe(candidate) {
                return installation
            }
        }
        throw CodexBridgeError.executableNotFound
    }

    static func probe(_ executableURL: URL) async throws -> CodexInstallation {
        let url = executableURL.standardizedFileURL.resolvingSymlinksInPath()
        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            throw CodexBridgeError.executableNotRunnable(url.path)
        }

        return try await Task.detached(priority: .userInitiated) {
            try probeSynchronously(url)
        }.value
    }

    static func parseVersion(from output: String) -> String? {
        let pattern = #"(?<![0-9])([0-9]+\.[0-9]+\.[0-9]+(?:[-+][A-Za-z0-9.-]+)?)"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        guard let match = expression.firstMatch(in: output, range: range),
              let versionRange = Range(match.range(at: 1), in: output)
        else {
            return nil
        }
        return String(output[versionRange])
    }

    private static func candidateURLs(
        preferredPath: String?,
        environment: [String: String]
    ) -> [URL] {
        if let preferredPath, !preferredPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return [URL(fileURLWithPath: (preferredPath as NSString).expandingTildeInPath)]
        }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var paths: [String] = []
        if let configured = environment["CODEX_EXECUTABLE"], !configured.isEmpty {
            paths.append(configured)
        }
        if let configured = environment["CODEX_BIN"], !configured.isEmpty {
            paths.append(configured)
        }
        if let path = environment["PATH"] {
            paths.append(contentsOf: path.split(separator: ":").map { "\($0)/codex" })
        }
        paths.append(contentsOf: [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "\(home)/.local/bin/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "\(home)/Applications/Codex.app/Contents/Resources/codex"
        ])

        var seen: Set<String> = []
        return paths.compactMap { rawPath in
            let expanded = (rawPath as NSString).expandingTildeInPath
            let url = URL(fileURLWithPath: expanded).standardizedFileURL
            guard seen.insert(url.path).inserted else { return nil }
            return url
        }
    }

    private static func probeSynchronously(_ executableURL: URL) throws -> CodexInstallation {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = executableURL
        process.arguments = ["--version"]
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw CodexBridgeError.executableNotRunnable(executableURL.path)
        }
        process.waitUntilExit()

        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: outputData + errorData, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0, let version = parseVersion(from: output) else {
            throw CodexBridgeError.versionProbeFailed(path: executableURL.path, output: output)
        }
        return CodexInstallation(
            executableURL: executableURL,
            version: version,
            versionOutput: output
        )
    }
}
