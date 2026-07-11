import Foundation

enum FilePermissionLock {
    private static let originalModesKey = "benbenben.filePermissionLock.originalModes"

    static func isLocked(_ url: URL?) -> Bool {
        guard let url, FileManager.default.fileExists(atPath: url.path) else {
            return false
        }

        if isUserImmutable(url) {
            return true
        }

        guard let mode = try? permissionMode(at: url) else {
            return false
        }
        return mode & 0o222 == 0
    }

    static func lock(_ url: URL) throws {
        try requireExistingFile(url)
        let path = canonicalPath(for: url)
        var modes = originalModes()
        if modes[path] == nil {
            modes[path] = try permissionMode(at: url)
            saveOriginalModes(modes)
        }

        try runCommand("/bin/chmod", arguments: ["a-w", path])
        try runCommand("/usr/bin/chflags", arguments: ["uchg", path])
    }

    static func unlock(_ url: URL) throws {
        try requireExistingFile(url)
        let path = canonicalPath(for: url)
        try runCommand("/usr/bin/chflags", arguments: ["nouchg", path])

        var modes = originalModes()
        if let mode = modes[path] {
            try runCommand("/bin/chmod", arguments: [String(format: "%o", mode & 0o7777), path])
            modes.removeValue(forKey: path)
            saveOriginalModes(modes)
        } else {
            try runCommand("/bin/chmod", arguments: ["u+w", path])
        }
    }

    static func modificationBlockedMessage(for url: URL?, action: String) -> String? {
        guard let url else { return nil }
        guard isLocked(url) else { return nil }
        return "\(action) blocked: \(url.lastPathComponent) is locked. Unlock it from the top bar first."
    }

    private static func requireExistingFile(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw FilePermissionLockError.missingFile(url.path)
        }
    }

    private static func canonicalPath(for url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private static func permissionMode(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let mode = attributes[.posixPermissions] as? NSNumber else {
            throw FilePermissionLockError.missingPermissions(url.path)
        }
        return mode.intValue
    }

    private static func isUserImmutable(_ url: URL) -> Bool {
        if let values = try? url.resourceValues(forKeys: [.isUserImmutableKey]),
           values.isUserImmutable == true {
            return true
        }

        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return false
        }
        return (attributes[.immutable] as? Bool) == true
    }

    private static func originalModes() -> [String: Int] {
        let raw = AppDefaults.dictionary(
            forKey: originalModesKey,
            migrating: ["notchwow.filePermissionLock.originalModes"]
        ) ?? [:]
        var modes: [String: Int] = [:]
        for (path, value) in raw {
            if let intValue = value as? Int {
                modes[path] = intValue
            } else if let numberValue = value as? NSNumber {
                modes[path] = numberValue.intValue
            }
        }
        return modes
    }

    private static func saveOriginalModes(_ modes: [String: Int]) {
        UserDefaults.standard.set(modes, forKey: originalModesKey)
    }

    @discardableResult
    private static func runCommand(_ executablePath: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            throw FilePermissionLockError.commandFailed(
                command: ([URL(fileURLWithPath: executablePath).lastPathComponent] + arguments).joined(separator: " "),
                output: output
            )
        }
        return output
    }
}

@MainActor
final class FilePermissionLockStore: ObservableObject {
    @Published private(set) var lastError: String?
    @Published private var refreshToken = UUID()

    func isLocked(_ url: URL?) -> Bool {
        _ = refreshToken
        return FilePermissionLock.isLocked(url)
    }

    func toggle(_ url: URL?) {
        guard let url else {
            lastError = "No file selected to lock."
            refreshToken = UUID()
            return
        }

        do {
            if FilePermissionLock.isLocked(url) {
                try FilePermissionLock.unlock(url)
            } else {
                try FilePermissionLock.lock(url)
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        refreshToken = UUID()
    }

    func refresh() {
        refreshToken = UUID()
    }
}

private enum FilePermissionLockError: LocalizedError {
    case missingFile(String)
    case missingPermissions(String)
    case commandFailed(command: String, output: String)

    var errorDescription: String? {
        switch self {
        case .missingFile(let path):
            return "File does not exist: \(path)"
        case .missingPermissions(let path):
            return "Could not read POSIX permissions for \(path)."
        case .commandFailed(let command, let output):
            if output.isEmpty {
                return "Permission command failed: \(command)"
            }
            return "Permission command failed: \(command)\n\(output)"
        }
    }
}
