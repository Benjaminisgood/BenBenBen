import AppKit
import SwiftUI

struct BenBenBenMenuBarView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Button("Open Ben龙") {
            model.showNotch()
        }

        Divider()

        Button("Open five shared windows") { model.showArtifactWindows() }
        ForEach(AgentArtifactKind.allCases) { kind in
            Button(kind.title) { model.showArtifactWindow(kind) }
        }

        Divider()

        SettingsLink { Text("Settings…") }
        Button("Quit BenBenBen") {
            NSApp.terminate(nil)
        }
    }
}
