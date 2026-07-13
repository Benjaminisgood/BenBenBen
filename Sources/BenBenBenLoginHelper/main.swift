import AppKit

@main
enum BenBenBenLoginHelperMain {
    static func main() {
        let application = NSApplication.shared
        let delegate = LoginHelperDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.prohibited)
        application.run()
    }
}

private final class LoginHelperDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let mainAppURL = Bundle.main.bundleURL
            .deletingLastPathComponent() // LoginItems
            .deletingLastPathComponent() // Library
            .deletingLastPathComponent() // Contents
            .deletingLastPathComponent() // BenBenBen.app

        guard mainAppURL.pathExtension == "app" else {
            NSApp.terminate(nil)
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        NSWorkspace.shared.openApplication(
            at: mainAppURL,
            configuration: configuration
        ) { _, _ in
            Task { @MainActor in
                NSApp.terminate(nil)
            }
        }
    }
}
