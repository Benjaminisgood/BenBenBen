import AppKit
import SwiftUI

struct BenBenBenMenuBarView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open BenBenBen") {
            openWindow(id: "main")
            model.showMainWindow()
        }

        Button("Open Ben龙") {
            model.showNotch()
        }

        Divider()

        Button("Knowledge") { model.showWorkbench(.markdown) }
        Button("Scripts") { model.showWorkbench(.scripts) }
        Button("Python") { model.showWorkbench(.python) }
        Button("Automations") { model.showWorkbench(.tasks) }

        Divider()

        SettingsLink { Text("Settings…") }
        Button("Quit BenBenBen") {
            NSApp.terminate(nil)
        }
    }
}
