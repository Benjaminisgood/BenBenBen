import Combine
import Foundation

enum ScriptLanguage: String {
    case shell = "Shell"
    case python = "Python"
    case appleScript = "AppleScript"

    var promptGuidance: String {
        switch self {
        case .shell:
            return "Return a complete /bin/zsh script. Preserve a shebang when present."
        case .python:
            return "Return a complete Python script. Preserve imports and executable entry points when useful."
        case .appleScript:
            return "Return a complete AppleScript source file. Prefer explicit application names and readable AppleScript."
        }
    }
}

struct ScriptAIEditProposal {
    let language: ScriptLanguage
    let instruction: String
    let fileName: String
    let originalScript: String
    let replacementScript: String
}

@MainActor
final class ScriptAIEditStore: ObservableObject {
    @Published var input = ""
    @Published private(set) var statusText = "Describe the script you want to create or revise."
    @Published private(set) var proposal: ScriptAIEditProposal?
    @Published private(set) var isRunning = false

    private var task: Task<Void, Never>?

    var canSubmit: Bool {
        !isRunning && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func submit(settings: AppSettingsStore, language: ScriptLanguage, fileName: String, script: String) {
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

        task?.cancel()
        proposal = nil
        isRunning = true
        statusText = "Asking AI for a \(language.rawValue) proposal..."

        task = Task { [weak self] in
            do {
                let replacementScript = try await Self.generateScript(
                    apiKey: apiKey,
                    model: model,
                    language: language,
                    instruction: instruction,
                    fileName: fileName,
                    script: script
                )
                await MainActor.run {
                    guard let self, !Task.isCancelled else { return }
                    self.proposal = ScriptAIEditProposal(
                        language: language,
                        instruction: instruction,
                        fileName: fileName,
                        originalScript: script,
                        replacementScript: replacementScript
                    )
                    self.input = ""
                    self.statusText = "Review the \(language.rawValue) proposal before applying it."
                    self.isRunning = false
                }
            } catch {
                await MainActor.run {
                    guard let self, !Task.isCancelled else { return }
                    self.statusText = "\(language.rawValue) AI failed: \(error.localizedDescription)"
                    self.isRunning = false
                }
            }
        }
    }

    func acceptProposal() {
        proposal = nil
        statusText = "Script proposal applied."
    }

    func rejectProposal() {
        proposal = nil
        statusText = "Script proposal rejected."
    }

    private static func generateScript(
        apiKey: String,
        model: String,
        language: ScriptLanguage,
        instruction: String,
        fileName: String,
        script: String
    ) async throws -> String {
        let reply = try await BailianChatClient.chat(
            apiKey: apiKey,
            model: model,
            messages: [
                BailianChatMessage(role: "system", content: systemPrompt(language: language)),
                BailianChatMessage(
                    role: "user",
                    content: """
                    File: \(fileName)

                    User instruction:
                    \(instruction)

                    Current \(language.rawValue) script:
                    \(script)
                    """
                )
            ],
            temperature: 0.2
        )

        return stripMarkdownFence(from: reply)
    }

    private static func systemPrompt(language: ScriptLanguage) -> String {
        """
        You are a \(language.rawValue) editing assistant for macOS automation.

        Return only the complete script source that should replace the current file.
        Do not include explanations or markdown fences.
        Preserve useful existing behavior unless the user asks to replace it.
        \(language.promptGuidance)
        """
    }

    private static func stripMarkdownFence(from reply: String) -> String {
        let trimmed = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```"), trimmed.hasSuffix("```") else {
            return trimmed
        }

        let lines = trimmed.components(separatedBy: .newlines)
        guard lines.count >= 3 else { return trimmed }
        return lines.dropFirst().dropLast().joined(separator: "\n")
    }
}
