import Foundation

struct BailianChatMessage: Encodable {
    let role: String
    let content: String
}

enum BailianChatClient {
    private static let chatCompletionsURL = URL(string: "https://coding.dashscope.aliyuncs.com/v1/chat/completions")!

    static func chat(
        apiKey: String,
        model: String,
        messages: [BailianChatMessage],
        temperature: Double = 0.7,
        timeout: TimeInterval = 120
    ) async throws -> String {
        var request = URLRequest(url: chatCompletionsURL)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            BailianChatRequest(model: model, messages: messages, temperature: temperature)
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BailianChatError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8)
                ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw BailianChatError.http(status: httpResponse.statusCode, message: message)
        }

        let decoded = try JSONDecoder().decode(BailianChatResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BailianChatError.emptyResponse
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct BailianChatRequest: Encodable {
    let model: String
    let messages: [BailianChatMessage]
    let temperature: Double
}

private struct BailianChatResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: String?
    }
}

enum BailianChatError: LocalizedError {
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
