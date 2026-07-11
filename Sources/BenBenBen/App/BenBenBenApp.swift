import AppKit
import SwiftUI

@main
struct BenBenBenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        WindowGroup("BenBenBen", id: "main") {
            MainWindowView()
                .environmentObject(model)
                .frame(minWidth: 980, minHeight: 680)
        }
        .defaultSize(width: 1240, height: 820)
        .commands {
            CommandMenu("BenBenBen") {
                Button("Open Ben龙") {
                    model.showNotch()
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])

                Button("New Agent Thread") {
                    model.selectedRoute = .agents
                    model.showMainWindow()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Divider()

                Button("Toggle Inspector") {
                    model.isInspectorPresented.toggle()
                }
                .keyboardShortcut("i", modifiers: [.command, .option])
            }
        }

        Settings {
            BenBenBenSettingsView(
                settingsStore: model.workbench.settingsStore,
                voiceInteraction: model.voiceInteraction,
                runtimeCatalog: model.runtimeCatalog,
                loginItemStore: model.loginItemStore
            )
                .environmentObject(model)
        }

        MenuBarExtra("BenBenBen", systemImage: "sparkles") {
            BenBenBenMenuBarView()
                .environmentObject(model)
        }
        .menuBarExtraStyle(.menu)
    }
}
