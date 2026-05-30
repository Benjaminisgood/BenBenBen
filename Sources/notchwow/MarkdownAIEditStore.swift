import Combine
import Foundation

struct MarkdownAIEditRequest {
    let tabID: UUID
    let fileName: String
    let instruction: String
    let fullText: String
    let selectedRange: NSRange

    var selectedText: String {
        (fullText as NSString).substring(with: selectedRange)
    }

    var isInsertion: Bool {
        selectedRange.length == 0
    }
}

struct MarkdownAIEditProposal: Identifiable {
    let id = UUID()
    let tabID: UUID
    let fileName: String
    let instruction: String
    let originalDocument: String
    let range: NSRange
    let originalText: String
    let replacementText: String
    let createdAt: Date

    var isInsertion: Bool {
        range.length == 0
    }

    var targetLabel: String {
        isInsertion ? "cursor" : "selection"
    }

    func proposedDocument() -> String? {
        let nsDocument = originalDocument as NSString
        guard range.location >= 0,
              range.length >= 0,
              range.location + range.length <= nsDocument.length else {
            return nil
        }

        return nsDocument.replacingCharacters(in: range, with: replacementText)
    }
}

@MainActor
final class MarkdownAIEditStore: ObservableObject {
    @Published var input = ""
    @Published private(set) var statusText = "AI Markdown edits will appear here."
    @Published private(set) var isRunning = false
    @Published private(set) var proposal: MarkdownAIEditProposal?

    private var task: Task<Void, Never>?

    var canSubmit: Bool {
        !isRunning && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func submit(
        settings: AppSettingsStore,
        tabID: UUID,
        fileName: String,
        fullText: String,
        selectedRange: NSRange
    ) {
        let instruction = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty, !isRunning else { return }

        let apiKey = settings.bailianAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = settings.bailianModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            statusText = "Set the Bailian API key in Settings first."
            return
        }
        guard !model.isEmpty else {
            statusText = "Set the Bailian model in Settings first."
            return
        }

        let clampedRange = Self.clampedRange(selectedRange, in: fullText)
        let request = MarkdownAIEditRequest(
            tabID: tabID,
            fileName: fileName,
            instruction: instruction,
            fullText: fullText,
            selectedRange: clampedRange
        )

        task?.cancel()
        proposal = nil
        isRunning = true
        statusText = "Asking AI for a local Markdown edit..."

        task = Task { [weak self] in
            do {
                let replacement = try await MarkdownAIClient.generateReplacement(
                    apiKey: apiKey,
                    model: model,
                    request: request
                )

                await MainActor.run {
                    guard let self, !Task.isCancelled else { return }
                    let proposal = MarkdownAIEditProposal(
                        tabID: request.tabID,
                        fileName: request.fileName,
                        instruction: request.instruction,
                        originalDocument: request.fullText,
                        range: request.selectedRange,
                        originalText: request.selectedText,
                        replacementText: replacement,
                        createdAt: Date()
                    )
                    self.proposal = proposal
                    self.statusText = "Review the proposed \(proposal.targetLabel) edit."
                    self.isRunning = false
                    self.input = ""
                }
            } catch {
                await MainActor.run {
                    guard let self, !Task.isCancelled else { return }
                    self.proposal = nil
                    self.statusText = "AI edit failed: \(error.localizedDescription)"
                    self.isRunning = false
                }
            }
        }
    }

    func rejectProposal() {
        proposal = nil
        statusText = "AI edit rejected."
    }

    func acceptProposal() {
        proposal = nil
        statusText = "AI edit applied."
    }

    func markProposalStale() {
        statusText = "The note changed after this AI proposal was created. Ask AI again to avoid editing the wrong text."
    }

    func markProposalInvalid() {
        proposal = nil
        statusText = "The AI proposal could not be applied."
    }

    private static func clampedRange(_ range: NSRange, in text: String) -> NSRange {
        let length = (text as NSString).length
        let location = min(max(range.location, 0), length)
        let selectionLength = min(max(range.length, 0), length - location)
        return NSRange(location: location, length: selectionLength)
    }
}

private enum MarkdownAIClient {
    private static let chatCompletionsURL = URL(string: "https://coding.dashscope.aliyuncs.com/v1/chat/completions")!

