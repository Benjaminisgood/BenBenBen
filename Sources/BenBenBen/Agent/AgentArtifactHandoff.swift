import Foundation

struct AgentArtifact: Hashable, Sendable {
    let kind: AgentArtifactKind
    let url: URL
    let modifiedAt: Date
}

struct AgentArtifactSnapshot: Sendable {
    private struct Fingerprint: Equatable, Sendable {
        let kind: AgentArtifactKind
        let modifiedAt: Date
        let byteCount: Int
    }

    private let files: [String: Fingerprint]

    static func capture(
        locations: [(kind: AgentArtifactKind, roots: [URL])] = AgentArtifactKind.allCases.map {
            (kind: $0, roots: $0.roots)
        }
    ) -> AgentArtifactSnapshot {
        let manager = FileManager.default
        var files: [String: Fingerprint] = [:]

        for location in locations {
            for root in location.roots {
                guard let enumerator = manager.enumerator(
                    at: root,
                    includingPropertiesForKeys: [
                        .isRegularFileKey,
                        .contentModificationDateKey,
                        .fileSizeKey
                    ],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) else { continue }

                for case let url as URL in enumerator
                where location.kind.extensions.contains(url.pathExtension.lowercased()) {
                    guard let values = try? url.resourceValues(forKeys: [
                        .isRegularFileKey,
                        .contentModificationDateKey,
                        .fileSizeKey
                    ]),
                    values.isRegularFile == true else { continue }
                    files[url.standardizedFileURL.path] = Fingerprint(
                        kind: location.kind,
                        modifiedAt: values.contentModificationDate ?? .distantPast,
                        byteCount: values.fileSize ?? 0
                    )
                }
            }
        }
        return AgentArtifactSnapshot(files: files)
    }

    func changes(since baseline: AgentArtifactSnapshot) -> [AgentArtifact] {
        files.compactMap { path, fingerprint in
            guard baseline.files[path] != fingerprint else { return nil }
            return AgentArtifact(
                kind: fingerprint.kind,
                url: URL(fileURLWithPath: path),
                modifiedAt: fingerprint.modifiedAt
            )
        }
        .sorted { $0.modifiedAt > $1.modifiedAt }
    }
}

extension AgentArtifactKind {
    static func kind(containing url: URL) -> AgentArtifactKind? {
        let path = url.standardizedFileURL.path
        return allCases.first { kind in
            kind.extensions.contains(url.pathExtension.lowercased())
                && kind.roots.contains { root in
                    path == root.standardizedFileURL.path
                        || path.hasPrefix(root.standardizedFileURL.path + "/")
                }
        }
    }
}
