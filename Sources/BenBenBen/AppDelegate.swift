import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let companionOnly = CommandLine.arguments.contains("--companion-only")
        NSApp.setActivationPolicy(companionOnly ? .accessory : .regular)
        if !companionOnly {
            NSApp.activate(ignoringOtherApps: true)
        }
        AppModel.shared.start()

        if companionOnly {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                NSApp.windows
                    .filter { $0.title == "BenBenBen" }
                    .forEach { $0.orderOut(nil) }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