    static func generateReplacement(
        apiKey: String,
        model: String,
        request: MarkdownAIEditRequest
    ) async throws -> String {
        var urlRequest = URLRequest(url: chatCompletionsURL)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 120
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body = ChatCompletionRequest(
            model: model,
            messages: [
                ChatMessage(role: "system", content: systemPrompt),
                ChatMessage(role: "user", content: userPrompt(for: request))
            ],
            temperature: 0.2
        )
        urlRequest.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MarkdownAIError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw MarkdownAIError.http(status: httpResponse.statusCode, message: message)
        }

        let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MarkdownAIError.emptyResponse
        }

        return try parseReplacement(from: content)
    }

    private static var systemPrompt: String {
        """
        You are a local Markdown editing engine. Return only JSON with one string field named "replacement".

        Rules:
        - The complete Markdown document is provided for context.
        - The editable region is marked by NOTCHWOW_EDIT_START and NOTCHWOW_EDIT_END.
        - If the markers are adjacent, this is a cursor insertion; generate only the text to insert at that cursor.
        - If text exists between the markers, generate only the replacement for that selected text.
        - Do not rewrite or include unmarked parts of the document.
        - Preserve Markdown style and surrounding language.
        - Do not include explanations, comments, markdown fences, or extra keys.
        """
    }

    private static func userPrompt(for request: MarkdownAIEditRequest) -> String {
        let markedDocument = documentWithMarkers(for: request)
        let mode = request.isInsertion ? "cursor insertion" : "selection replacement"

        return """
        File: \(request.fileName)
        Mode: \(mode)
        UTF-16 location: \(request.selectedRange.location)
        UTF-16 length: \(request.selectedRange.length)

        User instruction:
        \(request.instruction)

        Complete Markdown document with editable markers:
        \(markedDocument)
        """
    }

    private static func documentWithMarkers(for request: MarkdownAIEditRequest) -> String {
        let nsDocument = request.fullText as NSString
        let prefix = nsDocument.substring(with: NSRange(location: 0, length: request.selectedRange.location))
        let target = nsDocument.substring(with: request.selectedRange)
        let suffixLocation = request.selectedRange.location + request.selectedRange.length
        let suffix = nsDocument.substring(
            with: NSRange(location: suffixLocation, length: nsDocument.length - suffixLocation)
        )

        return "\(prefix)<<<NOTCHWOW_EDIT_START>>>\(target)<<<NOTCHWOW_EDIT_END>>>\(suffix)"
    }

    private static func parseReplacement(from content: String) throws -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = [
            trimmed,
            fencedJSONContent(in: trimmed),
            objectContent(in: trimmed)
        ].compactMap { $0 }

        for candidate in candidates {
            guard let data = candidate.data(using: .utf8),
                  let envelope = try? JSONDecoder().decode(ReplacementEnvelope.self, from: data) else {
                continue
            }
            return envelope.replacement
        }

        throw MarkdownAIError.unparseableResponse
    }

    private static func fencedJSONContent(in text: String) -> String? {
        guard let fenceStart = text.range(of: "```") else { return nil }
        let afterFence = text[fenceStart.upperBound...]
        guard let firstNewline = afterFence.firstIndex(of: "\n") else { return nil }
        let jsonStart = afterFence.index(after: firstNewline)
        guard let fenceEnd = afterFence[jsonStart...].range(of: "```") else { return nil }
        return String(afterFence[jsonStart..<fenceEnd.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func objectContent(in text: String) -> String? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              start <= end else {
            return nil
        }

        return String(text[start...end])
    }
}

private struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double
}

private struct ChatMessage: Encodable {
    let role: String
    let content: String
}

private struct ChatCompletionResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: String?
    }
}

private struct ReplacementEnvelope: Decodable {
    let replacement: String
}

private enum MarkdownAIError: LocalizedError {
    case invalidResponse
    case http(status: Int, message: String)
    case emptyResponse
    case unparseableResponse

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid server response."
        case .http(let status, let message):
            return "HTTP \(status): \(message)"
        case .emptyResponse:
            return "The model returned no text."
        case .unparseableResponse:
            return "The model did not return the expected replacement JSON."
        }
    }
}
