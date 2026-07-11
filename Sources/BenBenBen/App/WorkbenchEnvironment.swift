import Foundation

@MainActor
final class WorkbenchEnvironment: ObservableObject {
    let settingsStore = AppSettingsStore()
    let directoryStore = WorkspaceDirectoryStore()
    let markdownAIStore = MarkdownAIEditStore()
    let markdownAIChatStore = MarkdownAIChatStore()
    let fileLockStore = FilePermissionLockStore()
    let drawerState = DrawerState()
    let editorInteractionState = EditorInteractionState()
    let workbenchState = WorkbenchState()
    let scriptsState = ScriptsModuleState()
    let shellWorkspaceStore = ShellWorkspaceStore()
    let launchdJobStore = LaunchdJobStore()
    let launchdAIAgent = LaunchdAIAgent()
    let shellAIStore = ScriptAIEditStore()
    let pythonAIStore = ScriptAIEditStore()
    let appleScriptAIStore = ScriptAIEditStore()

    lazy var noteStore = NoteStore(markdownRoot: directoryStore.markdownWorkingDirectoryURL)
    lazy var imageStore = LocalImageStore(markdownRootURL: directoryStore.markdownWorkingDirectoryURL)
    lazy var shellCommandStore = ShellCommandStore(benshellRootURL: directoryStore.benshellRootDirectoryURL)
    lazy var condaStore = CondaEnvironmentStore(condaRootURL: directoryStore.condaRootDirectoryURL)

    let pythonStore = CodeFileStore(
        rootURL: WorkspacePaths.pythonRoot,
        fileExtension: "py",
        defaultTemplate: """
        # New script

        print("Hello from BenBenBen")
        """
    )

    let appleScriptStore = CodeFileStore(
        rootURL: WorkspacePaths.appleScriptRoot,
        fileExtension: "applescript",
        defaultTemplate: """
        -- title: New script

        return "Hello from BenBenBen"
        """,
        commentPrefix: "-- title: "
    )

    lazy var terminalRunner = CommandRunner(
        workingDirectory: directoryStore.shellWorkingDirectoryURL,
        input: "pwd",
        shellBootstrapURL: directoryStore.benshellInitScriptURL,
        environment: ["BENSHELL_HOME": directoryStore.benshellRootDirectoryURL.path],
        inputPersistenceURL: shellWorkspaceStore.activeWorkspace.inputURL,
        outputPersistenceURL: shellWorkspaceStore.activeWorkspace.transcriptURL,
        showsCommandTimestamps: true
    )

    let pythonRunner = PythonReplRunner(
        workingDirectory: WorkspacePaths.pythonRoot,
        outputPersistenceURL: WorkspacePaths.pythonOutputFile
    )

    lazy var appleScriptRunner = CommandRunner(
        workingDirectory: directoryStore.appleScriptDirectoryURL,
        input: "",
        shellBootstrapURL: nil,
        environment: [:],
        inputPersistenceURL: WorkspacePaths.appleScriptInputFile,
        outputPersistenceURL: WorkspacePaths.appleScriptOutputFile,
        showsCommandTimestamps: true
    )

    init() {
        WorkspacePaths.ensureDirectories()
    }
}
