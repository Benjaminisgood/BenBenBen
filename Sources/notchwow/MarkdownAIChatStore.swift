import Combine
import Foundation

struct AIChatMessage: Identifiable {
    let id = UUID()
    let role: AIChatRole
    let content: String
    let timestamp: Date

    init(role: AIChatRole, content: String, timestamp: Date = Date()) {
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}

enum AIChatRole: String {
    case user
    case assistant
}

@MainActor
final class MarkdownAIChatStore: ObservableObject {
    @Published var input = ""
    @Published private(set) var messages: [AIChatMessage] = []
    @Published private(set) var isRunning = false

    private var task: Task<Void, Never>?

    var canSubmit: Bool {
        !isRunning && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func submit(settings: AppSettingsStore, markdownContent: String, fileName: String) {
        let question = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isRunning else { return }

        let apiKey = settings.bailianAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = settings.bailianModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            messages.append(AIChatMessage(role: .assistant, content: "请先在设置中配置百炼 API Key。"))
            return
        }
        guard !model.isEmpty else {
            messages.append(AIChatMessage(role: .assistant, content: "请先在设置中配置百炼模型。"))
            return
        }

        let userMessage = AIChatMessage(role: .user, content: question)
        messages.append(userMessage)
        input = ""
        isRunning = true

        let history = messages
        task?.cancel()
        task = Task { [weak self] in
            do {
                let reply = try await MarkdownAIChatClient.chat(
                    apiKey: apiKey,
                    model: model,
                    markdownContent: markdownContent,
                    fileName: fileName,
                    history: history
                )

                await MainActor.run {
                    guard let self, !Task.isCancelled else { return }
                    self.messages.append(AIChatMessage(role: .assistant, content: reply))
                    self.isRunning = false
                }
            } catch {
                await MainActor.run {
                    guard let self, !Task.isCancelled else { return }
                    self.messages.append(AIChatMessage(role: .assistant, content: "Error: \(error.localizedDescription)"))
                    self.isRunning = false
                }
            }
        }
    }

    func clear() {
        task?.cancel()
        messages.removeAll()
        isRunning = false
    }
}

private enum MarkdownAIChatClient {
    private static let chatCompletionsURL = URL(string: "https://coding.dashscope.aliyuncs.com/v1/chat/completions")!

    static func chat(
        apiKey: String,
        model: String,
        markdownContent: String,
        fileName: String,
        history: [AIChatMessage]
    ) async throws -> String {
        var urlRequest = URLRequest(url: chatCompletionsURL)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 120
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        var apiMessages: [APIChatMessage] = [
            APIChatMessage(role: "system", content: systemPrompt(fileName: fileName, markdownContent: markdownContent))
        ]

        for msg in history {
            apiMessages.append(APIChatMessage(role: msg.role.rawValue, content: msg.content))
        }

        let body = APIChatRequest(
            model: model,
            messages: apiMessages,
            temperature: 0.7
        )
        urlRequest.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIChatError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8)
                ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw AIChatError.http(status: httpResponse.statusCode, message: message)
        }

        let decoded = try JSONDecoder().decode(APIChatResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIChatError.emptyResponse
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func systemPrompt(fileName: String, markdownContent: String) -> String {
        """
        你是一个基于用户 Markdown 笔记内容的智能助手。

        当前笔记文件: \(fileName)

        笔记内容:
        \(markdownContent)

        规则:
        - 基于上面的笔记内容回答用户的问题。
        - 用户可能让你出考题、解释内容、总结要点、翻译、提问等。
        - 用 Markdown 格式回答，保持简洁清晰。
        - 如果用户的问题与笔记内容无关，也可以正常回答。
        - 回答语言跟随用户提问的语言。
        """
    }
}

private struct APIChatMessage: Encodable {
    let role: String
    let content: String
}

private struct APIChatRequest: Encodable {
    let model: String
    let messages: [APIChatMessage]
    let temperature: Double
}

private struct APIChatResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: String?
    }
}

private enum AIChatError: LocalizedError {
    case invalidResponse
    case http(status: Int, message: String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid server response."
        case .http(let status, let message):
            return "HTTP \(status): \(message)"
        case .emptyResponse:
            return "The model returned no text."
        }
    }
}
