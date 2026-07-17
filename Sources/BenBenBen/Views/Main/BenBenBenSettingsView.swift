import AppKit
import SwiftUI

struct BenBenBenSettingsView: View {
    @ObservedObject var voiceInteraction: VoiceInteractionController
    @ObservedObject var runtimeCatalog: RuntimeCatalogStore
    @ObservedObject var loginItemStore: LoginItemStore
    @ObservedObject var notchPreferences: NotchPreferences
    @EnvironmentObject private var model: AppModel

    @AppStorage("benbenben.codexExecutable") private var codexExecutable = ""
    @State private var workspacePath = WorkspacePaths.root.path

    var body: some View {
        TabView {
            companionPage
                .tabItem { Label("Ben龙", systemImage: "sparkles") }

            permissionsPage
                .tabItem { Label("权限", systemImage: "lock.shield") }

            codexPage
                .tabItem { Label("Codex", systemImage: "terminal") }

            runtimePage
                .tabItem { Label("Runtime", systemImage: "shippingbox") }
        }
        .frame(width: 760, height: 600)
        .onAppear { workspacePath = WorkspacePaths.root.path }
    }

    private var companionPage: some View {
        SettingsPage(
            title: "Ben龙",
            subtitle: "调整陪伴方式、刘海尺寸和长期工作空间。",
            systemImage: "sparkles"
        ) {
            SettingsCard("行为", systemImage: "wand.and.stars") {
                SettingsToggleRow(
                    title: "登录后自动启动",
                    detail: loginItemStore.statusText,
                    isOn: Binding(
                        get: { loginItemStore.isEnabled },
                        set: { loginItemStore.setEnabled($0) }
                    )
                )
                if let error = loginItemStore.lastError {
                    SettingsNotice(text: error, color: .red)
                }

                SettingsDivider()

                SettingsRow(
                    title: "活跃程度",
                    detail: model.activityLevel.detail
                ) {
                    Picker("", selection: $model.activityLevel) {
                        ForEach(CompanionActivityLevel.allCases) { level in
                            Text(level.title).tag(level)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }
            }

            SettingsCard("物理刘海", systemImage: "laptopcomputer") {
                SettingsRow(title: "宽度", detail: "匹配屏幕物理刘海") {
                    Stepper(
                        "\(Int(notchPreferences.physicalWidth)) pt",
                        value: $notchPreferences.physicalWidth,
                        in: NotchPreferences.physicalWidthRange,
                        step: 1
                    )
                    .monospacedDigit()
                }
                SettingsDivider()
                SettingsRow(title: "高度", detail: "决定活动区的起始位置") {
                    Stepper(
                        "\(Int(notchPreferences.physicalHeight)) pt",
                        value: $notchPreferences.physicalHeight,
                        in: NotchPreferences.physicalHeightRange,
                        step: 1
                    )
                    .monospacedDigit()
                }
                SettingsDivider()
                SettingsRow(title: "面板总高", detail: "物理高度 + 108 pt 固定活动区") {
                    Text("\(Int(notchPreferences.physicalHeight + NotchGeometry.companionContentHeight)) pt")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                SettingsDivider()
                HStack {
                    Text("活动区不会因任务内容改变大小。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("恢复默认 184 × 32") { notchPreferences.restoreDefaults() }
                }
            }

            SettingsCard("永久内容目录", systemImage: "folder") {
                Text(workspacePath)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack {
                    Text("HTML、Markdown、Python、脚本、launchd 配置与新任务都使用此目录。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("恢复默认") {
                        model.updateWorkspaceRoot(nil)
                        workspacePath = WorkspacePaths.root.path
                    }
                    Button("选择目录…", action: chooseWorkspace)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private var permissionsPage: some View {
        SettingsPage(
            title: "权限与语音",
            subtitle: "控制任务执行边界，以及 Ben龙可以听到和看到什么。",
            systemImage: "lock.shield"
        ) {
            SettingsCard("任务执行", systemImage: "checkmark.shield") {
                SettingsRow(
                    title: "统一执行权限",
                    detail: executionModeBinding.wrappedValue.detail
                ) {
                    Picker("", selection: executionModeBinding) {
                        ForEach(AgentTaskExecutionMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 170)
                }
            }

            SettingsCard("语音", systemImage: "waveform") {
                SettingsStatusRow(title: "麦克风", value: voiceInteraction.microphonePermissionLabel)
                SettingsDivider()
                SettingsStatusRow(title: "语音识别", value: voiceInteraction.speechPermissionLabel)
                SettingsDivider()
                SettingsStatusRow(
                    title: "当前状态",
                    value: voiceInteraction.isRecording
                        ? "正在聆听"
                        : (voiceInteraction.isConversationEnabled ? "即将恢复" : "已暂停")
                )
                SettingsDivider()
                SettingsToggleRow(
                    title: "任务完成后读出结果",
                    detail: "仅在活跃语音通话中播报",
                    isOn: $voiceInteraction.speaksVoiceReplies
                )
                HStack {
                    Text("点击 Ben龙开始或暂停持续对话；按住说话，松开发送。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("请求语音权限") {
                        Task { _ = await voiceInteraction.requestPermissions() }
                    }
                }
            }

            SettingsCard("屏幕上下文", systemImage: "rectangle.inset.filled.and.person.filled") {
                SettingsToggleRow(
                    title: "允许口头指令启动",
                    detail: "只有在你明确说“看我的屏幕”一类口令后才开始共享",
                    isOn: Binding(
                        get: { model.screenContext.allowsVoiceActivation },
                        set: { model.screenContext.allowsVoiceActivation = $0 }
                    )
                )
                SettingsDivider()
                SettingsStatusRow(title: "本次共享", value: model.screenContext.status.label)
                if model.screenContext.isEnabled {
                    HStack {
                        Spacer()
                        Button("停止本次屏幕共享", role: .destructive) {
                            model.screenContext.disableSharing()
                        }
                    }
                }
            }
        }
    }

    private var codexPage: some View {
        SettingsPage(
            title: "Codex",
            subtitle: "Codex 是负责理解请求、编写代码和执行任务的智能代理。",
            systemImage: "terminal"
        ) {
            SettingsCard("连接", systemImage: "point.3.connected.trianglepath.dotted") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("可执行文件")
                        .font(.headline)
                    TextField("留空时自动选择最新版本", text: $codexExecutable)
                        .textFieldStyle(.roundedBorder)
                    Text("通常保持为空即可；仅在需要固定某个 Codex 安装时填写完整路径。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            SettingsCard("任务环境", systemImage: "folder.badge.gearshape") {
                SettingsRow(title: "当前工作目录", detail: "Codex 新任务的默认起点") {
                    Text(WorkspacePaths.root.path)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 330)
                        .textSelection(.enabled)
                }
                SettingsDivider()
                SettingsStatusRow(title: "任务策略", value: executionModeBinding.wrappedValue.title)
            }

            SettingsNotice(
                text: "Codex 决定“怎么完成任务”；Runtime 提供“这台 Mac 上有哪些固定工具可以安全调用”。",
                color: .accentColor
            )
        }
    }

    private var runtimePage: some View {
        SettingsPage(
            title: "Runtime",
            subtitle: "BenBenBen 随应用携带的本地工具箱，为 Codex 提供经过定义和分级的固定操作。",
            systemImage: "shippingbox"
        ) {
            SettingsCard("运行状态", systemImage: "checkmark.circle") {
                HStack(spacing: 14) {
                    Image(systemName: runtimeCatalog.lastError == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(runtimeCatalog.lastError == nil ? .green : .orange)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(runtimeCatalog.lastError == nil ? "Runtime 已就绪" : "Runtime 不可用")
                            .font(.headline)
                        Text("版本 \(runtimeCatalog.version) · \(runtimeCatalog.actions.count) 个可用操作")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("重新加载") { runtimeCatalog.reload() }
                }
                if let error = runtimeCatalog.lastError {
                    SettingsNotice(text: error, color: .red)
                }
            }

            SettingsCard("它负责什么", systemImage: "wrench.and.screwdriver") {
                RuntimeResponsibilityRow(
                    icon: "list.bullet.clipboard",
                    title: "声明固定操作",
                    detail: "从 manifest.json 读取操作名称、参数与风险级别。"
                )
                SettingsDivider()
                RuntimeResponsibilityRow(
                    icon: "terminal",
                    title: "提供本地命令与 Shell 环境",
                    detail: "包含 benbenben 命令、MCP helper 和当前 Benshell。"
                )
                SettingsDivider()
                RuntimeResponsibilityRow(
                    icon: "hand.raised",
                    title: "约束执行边界",
                    detail: "区分只读、写入与执行操作，需要时交给权限策略审批。"
                )
            }

            SettingsCard("位置", systemImage: "externaldrive") {
                SettingsPathRow(title: "Runtime 根目录", path: runtimeCatalog.runtimeRoot.path)
                SettingsDivider()
                SettingsPathRow(title: "MCP helper", path: WorkspacePaths.mcpHelper.path)
            }
        }
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

private struct SettingsPage<Content: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    Image(systemName: systemImage)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.tint)
                        .frame(width: 46, height: 46)
                        .background(.tint.opacity(0.12), in: .rect(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).font(.title2.bold())
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    init(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.primary)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: .rect(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).stroke(.separator.opacity(0.45), lineWidth: 1) }
    }
}

private struct SettingsRow<Trailing: View>: View {
    let title: String
    let detail: String?
    @ViewBuilder let trailing: Trailing

    init(title: String, detail: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.detail = detail
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 20)
            trailing
        }
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(title: title, detail: detail) {
            Toggle("", isOn: $isOn).labelsHidden()
        }
    }
}

private struct SettingsStatusRow: View {
    let title: String
    let value: String

    var body: some View {
        SettingsRow(title: title) {
            Text(value).foregroundStyle(.secondary)
        }
    }
}

private struct SettingsPathRow: View {
    let title: String
    let path: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
            Text(path)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(2)
        }
    }
}

private struct RuntimeResponsibilityRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct SettingsNotice: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(color)
            .textSelection(.enabled)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.08), in: .rect(cornerRadius: 8))
    }
}

private struct SettingsDivider: View {
    var body: some View { Divider().opacity(0.65) }
}
