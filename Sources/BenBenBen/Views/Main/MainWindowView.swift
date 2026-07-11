import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
        } detail: {
            detail
                .inspector(isPresented: $model.isInspectorPresented) {
                    MainInspectorView()
                        .environmentObject(model)
                        .inspectorColumnWidth(min: 250, ideal: 290, max: 360)
                }
        }
        .searchable(text: $model.globalSearch, placement: .toolbar, prompt: "Search your world")
        .onChange(of: model.globalSearch) { _, query in
            model.personalWorkspace.query = query
            Task {
                await model.personalWorkspace.search()
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.showNotch()
                } label: {
                    Label("Ben龙", systemImage: "sparkles")
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.isInspectorPresented.toggle()
                } label: {
                    Label("Inspector", systemImage: "sidebar.right")
                }
            }
        }
    }

    private var sidebar: some View {
        List(selection: $model.selectedRoute) {
            Section("Now") {
                sidebarRow(.home)
                sidebarRow(.today)
                sidebarRow(.inbox)
            }

            Section("Agent") {
                sidebarRow(.agents)
            }

            Section("Library") {
                sidebarRow(.knowledge)
                sidebarRow(.scripts)
                sidebarRow(.python)
                sidebarRow(.automations)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("BenBenBen")
    }

    private func sidebarRow(_ route: MainRoute) -> some View {
        Label(route.title, systemImage: route.systemImage)
            .tag(route)
    }

    @ViewBuilder
    private var detail: some View {
        if !model.globalSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            PersonalSearchResultsView(store: model.personalWorkspace)
        } else {
            switch model.selectedRoute {
            case .home:
                HomeDashboardView(personal: model.personalWorkspace)
                    .environmentObject(model)
            case .today:
                PersonalTasksView(mode: .today, store: model.personalWorkspace)
            case .inbox:
                PersonalTasksView(mode: .inbox, store: model.personalWorkspace)
            case .agents:
                AgentRouteView()
                    .environmentObject(model)
            case .knowledge:
                MainWorkbenchView(mode: .markdown, environment: model.workbench)
            case .scripts:
                MainWorkbenchView(mode: .scripts, environment: model.workbench)
            case .python:
                MainWorkbenchView(mode: .python, environment: model.workbench)
            case .automations:
                MainWorkbenchView(mode: .tasks, environment: model.workbench)
            }
        }
    }
}

private struct HomeDashboardView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var personal: PersonalWorkspaceStore

    private let columns = [
        GridItem(.adaptive(minimum: 210, maximum: 320), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Good to see you, Ben")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("Your notes, tools, automations, and agents—together at last.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                GlassEffectContainer(spacing: 16) {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                        DashboardCard(
                            title: "Today",
                            value: "\(todayCount)",
                            detail: "due or overdue",
                            systemImage: "sun.max",
                            tint: .yellow
                        ) { model.selectedRoute = .today }

                        DashboardCard(
                            title: "Inbox",
                            value: "\(inboxCount)",
                            detail: "captured tasks",
                            systemImage: "tray",
                            tint: .pink
                        ) { model.selectedRoute = .inbox }

                        DashboardCard(
                            title: "Knowledge",
                            value: "\(personal.refreshSummary?.indexedFileCount ?? 0)",
                            detail: "indexed personal files",
                            systemImage: "books.vertical",
                            tint: .mint
                        ) { model.selectedRoute = .knowledge }

                        DashboardCard(
                            title: "Tools",
                            value: "\(model.workbench.shellCommandStore.commands.count)",
                            detail: "discoverable actions",
                            systemImage: "terminal",
                            tint: .blue
                        ) { model.selectedRoute = .scripts }

                        DashboardCard(
                            title: "Python",
                            value: "\(model.workbench.pythonStore.files.count)",
                            detail: "personal scripts",
                            systemImage: "chevron.left.forwardslash.chevron.right",
                            tint: .purple
                        ) { model.selectedRoute = .python }

                        DashboardCard(
                            title: "Automations",
                            value: "\(model.workbench.launchdJobStore.loadedJobs.count)",
                            detail: "active jobs",
                            systemImage: "clock.arrow.2.circlepath",
                            tint: .orange
                        ) { model.selectedRoute = .automations }
                    }
                }

                HStack(spacing: 12) {
                    Button {
                        model.selectedRoute = .agents
                    } label: {
                        Label("Ask Ben龙", systemImage: "sparkles")
                            .frame(minWidth: 150)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)

                    Button("Open notch companion") {
                        model.showNotch()
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                }
            }
            .frame(maxWidth: 980, alignment: .leading)
            .padding(32)
        }
        .navigationTitle("Home")
    }

    private var todayCount: Int {
        let calendar = Calendar.current
        return personal.tasks.filter { task in
            guard !task.isCompleted, let dueDate = task.dueDate else { return false }
            return dueDate < calendar.startOfDay(for: Date()).addingTimeInterval(86_400)
        }.count
    }

    private var inboxCount: Int {
        personal.tasks.filter {
            !$0.isCompleted && $0.sourceURL.standardizedFileURL == personal.registry.inboxURL.standardizedFileURL
        }.count
    }
}

