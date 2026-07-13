import AppKit
import SwiftUI

@main
struct BenBenBenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        Settings {
            BenBenBenSettingsView(
                voiceInteraction: model.voiceInteraction,
                runtimeCatalog: model.runtimeCatalog,
                loginItemStore: model.loginItemStore
            )
                .environmentObject(model)
        }
        .restorationBehavior(.disabled)

        MenuBarExtra("BenBenBen", systemImage: "sparkles") {
            BenBenBenMenuBarView()
                .environmentObject(model)
        }
        .menuBarExtraStyle(.menu)
        .commands {
            CommandMenu("BenBenBen") {
                Button("Open Ben龙") {
                    model.showAgent()
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])

                Button("New Agent Thread") {
                    model.createAgentThread()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Divider()

                Button("Open five shared windows") {
                    model.showArtifactWindows()
                }

                Menu("Shared Windows") {
                    ForEach(AgentArtifactKind.allCases) { kind in
                        Button(kind.title) {
                            model.showArtifactWindow(kind)
                        }
                    }
                }
            }
        }
    }
}
