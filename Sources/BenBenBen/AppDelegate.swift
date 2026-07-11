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
            for delay in [0.10, 0.50, 1.25] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    Self.hideWorkbenchWindowsForCompanionLaunch()
                }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private static func hideWorkbenchWindowsForCompanionLaunch() {
        NSApp.windows
            .filter { !($0 is NotchPanel) }
            .forEach { window in
                window.isRestorable = false
                window.orderOut(nil)
            }
    }
}