private struct DashboardCard: View {
    let title: String
    let value: String
    let detail: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Image(systemName: systemImage)
                        .font(.title2)
                        .foregroundStyle(tint)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .foregroundStyle(.tertiary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(value)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    Text(title)
                        .font(.headline)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
            .padding(18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
    }
}

private struct MainWorkbenchView: View {
    let mode: WorkbenchMode
    @ObservedObject var environment: WorkbenchEnvironment

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                WorkbenchModeControl(workbenchState: environment.workbenchState)
                Spacer()
                WorkbenchTopToolsView(
                    workbenchState: environment.workbenchState,
                    scriptsState: environment.scriptsState,
                    noteStore: environment.noteStore,
                    fileLockStore: environment.fileLockStore,
                    editorInteractionState: environment.editorInteractionState,
                    pythonStore: environment.pythonStore,
                    appleScriptStore: environment.appleScriptStore,
                    shellCommandStore: environment.shellCommandStore,
                    shellWorkspaceStore: environment.shellWorkspaceStore,
                    launchdJobStore: environment.launchdJobStore,
                    terminalRunner: environment.terminalRunner,
                    pythonRunner: environment.pythonRunner,
                    appleScriptRunner: environment.appleScriptRunner
                )
                SettingsLink {
                    Image(systemName: "gearshape")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            GeometryReader { proxy in
                WorkbenchContentView(
                    workbenchState: environment.workbenchState,
                    scriptsState: environment.scriptsState,
                    store: environment.noteStore,
                    settingsStore: environment.settingsStore,
                    imageStore: environment.imageStore,
                    markdownAIStore: environment.markdownAIStore,
                    markdownAIChatStore: environment.markdownAIChatStore,
                    fileLockStore: environment.fileLockStore,
                    editorInteractionState: environment.editorInteractionState,
                    pythonStore: environment.pythonStore,
                    appleScriptStore: environment.appleScriptStore,
                    shellCommandStore: environment.shellCommandStore,
                    shellWorkspaceStore: environment.shellWorkspaceStore,
                    launchdJobStore: environment.launchdJobStore,
                    launchdAIAgent: environment.launchdAIAgent,
                    shellAIStore: environment.shellAIStore,
                    pythonAIStore: environment.pythonAIStore,
                    appleScriptAIStore: environment.appleScriptAIStore,
                    condaStore: environment.condaStore,
                    directoryStore: environment.directoryStore,
                    terminalRunner: environment.terminalRunner,
                    pythonRunner: environment.pythonRunner,
                    appleScriptRunner: environment.appleScriptRunner,
                    size: proxy.size
                )
            }
            .clipShape(.rect(cornerRadius: 14))
            .padding([.horizontal, .bottom], 12)
        }
        .navigationTitle(mode.title)
        .onAppear {
            environment.workbenchState.select(mode)
        }
        .onChange(of: mode) { _, next in
            environment.workbenchState.select(next)
        }
    }
}

private struct MainInspectorView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if model.selectedRoute == .agents, let store = model.agentStore {
                AgentInspectorView(store: store)
            } else {
                Form {
                    Section("Selection") {
                        LabeledContent("Area", value: model.selectedRoute.title)
                        LabeledContent("Workspace", value: "~/keyoti")
                    }

                    Section("Safety") {
                        Label("Reads are automatic", systemImage: "eye")
                        Label("Writes show a diff", systemImage: "doc.text.magnifyingglass")
                        Label("Commands require approval", systemImage: "hand.raised")
                    }

                    Section("Runtime") {
                        LabeledContent("Codex", value: "External CLI")
                        LabeledContent("Policy", value: "On request")
                    }
                }
                .formStyle(.grouped)
                .padding(.top, 8)
            }
        }
    }
}
