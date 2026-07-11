import Combine
import Foundation

enum RuntimeActionRisk: String, Codable, Sendable {
    case read
    case write
    case execute

    var requiresApproval: Bool { self != .read }
}

struct RuntimeActionManifest: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let summary: String
    let executable: String
    let arguments: [String]
    let cwd: String
    let risk: RuntimeActionRisk
    let inputSchema: AgentJSON
}

struct RuntimeManifestDocument: Codable, Sendable {
    let schemaVersion: Int
    let runtimeVersion: String
    let mcpHelper: String
    let actions: [RuntimeActionManifest]
}

@MainActor
final class RuntimeCatalogStore: ObservableObject {
    @Published private(set) var version = "Unknown"
    @Published private(set) var actions: [RuntimeActionManifest] = []
    @Published private(set) var runtimeRoot = WorkspacePaths.runtimeRoot
    @Published private(set) var lastError: String?

    init() {
        reload()
    }

    func reload() {
        runtimeRoot = WorkspacePaths.runtimeRoot
        let manifestURL = runtimeRoot.appendingPathComponent("manifest.json", isDirectory: false)
        do {
            let data = try Data(contentsOf: manifestURL)
            let manifest = try JSONDecoder().decode(RuntimeManifestDocument.self, from: data)
            guard manifest.schemaVersion == 1 else {
                throw RuntimeCatalogError.unsupportedSchema(manifest.schemaVersion)
            }
            version = manifest.runtimeVersion
            actions = manifest.actions
            lastError = nil
        } catch {
            version = "Unavailable"
            actions = []
            lastError = error.localizedDescription
        }
    }
}

private enum RuntimeCatalogError: LocalizedError {
    case unsupportedSchema(Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version):
            return "Unsupported Runtime manifest schema: \(version)"
        }
    }
}
