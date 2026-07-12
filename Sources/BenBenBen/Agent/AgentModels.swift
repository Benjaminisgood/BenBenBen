import Foundation

enum CodexProtocolBaseline {
    /// Stable schema generated with:
    /// `codex app-server generate-json-schema --out DIR`
    /// on 2026-07-11. Experimental fields were intentionally excluded.
    static let codexVersion = "0.142.4"
    static let experimentalAPI = false
}

struct CodexInstallation: Sendable, Equatable {
    let executableURL: URL
    let version: String
    let versionOutput: String

    var matchesGeneratedSchema: Bool {
        version == CodexProtocolBaseline.codexVersion
    }
}

struct CodexClientInfo: Sendable, Equatable {
    var name = "benbenben"
    var title = "BenBenBen"
    var version = "0.1.0"
}

struct CodexServerInfo: Sendable, Equatable {
    let installation: CodexInstallation
    let userAgent: String
    let codexHome: String
    let platformFamily: String
    let platformOS: String
}

enum AgentConnectionState: Sendable, Equatable {
    case disconnected
    case starting
    case ready(CodexServerInfo)
    case failed(String)
}

enum AgentAccount: Sendable, Equatable {
    case apiKey
    case chatGPT(email: String?, plan: String)
    case amazonBedrock(credentialSource: String?)
    case unknown(type: String, raw: AgentJSON)
}

struct AgentAccountStatus: Sendable, Equatable {
    let account: AgentAccount?
    let requiresOpenAIAuth: Bool
}

struct AgentLoginFlow: Sendable, Equatable {
    let type: String
    let loginID: String?
    let authorizationURL: URL?
    let verificationURL: URL?
    let userCode: String?
}

struct AgentThread: Sendable, Equatable, Identifiable {
    let id: String
    let sessionID: String?
    let preview: String
    let name: String?
    let cwd: String?
    let modelProvider: String?
    let createdAt: Double?
    let updatedAt: Double?
    let status: String?
    let raw: AgentJSON

    init(json: AgentJSON) throws {
        guard let id = json["id"]?.stringValue else {
            throw CodexBridgeError.invalidResponse(method: "thread", detail: "missing thread.id")
        }
        self.id = id
        sessionID = json["sessionId"]?.stringValue
        preview = json["preview"]?.stringValue ?? ""
        name = json["name"]?.stringValue
        cwd = json["cwd"]?.stringValue
        modelProvider = json["modelProvider"]?.stringValue
        createdAt = json["createdAt"]?.doubleValue
        updatedAt = json["updatedAt"]?.doubleValue
        status = json["status"]?["type"]?.stringValue ?? json["status"]?.stringValue
        raw = json
    }
}

struct AgentThreadPage: Sendable, Equatable {
    let threads: [AgentThread]
    let nextCursor: String?
    let backwardsCursor: String?
}

struct AgentTurn: Sendable, Equatable, Identifiable {
    let id: String
    let status: String
    let errorMessage: String?
    let raw: AgentJSON

    init(json: AgentJSON) throws {
        guard let id = json["id"]?.stringValue else {
            throw CodexBridgeError.invalidResponse(method: "turn", detail: "missing turn.id")
        }
        self.id = id
        status = json["status"]?.stringValue ?? "unknown"
        errorMessage = json["error"]?["message"]?.stringValue
        raw = json
    }
}

struct AgentSentTurn: Sendable, Equatable {
    let threadID: String
    let turn: AgentTurn
}

struct AgentTokenUsage: Sendable, Equatable {
    struct Breakdown: Sendable, Equatable {
        let totalTokens: Int64
        let inputTokens: Int64
        let cachedInputTokens: Int64
        let outputTokens: Int64
        let reasoningOutputTokens: Int64

        init(json: AgentJSON?) {
            totalTokens = json?["totalTokens"]?.integerValue ?? 0
            inputTokens = json?["inputTokens"]?.integerValue ?? 0
            cachedInputTokens = json?["cachedInputTokens"]?.integerValue ?? 0
            outputTokens = json?["outputTokens"]?.integerValue ?? 0
            reasoningOutputTokens = json?["reasoningOutputTokens"]?.integerValue ?? 0
        }
    }

    let total: Breakdown
    let last: Breakdown
    let modelContextWindow: Int64?

    init(json: AgentJSON) {
        total = Breakdown(json: json["total"])
        last = Breakdown(json: json["last"])
        modelContextWindow = json["modelContextWindow"]?.integerValue
    }
}

struct AgentEventContext: Sendable, Equatable {
    let threadID: String
    let turnID: String
    let itemID: String?
}

enum AgentApprovalKind: String, Sendable, Equatable {
    case command
    case fileChange
    case permissions
    case userInput
    case mcpElicitation
    case legacyCommand
    case legacyFileChange
}

struct AgentApprovalRequest: Sendable, Equatable, Identifiable {
    let id: AgentRequestID
    let kind: AgentApprovalKind
    let method: String
    let threadID: String?
    let turnID: String?
    let itemID: String?
    let reason: String?
    let command: String?
    let cwd: String?
    let rawParams: AgentJSON
}

