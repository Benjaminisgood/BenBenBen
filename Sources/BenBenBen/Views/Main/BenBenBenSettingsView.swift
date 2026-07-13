import AppKit
import SwiftUI

struct BenBenBenSettingsView: View {
    @ObservedObject var voiceInteraction: VoiceInteractionController
    @ObservedObject var runtimeCatalog: RuntimeCatalogStore
    @ObservedObject var loginItemStore: LoginItemStore
    @EnvironmentObject private var model: AppModel

    @AppStorage("benbenben.codexExecutable") private var codexExecutable = ""
    @State private var workspacePath = WorkspacePaths.root.path

    var body: some View {
        TabView {
            Form {
                Toggle(
                    "登录 Mac 后启动 Ben龙",
                    isOn: Binding(
                        get: { loginItemStore.isEnabled },
                        set: { loginItemStore.setEnabled($0) }
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

                Picker("Ben龙活跃程度", selection: $model.activityLevel) {
                    ForEach(CompanionActivityLevel.allCases) { level in
                        Text(level.title).tag(level)
                    }
                }
                Text(model.activityLevel.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent("永久内容目录") {
                    HStack(spacing: 8) {
                        Text(workspacePath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                        Button("选择…", action: chooseWorkspace)
                        Button("默认") {
                            model.updateWorkspaceRoot(nil)
                            workspacePath = WorkspacePaths.root.path
                        }
                    }
                }
                Text("HTML、MD、PY、SCRIPTS、PLIST 与任务的新工作目录都会永久使用这里；切换目录后下次语音会从该目录继续。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .tabItem { Label("Ben龙", systemImage: "sparkles") }

            Form {
                Picker("统一执行权限", selection: executionModeBinding) {
                    ForEach(AgentTaskExecutionMode.allCases) { mode in
                        VStack(alignment: .leading) {
                            Text(mode.title)
                            Text(mode.detail)
                        }
                        .tag(mode)
                    }
                }
                Text(executionModeBinding.wrappedValue.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                LabeledContent("麦克风", value: voiceInteraction.microphonePermissionLabel)
                LabeledContent("语音识别", value: voiceInteraction.speechPermissionLabel)
                Button("请求语音权限") {
                    Task { _ = await voiceInteraction.requestPermissions() }
                }

                Toggle(
                    "允许口头指令启动屏幕共享",
                    isOn: Binding(
                        get: { model.screenContext.allowsVoiceActivation },
                        set: { model.screenContext.allowsVoiceActivation = $0 }
                    )
                )
                LabeledContent("当前屏幕状态", value: model.screenContext.status.label)
                if model.screenContext.isEnabled {
                    Button("立即停止本次屏幕共享", role: .destructive) {
                        model.screenContext.disableSharing()
                    }
                }

                Toggle("语音任务完成后读出结果", isOn: $voiceInteraction.speaksVoiceReplies)
                LabeledContent(
                    "当前语音",
                    value: voiceInteraction.isRecording
                        ? "正在聆听"
                        : (voiceInteraction.isConversationEnabled ? "即将恢复" : "已暂停")
                )
                Text("开始和暂停都直接点击 Ben龙。屏幕只有在你说“看我的屏幕”一类口令后才会共享。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .tabItem { Label("权限", systemImage: "lock.shield") }

            Form {
                TextField("Codex 可执行文件（默认自动选择最新版）", text: $codexExecutable)
                LabeledContent("当前工作目录", value: WorkspacePaths.root.path)
                LabeledContent("任务策略", value: executionModeBinding.wrappedValue.title)
            }
            .tabItem { Label("Codex", systemImage: "terminal") }

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
                Button("重新加载 Runtime") { runtimeCatalog.reload() }
            }
            .tabItem { Label("Runtime", systemImage: "shippingbox") }
        }
        .frame(width: 680, height: 470)
        .scenePadding()
        .onAppear { workspacePath = WorkspacePaths.root.path }
    }

    private var executionModeBinding: Binding<AgentTaskExecutionMode> {
        Binding(
            get: { model.agentStore?.defaultExecutionMode ?? AgentTaskExecutionMode.persistedDefault },
            set: { mode in
                UserDefaults.standard.set(mode.rawValue, forKey: "benbenben.agent.executionMode")
                model.agentStore?.defaultExecutionMode = mode
            }
        )
    }

    private func chooseWorkspace() {
        let panel = NSOpenPanel()
        panel.title = "选择 BenBenBen 永久内容目录"
        panel.prompt = "使用此目录"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = WorkspacePaths.root
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.updateWorkspaceRoot(url)
        workspacePath = WorkspacePaths.root.path
    }
}
