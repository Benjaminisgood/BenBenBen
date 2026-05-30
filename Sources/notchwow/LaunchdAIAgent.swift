import Combine
import Foundation

@MainActor
final class LaunchdAIAgent: ObservableObject {
    @Published var input: String = ""
    @Published private(set) var lastMessage: String = ""
    @Published private(set) var generatedPlist: String?
    @Published private(set) var isRunning: Bool = false

    private var task: Task<Void, Never>?

    var canSubmit: Bool {
        !isRunning && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func submit(settings: AppSettingsStore, context: LaunchdAIContext) {
        let question = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isRunning else { return }

        let apiKey = settings.bailianAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = settings.bailianModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            lastMessage = "请先在设置中配置百炼 API Key。"
            return
        }
        guard !model.isEmpty else {
            lastMessage = "请先在设置中配置百炼模型。"
            return
        }

        input = ""
        isRunning = true
        generatedPlist = nil

        task?.cancel()
        task = Task { [weak self] in
            do {
                let reply = try await LaunchdAIClient.chat(
                    apiKey: apiKey,
                    model: model,
                    userMessage: question,
                    context: context
                )

                await MainActor.run {
                    guard let self, !Task.isCancelled else { return }
                    self.handleReply(reply)
                    self.isRunning = false
                }
            } catch {
                await MainActor.run {
                    guard let self, !Task.isCancelled else { return }
                    self.lastMessage = "Error: \(error.localizedDescription)"
                    self.isRunning = false
                }
            }
        }
    }

    func cancel() {
        task?.cancel()
        isRunning = false
    }

    private func handleReply(_ reply: String) {
        // If reply contains a plist XML block, extract it
        if let plistContent = extractPlist(from: reply) {
            generatedPlist = plistContent
            // Extract message outside the plist block
            let message = reply
                .replacingOccurrences(of: plistContent, with: "")
                .replacingOccurrences(of: "```xml", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            lastMessage = message.isEmpty ? "已生成 plist 配置，已写入编辑器。" : message
        } else {
            lastMessage = reply
            generatedPlist = nil
        }
    }

    private func extractPlist(from text: String) -> String? {
        // Try to find XML plist content
        if let xmlStart = text.range(of: "<?xml"),
           let dictEnd = text.range(of: "</plist>", options: .backwards) {
            return String(text[xmlStart.lowerBound..<dictEnd.upperBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }
}

struct LaunchdAIContext {
    let existingJobs: [LaunchdJob]
    let availableShellScripts: [String]
    let availablePythonScripts: [String]
    let availableAppleScripts: [String]
    let selectedJob: LaunchdJob?
    let launchdPath: String
    let pythonExecutablePath: String
}

private enum LaunchdAIClient {
    static func chat(
        apiKey: String,
        model: String,
        userMessage: String,
        context: LaunchdAIContext
    ) async throws -> String {
        try await BailianChatClient.chat(
            apiKey: apiKey,
            model: model,
            messages: [
                BailianChatMessage(role: "system", content: systemPrompt(context: context)),
                BailianChatMessage(role: "user", content: userMessage)
            ]
        )
    }

    private static func systemPrompt(context: LaunchdAIContext) -> String {
        let shPath = WorkspacePaths.shellRoot.path
        let pyPath = WorkspacePaths.pythonRoot.path
        let asPath = WorkspacePaths.appleScriptRoot.path

        var scriptList = ""
        if !context.availableShellScripts.isEmpty {
            scriptList += "Shell 脚本 (在 \(shPath)/ 目录):\n"
            scriptList += context.availableShellScripts.map { "  - \($0)" }.joined(separator: "\n")
            scriptList += "\n"
        }
        if !context.availablePythonScripts.isEmpty {
            scriptList += "Python 脚本 (在 \(pyPath)/ 目录):\n"
            scriptList += context.availablePythonScripts.map { "  - \($0)" }.joined(separator: "\n")
            scriptList += "\n"
        }
        if !context.availableAppleScripts.isEmpty {
            scriptList += "AppleScript 脚本 (在 \(asPath)/ 目录，使用 /usr/bin/osascript 执行):\n"
            scriptList += context.availableAppleScripts.map { "  - \($0)" }.joined(separator: "\n")
            scriptList += "\n"
        }

        var jobList = ""
        if !context.existingJobs.isEmpty {
            jobList = "当前已有的 launchd 任务:\n"
            jobList += context.existingJobs.map { "  - \($0.label) (\($0.isLoaded ? "运行中" : "未加载"))" }.joined(separator: "\n")
            jobList += "\n"
        }

        var currentPlist = ""
        if let job = context.selectedJob {
            currentPlist = "当前选中的 plist 文件 (\(job.detail)):\n\(job.content)\n"
        }

        return """
        你是一个 macOS launchd 自动化任务配置助手。

        用户会用自然语言描述他们想要自动化的任务，你需要生成对应的 launchd plist 配置文件。

        规则:
        - 生成标准的 macOS launchd plist XML 格式
        - Label 使用 com.notchwow. 前缀
        - plist 文件存放在 \(context.launchdPath) 目录
        - Shell 脚本用 /bin/zsh 执行，Python 脚本用 \(context.pythonExecutablePath) 执行
        - AppleScript 脚本用 /usr/bin/osascript 执行完整脚本路径，例如 ProgramArguments = ["/usr/bin/osascript", "\(asPath)/脚本名.applescript"]
        - 如果用户提到的脚本在可用列表中，使用完整路径
        - 使用 StartInterval（秒数）或 StartCalendarInterval（日历时间）设置调度
        - 可以设置 StandardOutPath 和 StandardErrorPath 到 \(context.launchdPath) 目录下的 .log 文件
        - 直接输出完整的 plist XML 内容，不要用 markdown 代码块包裹
        - 如果用户只是提问而不是要求生成配置，正常回答即可
        - 回答语言跟随用户

        \(scriptList)
        \(jobList)
        \(currentPlist)
        """
    }
}