enum AgentApprovalResponse: Sendable, Equatable {
    case accept
    case acceptForSession
    case decline
    case cancel
    case grantPermissions(AgentJSON, scope: String)
    case userInputAnswers([String: [String]])
    case custom(AgentJSON)
}

enum AgentEvent: Sendable, Equatable {
    case connectionChanged(AgentConnectionState)
    case protocolVersionMismatch(expected: String, actual: String)
    case agentMessageDelta(context: AgentEventContext, delta: String)
    case commandOutputDelta(context: AgentEventContext, delta: String)
    case fileChangeOutputDelta(context: AgentEventContext, delta: String)
    case diffUpdated(context: AgentEventContext, diff: String)
    case tokenUsageUpdated(threadID: String, turnID: String, usage: AgentTokenUsage)
    case turnStarted(threadID: String, turn: AgentTurn)
    case turnCompleted(threadID: String, turn: AgentTurn)
    case threadUpdated(AgentThread)
    case threadArchived(String)
    case approvalRequested(AgentApprovalRequest)
    case loginCompleted(loginID: String?, success: Bool, error: String?)
    case runtimeError(threadID: String?, turnID: String?, message: String, willRetry: Bool)
    case warning(String)
    case stderr(String)
    case malformedMessage(line: String, error: String)
    case unknownMessage(method: String?, raw: AgentJSON)
    case processExited(status: Int32, expected: Bool, stderrTail: String)
}

struct AgentThreadListQuery: Sendable, Equatable {
    var cursor: String?
    var limit: Int?
    var archived: Bool?
    var cwd: [String]?
    var searchTerm: String?

    init(
        cursor: String? = nil,
        limit: Int? = 50,
        archived: Bool? = false,
        cwd: [String]? = nil,
        searchTerm: String? = nil
    ) {
        self.cursor = cursor
        self.limit = limit
        self.archived = archived
        self.cwd = cwd
        self.searchTerm = searchTerm
    }

    var json: AgentJSON {
        var object: [String: AgentJSON] = [:]
        if let cursor { object["cursor"] = .string(cursor) }
        if let limit { object["limit"] = .integer(Int64(limit)) }
        if let archived { object["archived"] = .bool(archived) }
        if let cwd {
            object["cwd"] = cwd.count == 1 ? .string(cwd[0]) : .array(cwd.map(AgentJSON.string))
        }
        if let searchTerm { object["searchTerm"] = .string(searchTerm) }
        return .object(object)
    }
}

struct AgentThreadStartOptions: Sendable, Equatable {
    var cwd: String
    var model: String?
    var ephemeral: Bool
    var approvalPolicy: String
    var sandbox: String
    var approvalsReviewer: String

    init(
        cwd: String = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("keyoti", isDirectory: true).path,
        model: String? = nil,
        ephemeral: Bool = false,
        approvalPolicy: String = "on-request",
        sandbox: String = "workspace-write",
        approvalsReviewer: String = "user"
    ) {
        self.cwd = cwd
        self.model = model
        self.ephemeral = ephemeral
        self.approvalPolicy = approvalPolicy
        self.sandbox = sandbox
        self.approvalsReviewer = approvalsReviewer
    }

    var json: AgentJSON {
        var object: [String: AgentJSON] = [
            "cwd": .string(cwd),
            "ephemeral": .bool(ephemeral),
            "approvalPolicy": .string(approvalPolicy),
            "sandbox": .string(sandbox),
            "approvalsReviewer": .string(approvalsReviewer)
        ]
        if let model { object["model"] = .string(model) }
        return .object(object)
    }
}

enum CodexBridgeError: Error, Sendable, LocalizedError {
    case executableNotFound
    case executableNotRunnable(String)
    case versionProbeFailed(path: String, output: String)
    case launchFailed(String)
    case alreadyRunning
    case notRunning
    case notInitialized
    case requestTimedOut(method: String)
    case transportClosed(String)
    case server(code: Int, message: String, data: AgentJSON?)
    case invalidResponse(method: String, detail: String)
    case missingApproval(AgentRequestID)
    case unsupportedApproval(method: String, response: String)

    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            "Could not find a runnable Codex executable."
        case let .executableNotRunnable(path):
            "Codex is not executable at \(path)."
        case let .versionProbeFailed(path, output):
            "Could not read the Codex version at \(path): \(output)"
        case let .launchFailed(message):
            "Could not launch Codex app-server: \(message)"
        case .alreadyRunning:
            "Codex app-server is already running."
        case .notRunning:
            "Codex app-server is not running."
        case .notInitialized:
            "Codex app-server has not completed initialization."
        case let .requestTimedOut(method):
            "Codex app-server request timed out: \(method)."
        case let .transportClosed(message):
            "Codex app-server transport closed: \(message)"
        case let .server(code, message, _):
            "Codex app-server error \(code): \(message)"
        case let .invalidResponse(method, detail):
            "Invalid response for \(method): \(detail)"
        case let .missingApproval(id):
            "Approval request \(id) is no longer pending."
        case let .unsupportedApproval(method, response):
            "Approval response \(response) is not valid for \(method)."
        }
    }

    var isMissingThread: Bool {
        guard case let .server(code, message, _) = self else { return false }
        return code == -32_600 && message.localizedCaseInsensitiveContains("thread not found")
    }
}
