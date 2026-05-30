import Foundation

enum SmokeTestFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message):
            return message
        }
    }
}

@main
struct LogicSmokeTests {
    static func main() throws {
        try testWorkspaceDefaultsUseCurrentHomeDirectory()
        try testSanitizedFileStemRemovesPathSeparatorsAndControlCharacters()
        try testUniquedFileURLAddsNumericSuffix()
        try testTerminalSummaryShortensCurrentHomeDirectory()
        try testLaunchdTemplateRoundTripsLabel()
        try testLaunchdLabelParserRejectsMalformedPropertyList()
        print("Logic smoke tests passed")
    }

    private static func testWorkspaceDefaultsUseCurrentHomeDirectory() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser

        try expect(
            WorkspacePaths.root.path == home.appendingPathComponent("keyoti").path,
            "Workspace root should use the current user's home directory"
        )
        try expect(
            WorkspacePaths.condaPythonExecutable.path
                == home.appendingPathComponent("miniforge3/bin/python").path,
            "Conda Python path should use the current user's home directory"
        )
    }

    private static func testSanitizedFileStemRemovesPathSeparatorsAndControlCharacters() throws {
        try expect(
            WorkspacePaths.sanitizedFileStem("  report/one:\nfinal  ") == "report-one--final",
            "Filename sanitization should replace separators and control characters"
        )
        try expect(
            WorkspacePaths.sanitizedFileStem(" ... ") == "Untitled",
            "Filename sanitization should use its fallback for empty names"
        )
    }

    private static func testUniquedFileURLAddsNumericSuffix() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let original = directory.appendingPathComponent("note.md")
        try Data().write(to: original)

        let next = WorkspacePaths.uniquedFileURL(
            stem: "note",
            fileExtension: "md",
            in: directory
        )
        try expect(next.lastPathComponent == "note 2.md", "Duplicate filenames should gain a numeric suffix")
    }

    private static func testTerminalSummaryShortensCurrentHomeDirectory() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        try expect(
            TerminalTaskStore.shortCommand("\(home)/Desktop/project/run.sh") == "~/Desktop/project/run.sh",
            "Terminal summaries should abbreviate the current Desktop path"
        )
        try expect(
            TerminalTaskStore.shortCommand("\(home)/project/run.sh") == "~/project/run.sh",
            "Terminal summaries should abbreviate the current home path"
        )
    }

    private static func testLaunchdTemplateRoundTripsLabel() throws {
        let label = "com.notchwow.test<&>"
        let template = LaunchdJobStore.plistTemplate(label: label)

        try expect(
            LaunchdJobStore.extractLabel(from: template) == label,
            "Launchd templates should escape and round-trip labels"
        )
    }

    private static func testLaunchdLabelParserRejectsMalformedPropertyList() throws {
        try expect(
            LaunchdJobStore.extractLabel(from: "<key>Label</key><string>broken") == nil,
            "Malformed property lists should not produce labels"
        )
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) throws {
        guard condition() else {
            throw SmokeTestFailure.failed(message)
        }
    }
}
