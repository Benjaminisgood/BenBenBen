import Foundation

enum CompanionActivityLevel: String, CaseIterable, Identifiable, Sendable {
    case quiet
    case collaborative
    case proactive
    case autonomous

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quiet: return "安静陪伴"
        case .collaborative: return "协作"
        case .proactive: return "主动"
        case .autonomous: return "自主"
        }
    }

    var detail: String {
        switch self {
        case .quiet: return "只回应口头指令，不主动弹出内容"
        case .collaborative: return "自动展示产物和需要你判断的任务"
        case .proactive: return "同时观察已授权的屏幕变化并及时提醒"
        case .autonomous: return "主动组织窗口、上下文与后续动作"
        }
    }

    var revealsArtifacts: Bool { self != .quiet }
    var revealsDecisions: Bool { self != .quiet }
    var reactsToScreenChanges: Bool { self == .proactive || self == .autonomous }

    static var persisted: CompanionActivityLevel {
        let value = UserDefaults.standard.string(forKey: "benbenben.companion.activityLevel")
        return value.flatMap(Self.init(rawValue:)) ?? .collaborative
    }
}

struct VoiceCommandIntent: Equatable, Sendable {
    enum ScreenAction: Equatable, Sendable {
        case enable
        case disable
    }

    let screenAction: ScreenAction?
    let artifactKind: AgentArtifactKind?
    let showsTaskWindow: Bool
    let isPureWindowCommand: Bool
    let isPureScreenCommand: Bool

    static func parse(_ text: String) -> VoiceCommandIntent {
        let normalized = normalize(text)
        let compact = String(normalized.filter { !$0.isWhitespace })
        let screenAction: ScreenAction?
        if containsAny(normalized, [
            "停止共享屏幕", "关闭屏幕共享", "别看屏幕", "不要看屏幕", "停止看屏幕", "取消共享屏幕"
        ]) {
            screenAction = .disable
        } else if containsAny(normalized, [
            "看我的屏幕", "看看我的屏幕", "看屏幕上", "屏幕上", "共享屏幕", "share my screen"
        ]) {
            screenAction = .enable
        } else {
            screenAction = nil
        }

        let artifactKind: AgentArtifactKind?
        if containsAny(compact, ["html", ".html", ".htm", "网页窗口", "报告窗口"]) {
            artifactKind = .html
        } else if containsAny(compact, ["python", ".py", "py窗口", "python窗口"]) {
            artifactKind = .python
        } else if containsAny(compact, ["markdown", ".md", "md窗口", "md文件", "笔记窗口"]) {
            artifactKind = .markdown
        } else if containsAny(compact, ["scripts", ".sh", ".zsh", ".applescript", "script窗口", "脚本窗口", "shell窗口", "applescript窗口"]) {
            artifactKind = .scripts
        } else if containsAny(compact, ["plist", "launchd窗口", "定时任务窗口", "job窗口"]) {
            artifactKind = .plist
        } else {
            artifactKind = nil
        }

        let showsTaskWindow = containsAny(normalized, [
            "任务窗口", "任务详情", "聊天窗口", "打开任务", "看看任务", "显示任务"
        ])
        let hasDisplayVerb = containsAny(normalized, [
            "打开", "显示", "切换到", "让我看", "看看", "调出", "open", "show"
        ])
        let hasWorkVerb = containsAny(normalized, [
            "修改", "创建", "新建", "分析", "解释", "为什么", "怎么", "帮我", "继续", "执行", "生成", "整理", "对比", "检查"
        ])
        let isPureWindowCommand = screenAction != .enable
            && hasDisplayVerb
            && !hasWorkVerb
            && (artifactKind != nil || showsTaskWindow)
        let isPureScreenCommand = screenAction == .disable
            && !hasWorkVerb
            && artifactKind == nil
            && !showsTaskWindow

        return VoiceCommandIntent(
            screenAction: screenAction,
            artifactKind: artifactKind,
            showsTaskWindow: showsTaskWindow,
            isPureWindowCommand: isPureWindowCommand,
            isPureScreenCommand: isPureScreenCommand
        )
    }

    private static func normalize(_ text: String) -> String {
        " " + text.lowercased()
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ") + " "
    }

    private static func containsAny(_ text: String, _ values: [String]) -> Bool {
        values.contains(where: text.contains)
    }
}
