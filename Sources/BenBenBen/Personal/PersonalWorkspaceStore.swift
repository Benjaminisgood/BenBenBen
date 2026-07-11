import Combine
import Foundation

/// Main-actor facade for SwiftUI. It coordinates the derived search index with
/// task mutations while keeping file and database implementation details out of
/// views.
@MainActor
final class PersonalWorkspaceStore: ObservableObject {
    let registry: WorkspaceRegistry

    @Published var query = ""
    @Published private(set) var searchResults: [PersonalSearchResult] = []
    @Published private(set) var tasks: [PersonalTaskOccurrence] = []
    @Published private(set) var refreshSummary: PersonalIndexRefreshSummary?
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastError: String?

    private let searchIndex: PersonalSearchIndex
    private let taskService: PersonalTaskService

    init(
        registry: WorkspaceRegistry = WorkspaceRegistry(),
        databaseURL: URL? = nil,
        isLocked: @escaping PersonalTaskService.LockCheck = { FilePermissionLock.isLocked($0) }
    ) {
        self.registry = registry
        self.searchIndex = PersonalSearchIndex(
            databaseURL: databaseURL ?? Self.defaultDatabaseURL()
        )
        self.taskService = PersonalTaskService(registry: registry, isLocked: isLocked)
    }

    func refresh(forceReindex: Bool = false) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let loadedTasks = try taskService.loadTasks()
            let summary = try await searchIndex.refresh(registry: registry, force: forceReindex)
            tasks = loadedTasks
            refreshSummary = summary
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                searchResults = []
            } else {
                searchResults = try await searchIndex.search(query)
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func search() async {
        do {
            searchResults = try await searchIndex.search(query)
            lastError = nil
        } catch {
            searchResults = []
            lastError = error.localizedDescription
        }
    }

    @discardableResult
    func capture(_ draft: PersonalTaskDraft) async -> PersonalTaskOccurrence? {
        do {
            let occurrence = try taskService.capture(draft)
            tasks = try taskService.loadTasks()
            refreshSummary = try await searchIndex.refresh(registry: registry)
            lastError = nil
            return occurrence
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    @discardableResult
    func complete(_ task: PersonalTaskOccurrence) async -> PersonalTaskOccurrence? {
        do {
            let occurrence = try taskService.complete(task)
            tasks = try taskService.loadTasks()
            refreshSummary = try await searchIndex.refresh(registry: registry)
            lastError = nil
            return occurrence
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    private static func defaultDatabaseURL() -> URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return applicationSupport
            .appendingPathComponent("BenBenBen", isDirectory: true)
            .appendingPathComponent("PersonalIndex.sqlite3", isDirectory: false)
    }
}
