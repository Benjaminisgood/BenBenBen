import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: NotchPanelController?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        panelController = NotchPanelController()
        panelController?.showDocked()
        buildStatusItem()
        buildMenu()
    }

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "notchwow")
        item.button?.imagePosition = .imageOnly
        item.menu = makeStatusMenu()
        statusItem = item
    }

    private func buildMenu() {
        let rootItem = NSMenuItem(title: "notchwow", action: nil, keyEquivalent: "")
        rootItem.submenu = makeAppMenu()

        let workbenchItem = NSMenuItem(title: "Workbench", action: nil, keyEquivalent: "")
        workbenchItem.submenu = makeWorkbenchMenu()

        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editItem.submenu = makeEditMenu()

        let mainMenu = NSMenu()
        mainMenu.addItem(rootItem)
        mainMenu.addItem(workbenchItem)
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
    }

    private func makeAppMenu() -> NSMenu {
        let appMenu = NSMenu()
        appMenu.addItem(menuItem(title: "Show notchwow", action: #selector(showNotes), keyEquivalent: "0"))

        appMenu.addItem(menuItem(title: "Hide notchwow", action: #selector(hideNotes), keyEquivalent: "w"))

        appMenu.addItem(.separator())

        appMenu.addItem(menuItem(title: "Quit notchwow", action: #selector(quit), keyEquivalent: "q"))

        return appMenu
    }

    private func makeStatusMenu() -> NSMenu {
        let menu = makeAppMenu()
        menu.addItem(.separator())
        addWorkbenchItems(to: menu)
        return menu
    }

    private func makeWorkbenchMenu() -> NSMenu {
        let menu = NSMenu(title: "Workbench")
        addWorkbenchItems(to: menu)
        return menu
    }

    private func addWorkbenchItems(to menu: NSMenu) {
        menu.addItem(menuItem(title: "Show Markdown", action: #selector(showMarkdown), keyEquivalent: "1"))
        menu.addItem(menuItem(title: "Show Scripts", action: #selector(showScripts), keyEquivalent: "2"))
        menu.addItem(menuItem(title: "Show Python", action: #selector(showPython), keyEquivalent: "3"))
        menu.addItem(menuItem(title: "Show Launchd Jobs", action: #selector(showLaunchdJobs), keyEquivalent: "4"))

        menu.addItem(.separator())

        menu.addItem(menuItem(title: "New Markdown Note", action: #selector(newMarkdownNote), keyEquivalent: "n"))
        menu.addItem(
            menuItem(
                title: "New Python File",
                action: #selector(newPythonFile),
                keyEquivalent: "n",
                modifiers: [.command, .option]
            )
        )
        menu.addItem(
            menuItem(
                title: "New Shell Workspace",
                action: #selector(newShellWorkspace),
                keyEquivalent: "s",
                modifiers: [.command, .option]
            )
        )
        menu.addItem(
            menuItem(
                title: "New AppleScript File",
                action: #selector(newAppleScriptFile),
                keyEquivalent: "a",
                modifiers: [.command, .option]
            )
        )

        menu.addItem(.separator())

        menu.addItem(
            menuItem(
                title: "Run Python File",
                action: #selector(runPythonFile),
                keyEquivalent: "\r",
                modifiers: [.command, .shift]
            )
        )
        menu.addItem(
            menuItem(
                title: "Run Python Command",
                action: #selector(runPythonCommand),
                keyEquivalent: "\r",
                modifiers: [.command, .option]
            )
        )
    }

    private func makeEditMenu() -> NSMenu {
        let editMenu = NSMenu(title: "Edit")

        let undoItem = NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        undoItem.target = nil
        editMenu.addItem(undoItem)

        let redoItem = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        redoItem.target = nil
        editMenu.addItem(redoItem)

        editMenu.addItem(.separator())

        let cutItem = NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        cutItem.target = nil
        editMenu.addItem(cutItem)

        let copyItem = NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        copyItem.target = nil
        editMenu.addItem(copyItem)

        let pasteItem = NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        pasteItem.target = nil
        editMenu.addItem(pasteItem)

        editMenu.addItem(.separator())

        let selectAllItem = NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        selectAllItem.target = nil
        editMenu.addItem(selectAllItem)

        return editMenu
    }

    private func menuItem(
        title: String,
        action: Selector,
        keyEquivalent: String,
        modifiers: NSEvent.ModifierFlags = [.command]
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        item.keyEquivalentModifierMask = modifiers
        return item
    }

    @objc private func showNotes() {
        panelController?.expand(animated: true)
    }

    @objc private func hideNotes() {
        panelController?.collapse(animated: true)
    }

    @objc private func showMarkdown() {
        panelController?.showWorkbenchMode(.markdown)
    }

    @objc private func showScripts() {
        panelController?.showWorkbenchMode(.scripts)
    }

    @objc private func showPython() {
        panelController?.showWorkbenchMode(.python)
    }

    @objc private func showLaunchdJobs() {
        panelController?.showWorkbenchMode(.tasks)
    }

    @objc private func newMarkdownNote() {
        panelController?.newMarkdownNote()
    }

    @objc private func newPythonFile() {
        panelController?.newPythonFile()
    }

    @objc private func newShellWorkspace() {
        panelController?.newShellWorkspace()
    }

    @objc private func newAppleScriptFile() {
        panelController?.newAppleScriptFile()
    }

    @objc private func runPythonFile() {
        panelController?.runPythonFile()
    }

    @objc private func runPythonCommand() {
        panelController?.runPythonCommand()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
