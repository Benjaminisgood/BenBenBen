import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppModel.shared.start()

        // Settings restoration can otherwise put an ordinary window in front
        // of the dragon after a crash or relaunch. Startup always returns to
        // the notch-only product surface; user-opened artifact windows are not
        // affected after this short restoration window.
        for delay in [0.10, 0.50, 1.25] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                Self.hideRestoredWindows()
            }
        }

        if CommandLine.arguments.contains("--ui-test-expanded")
            || ProcessInfo.processInfo.environment["BENBENBEN_UI_TEST_EXPANDED"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                AppModel.shared.showAgent()
            }
        }
        if ProcessInfo.processInfo.environment["BENBENBEN_UI_TEST_ARTIFACTS"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                AppModel.shared.showArtifactWindows()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private static func hideRestoredWindows() {
        NSApp.windows
            .filter { !($0 is NotchPanel) }
            .forEach { window in
                window.isRestorable = false
                window.orderOut(nil)
            }
    }
}
