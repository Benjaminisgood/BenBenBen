import SwiftUI

struct BenBenBenSettingsView: View {
    @ObservedObject var settingsStore: AppSettingsStore
    @ObservedObject var voiceInteraction: VoiceInteractionController
    @ObservedObject var runtimeCatalog: RuntimeCatalogStore
    @ObservedObject var loginItemStore: LoginItemStore
    @EnvironmentObject private var model: AppModel

    @AppStorage("benbenben.codexExecutable") private var codexExecutable = "/opt/homebrew/bin/codex"

    var body: some View {
        TabView {
            Form {
                Picker("Notch trigger", selection: $settingsStore.triggerMode) {
                    ForEach(TriggerMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.systemImage)
                            .tag(mode)
                    }
                }
                Toggle(
                    "Launch companion at login",
                    isOn: Binding(
                        get: { loginItemStore.isEnabled },
                        set: { enabled in loginItemStore.setEnabled(enabled) }
                    )
                )
                Text(loginItemStore.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let error = loginItemStore.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
            .tabItem { Label("General", systemImage: "gearshape") }

            Form {
                TextField("Codex executable", text: $codexExecutable)
                LabeledContent("Default workspace", value: "~/keyoti")
                LabeledContent("Approval policy", value: "On request")
                LabeledContent("Sandbox", value: "Workspace write")
            }
            .tabItem { Label("Codex", systemImage: "sparkles") }

            Form {
                Toggle("Speak short voice-initiated replies", isOn: $voiceInteraction.speaksVoiceReplies)
                Toggle(
                    "Observe and react to screen changes",
                    isOn: Binding(
                        get: { model.screenContext.isEnabled },
                        set: { model.screenContext.isEnabled = $0 }
                    )
                )
                Text(model.screenContext.status.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LabeledContent(
                    "Speech recognition",
                    value: voiceInteraction.isRecording ? "Listening" : "On demand"
                )
                Text("Voice is push-to-talk. Screen observation is separately visible, can be stopped at any time, and only sends changed frames to Codex while enabled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .tabItem { Label("Voice", systemImage: "waveform") }

            Form {
                LabeledContent("Version", value: runtimeCatalog.version)
                LabeledContent("Actions", value: "\(runtimeCatalog.actions.count)")
                LabeledContent("Location", value: runtimeCatalog.runtimeRoot.path)
                LabeledContent("MCP helper", value: WorkspacePaths.mcpHelper.path)
                if let error = runtimeCatalog.lastError {
                    Text(error)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
                Button("Reload catalog") { runtimeCatalog.reload() }
            }
            .tabItem { Label("Runtime", systemImage: "shippingbox") }

            Form {
                SecureField("Legacy Bailian API key", text: $settingsStore.bailianAPIKey)
                TextField("Legacy model", text: $settingsStore.bailianModel)
                Text("This provider is kept only for compatibility. Codex is the primary agent runtime.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Import legacy notchwow Keychain item") {
                    settingsStore.migrateLegacyBailianKeychain()
                }
                .disabled(settingsStore.isMigratingLegacyKeychain)
                if settingsStore.isMigratingLegacyKeychain {
                    ProgressView("Waiting for Keychain…")
                }
                if let message = settingsStore.legacyKeychainMigrationMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tabItem { Label("Legacy", systemImage: "shippingbox") }
        }
        .frame(width: 580, height: 360)
        .scenePadding()
    }
}
