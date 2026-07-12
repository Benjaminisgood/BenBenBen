import Foundation

actor CodexProcessActor: AgentRuntime {
    nonisolated let installation: CodexInstallation

    private struct PendingRequest {
        let method: String
        let continuation: CheckedContinuation<AgentJSON, Error>
    }

    private struct PendingApproval {
        let request: AgentApprovalRequest
    }

    private let clientInfo: CodexClientInfo
    private let requestTimeout: Duration
    private let events: AsyncStream<AgentEvent>
    private let eventContinuation: AsyncStream<AgentEvent>.Continuation
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var process: Process?
    private var standardInput: FileHandle?
    private var stdoutHandle: FileHandle?
    private var stderrHandle: FileHandle?
    private var stdoutBuffer = Data()
    private var stderrTail = ""
    private var nextRequestID: Int64 = 1
    private var pendingRequests: [AgentRequestID: PendingRequest] = [:]
    private var pendingApprovals: [AgentRequestID: PendingApproval] = [:]
    private var initialized = false
    private var stopRequested = false
    private var handledTermination = false
    private var serverInfo: CodexServerInfo?

    init(
        installation: CodexInstallation,
        clientInfo: CodexClientInfo = CodexClientInfo(),
        requestTimeout: Duration = .seconds(30)
    ) {
        self.installation = installation
        self.clientInfo = clientInfo
        self.requestTimeout = requestTimeout
        let stream = AsyncStream<AgentEvent>.makeStream(bufferingPolicy: .bufferingNewest(1_024))
        events = stream.stream
        eventContinuation = stream.continuation
    }

    nonisolated func eventStream() -> AsyncStream<AgentEvent> {
        events
    }

    func start() async throws -> CodexServerInfo {
        if let serverInfo, initialized, process?.isRunning == true {
            return serverInfo
        }
        guard process == nil else { throw CodexBridgeError.alreadyRunning }

        eventContinuation.yield(.connectionChanged(.starting))
        stopRequested = false
        handledTermination = false
        initialized = false
        stdoutBuffer.removeAll(keepingCapacity: true)
        stderrTail = ""

        let child = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        child.executableURL = installation.executableURL
        child.arguments = ["app-server", "--stdio"]
        child.standardInput = stdinPipe
        child.standardOutput = stdoutPipe
        child.standardError = stderrPipe
        child.terminationHandler = { [weak self] terminatedProcess in
            let status = terminatedProcess.terminationStatus
            Task { await self?.processDidExit(status: status) }
        }

        do {
            try child.run()
        } catch {
            let bridgeError = CodexBridgeError.launchFailed(error.localizedDescription)
            eventContinuation.yield(.connectionChanged(.failed(bridgeError.localizedDescription)))
            throw bridgeError
        }

        process = child
        standardInput = stdinPipe.fileHandleForWriting
        beginReading(stdout: stdoutPipe.fileHandleForReading, stderr: stderrPipe.fileHandleForReading)

        do {
            let initializeResult = try await sendRequest(
                method: "initialize",
                params: .object([
                    "clientInfo": .object([
                        "name": .string(clientInfo.name),
                        "title": .string(clientInfo.title),
                        "version": .string(clientInfo.version)
                    ]),
                    "capabilities": .object([
                        "experimentalApi": .bool(CodexProtocolBaseline.experimentalAPI),
                        "requestAttestation": .bool(false),
                        "mcpServerOpenaiFormElicitation": .bool(false)
                    ])
                ]),
                requiresInitialization: false
            )
            try sendNotification(method: "initialized")

            guard let userAgent = initializeResult["userAgent"]?.stringValue,
                  let codexHome = initializeResult["codexHome"]?.stringValue,
                  let platformFamily = initializeResult["platformFamily"]?.stringValue,
                  let platformOS = initializeResult["platformOs"]?.stringValue
            else {
                throw CodexBridgeError.invalidResponse(
                    method: "initialize",
                    detail: "missing userAgent, codexHome, platformFamily, or platformOs"
                )
            }

            let info = CodexServerInfo(
                installation: installation,
                userAgent: userAgent,
                codexHome: codexHome,
                platformFamily: platformFamily,
                platformOS: platformOS
            )
            initialized = true
            serverInfo = info
            if !installation.matchesGeneratedSchema {
                eventContinuation.yield(
                    .protocolVersionMismatch(
                        expected: CodexProtocolBaseline.codexVersion,
                        actual: installation.version
                    )
                )
            }
            eventContinuation.yield(.connectionChanged(.ready(info)))
            return info
        } catch {
            initialized = false
            serverInfo = nil
            let message = error.localizedDescription
            eventContinuation.yield(.connectionChanged(.failed(message)))
            child.terminate()
            throw error
        }
    }

    func stop() async {
        stopRequested = true
        initialized = false
        serverInfo = nil
        failPendingRequests(with: CodexBridgeError.transportClosed("client stopped app-server"))
        pendingApprovals.removeAll()

        stdoutHandle?.readabilityHandler = nil
        stderrHandle?.readabilityHandler = nil
        stdoutHandle = nil
        stderrHandle = nil
        try? standardInput?.close()
        standardInput = nil

        if let process, process.isRunning {
            process.terminate()
        } else {
            self.process = nil
            eventContinuation.yield(.connectionChanged(.disconnected))
        }
    }

    func readAccount(refreshToken: Bool = false) async throws -> AgentAccountStatus {
        let result = try await sendRequest(
            method: "account/read",
            params: .object(["refreshToken": .bool(refreshToken)])
        )
        guard let requiresAuth = result["requiresOpenaiAuth"]?.boolValue else {
            throw CodexBridgeError.invalidResponse(
                method: "account/read",
                detail: "missing requiresOpenaiAuth"
            )
        }

        let account: AgentAccount?
        switch result["account"] {
        case nil, .some(.null):
            account = nil
        case let .some(value):
            let type = value["type"]?.stringValue ?? "unknown"
            switch type {
            case "apiKey":
                account = .apiKey
            case "chatgpt":
                account = .chatGPT(
                    email: value["email"]?.stringValue,
                    plan: value["planType"]?.stringValue ?? "unknown"
                )
            case "amazonBedrock":
                account = .amazonBedrock(credentialSource: value["credentialSource"]?.stringValue)
            default:
                account = .unknown(type: type, raw: value)
            }
        }
        return AgentAccountStatus(account: account, requiresOpenAIAuth: requiresAuth)
    }

    func startChatGPTLogin() async throws -> AgentLoginFlow {
        let result = try await sendRequest(
            method: "account/login/start",
            params: .object(["type": .string("chatgpt")])
        )
        let type = result["type"]?.stringValue ?? "chatgpt"
        return AgentLoginFlow(
            type: type,
            loginID: result["loginId"]?.stringValue,
            authorizationURL: result["authUrl"]?.stringValue.flatMap(URL.init(string:)),
            verificationURL: result["verificationUrl"]?.stringValue.flatMap(URL.init(string:)),
            userCode: result["userCode"]?.stringValue
        )
    }

    func listThreads(_ query: AgentThreadListQuery = AgentThreadListQuery()) async throws -> AgentThreadPage {
        let result = try await sendRequest(method: "thread/list", params: query.json)
        guard let data = result["data"]?.arrayValue else {
            throw CodexBridgeError.invalidResponse(method: "thread/list", detail: "missing data array")
        }
        return AgentThreadPage(
            threads: try data.map(AgentThread.init(json:)),
            nextCursor: result["nextCursor"]?.stringValue,
            backwardsCursor: result["backwardsCursor"]?.stringValue
        )
    }

    func startThread(_ options: AgentThreadStartOptions) async throws -> AgentThread {
        let result = try await sendRequest(method: "thread/start", params: options.json)
        guard let thread = result["thread"] else {
            throw CodexBridgeError.invalidResponse(method: "thread/start", detail: "missing thread")
        }
        return try AgentThread(json: thread)
    }

    func resumeThread(id: String, cwd: String? = nil) async throws -> AgentThread {
        var params: [String: AgentJSON] = ["threadId": .string(id)]
        if let cwd { params["cwd"] = .string(cwd) }
        let result = try await sendRequest(method: "thread/resume", params: .object(params))
        guard let thread = result["thread"] else {
            throw CodexBridgeError.invalidResponse(method: "thread/resume", detail: "missing thread")
        }
        return try AgentThread(json: thread)
    }

    func archiveThread(id: String) async throws {
        _ = try await sendRequest(
            method: "thread/archive",
            params: .object(["threadId": .string(id)])
        )
    }

    func startTurn(threadID: String, text: String, localImagePath: String? = nil) async throws -> AgentTurn {
        var input: [AgentJSON] = [
            .object([
                "type": .string("text"),
                "text": .string(text),
                "text_elements": .array([])
            ])
        ]
        if let localImagePath {
            input.append(.object([
                "type": .string("localImage"),
                "path": .string(localImagePath)
            ]))
        }
        let result = try await sendRequest(
            method: "turn/start",
            params: .object([
                "threadId": .string(threadID),
                "input": .array(input)
            ])
        )
        guard let turn = result["turn"] else {
            throw CodexBridgeError.invalidResponse(method: "turn/start", detail: "missing turn")
        }
        return try AgentTurn(json: turn)
    }

    func steerTurn(threadID: String, turnID: String, text: String) async throws -> String {
        let result = try await sendRequest(
            method: "turn/steer",
            params: .object([
                "threadId": .string(threadID),
                "expectedTurnId": .string(turnID),
                "input": .array([
                    .object([
                        "type": .string("text"),
                        "text": .string(text),
                        "text_elements": .array([])
                    ])
                ])
            ])
        )
        guard let acceptedTurnID = result["turnId"]?.stringValue else {
            throw CodexBridgeError.invalidResponse(method: "turn/steer", detail: "missing turnId")
        }
        return acceptedTurnID
    }

    func interruptTurn(threadID: String, turnID: String) async throws {
        _ = try await sendRequest(
            method: "turn/interrupt",
            params: .object([
                "threadId": .string(threadID),
                "turnId": .string(turnID)
            ])
        )
    }

    func respondToApproval(id: AgentRequestID, response: AgentApprovalResponse) async throws {
        guard let pending = pendingApprovals[id] else {
            throw CodexBridgeError.missingApproval(id)
        }
        let result = try approvalResult(for: pending.request, response: response)
        try sendEnvelope(AgentRPCEnvelope(id: id, result: result))
        pendingApprovals.removeValue(forKey: id)
    }

    private func beginReading(stdout: FileHandle, stderr: FileHandle) {
        stdoutHandle = stdout
        stderrHandle = stderr

        // FileHandle.read(upToCount:) can wait for the requested byte count on
        // a long-lived pipe. app-server keeps stdout open, so use readability
        // callbacks to process every available JSONL chunk immediately.
        stdout.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                Task { await self?.receiveStdoutEOF() }
            } else {
                Task { await self?.receiveStdout(data) }
            }
        }
        stderr.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else {
                Task { await self?.receiveStderr(data) }
            }
        }
    }

    private func receiveStdout(_ data: Data) {
        stdoutBuffer.append(data)
        while let newline = stdoutBuffer.firstIndex(of: 0x0A) {
            var lineData = stdoutBuffer.prefix(upTo: newline)
            stdoutBuffer.removeSubrange(...newline)
            if lineData.last == 0x0D { lineData = lineData.dropLast() }
            guard !lineData.isEmpty else { continue }
            processLine(Data(lineData))
        }
    }

    private func receiveStdoutEOF() {
        guard !stdoutBuffer.isEmpty else { return }
        let trailing = stdoutBuffer
        stdoutBuffer.removeAll()
        processLine(trailing)
    }

    private func receiveStderr(_ data: Data) {
        let text = String(decoding: data, as: UTF8.self)
        stderrTail.append(text)
        if stderrTail.utf8.count > 32_768 {
            stderrTail = String(stderrTail.suffix(24_576))
        }
        eventContinuation.yield(.stderr(text))
    }

    private func processLine(_ data: Data) {
        do {
            let envelope = try decoder.decode(AgentRPCEnvelope.self, from: data)
            route(envelope)
        } catch {
            eventContinuation.yield(
                .malformedMessage(
                    line: String(decoding: data, as: UTF8.self),
                    error: error.localizedDescription
                )
            )
        }
    }

    private func route(_ envelope: AgentRPCEnvelope) {
        if let method = envelope.method, let id = envelope.id {
            routeServerRequest(id: id, method: method, params: envelope.params ?? .emptyObject)
        } else if let method = envelope.method {
            routeNotification(method: method, params: envelope.params ?? .emptyObject, raw: envelope.jsonValue)
        } else if let id = envelope.id {
            routeResponse(id: id, result: envelope.result, error: envelope.error, raw: envelope.jsonValue)
        } else {
            eventContinuation.yield(.unknownMessage(method: nil, raw: envelope.jsonValue))
        }
    }

    private func routeResponse(
        id: AgentRequestID,
        result: AgentJSON?,
        error: AgentRPCErrorPayload?,
        raw: AgentJSON
    ) {
        guard let pending = pendingRequests.removeValue(forKey: id) else {
            eventContinuation.yield(.unknownMessage(method: nil, raw: raw))
            return
        }
        if let error {
            pending.continuation.resume(
                throwing: CodexBridgeError.server(
                    code: error.code,
                    message: error.message,
                    data: error.data
                )
            )
        } else if let result {
            pending.continuation.resume(returning: result)
        } else {
            pending.continuation.resume(
                throwing: CodexBridgeError.invalidResponse(
                    method: pending.method,
                    detail: "response has neither result nor error"
                )
            )
        }
    }

    private func routeServerRequest(id: AgentRequestID, method: String, params: AgentJSON) {
        let kind: AgentApprovalKind?
        switch method {
        case "item/commandExecution/requestApproval": kind = .command
        case "item/fileChange/requestApproval": kind = .fileChange
        case "item/permissions/requestApproval": kind = .permissions
        case "item/tool/requestUserInput": kind = .userInput
        case "mcpServer/elicitation/request": kind = .mcpElicitation
        case "execCommandApproval": kind = .legacyCommand
        case "applyPatchApproval": kind = .legacyFileChange
        default: kind = nil
        }

        guard let kind else {
            eventContinuation.yield(
                .unknownMessage(
                    method: method,
                    raw: AgentRPCEnvelope(id: id, method: method, params: params).jsonValue
                )
            )
            do {
                try sendEnvelope(
                    AgentRPCEnvelope(
                        id: id,
                        error: AgentRPCErrorPayload(
                            code: -32601,
                            message: "Unsupported server request: \(method)",
                            data: nil
                        )
                    )
                )
            } catch {
                eventContinuation.yield(.warning(error.localizedDescription))
            }
            return
        }

        let request = AgentApprovalRequest(
            id: id,
            kind: kind,
            method: method,
            threadID: params["threadId"]?.stringValue ?? params["conversationId"]?.stringValue,
            turnID: params["turnId"]?.stringValue,
            itemID: params["itemId"]?.stringValue ?? params["callId"]?.stringValue,
            reason: params["reason"]?.stringValue ?? params["message"]?.stringValue,
            command: params["command"]?.stringValue,
            cwd: params["cwd"]?.stringValue,
            rawParams: params
        )
        pendingApprovals[id] = PendingApproval(request: request)
        eventContinuation.yield(.approvalRequested(request))
    }

    private func routeNotification(method: String, params: AgentJSON, raw: AgentJSON) {
        switch method {
        case "item/agentMessage/delta":
            yieldTextDelta(.agent, params: params, raw: raw)
        case "item/commandExecution/outputDelta":
            yieldTextDelta(.command, params: params, raw: raw)
        case "item/fileChange/outputDelta":
            yieldTextDelta(.fileChange, params: params, raw: raw)
        case "turn/diff/updated":
            guard let context = context(from: params), let diff = params["diff"]?.stringValue else {
                eventContinuation.yield(.unknownMessage(method: method, raw: raw))
                return
            }
            eventContinuation.yield(.diffUpdated(context: context, diff: diff))
        case "thread/tokenUsage/updated":
            guard let threadID = params["threadId"]?.stringValue,
                  let turnID = params["turnId"]?.stringValue,
                  let tokenUsage = params["tokenUsage"]
            else {
                eventContinuation.yield(.unknownMessage(method: method, raw: raw))
                return
            }
            eventContinuation.yield(
                .tokenUsageUpdated(
                    threadID: threadID,
                    turnID: turnID,
                    usage: AgentTokenUsage(json: tokenUsage)
                )
            )
        case "turn/started", "turn/completed":
            guard let threadID = params["threadId"]?.stringValue, let turnJSON = params["turn"],
                  let turn = try? AgentTurn(json: turnJSON)
            else {
                eventContinuation.yield(.unknownMessage(method: method, raw: raw))
                return
            }
            if method == "turn/started" {
                eventContinuation.yield(.turnStarted(threadID: threadID, turn: turn))
            } else {
                eventContinuation.yield(.turnCompleted(threadID: threadID, turn: turn))
            }
        case "thread/started":
            guard let threadJSON = params["thread"], let thread = try? AgentThread(json: threadJSON) else {
                eventContinuation.yield(.unknownMessage(method: method, raw: raw))
                return
            }
            eventContinuation.yield(.threadUpdated(thread))
        case "thread/archived":
            guard let threadID = params["threadId"]?.stringValue else {
                eventContinuation.yield(.unknownMessage(method: method, raw: raw))
                return
            }
            eventContinuation.yield(.threadArchived(threadID))
        case "account/login/completed":
            eventContinuation.yield(
                .loginCompleted(
                    loginID: params["loginId"]?.stringValue,
                    success: params["success"]?.boolValue ?? false,
                    error: params["error"]?.stringValue
                )
            )
        case "error":
            eventContinuation.yield(
                .runtimeError(
                    threadID: params["threadId"]?.stringValue,
                    turnID: params["turnId"]?.stringValue,
                    message: params["error"]?["message"]?.stringValue ?? "Unknown Codex error",
                    willRetry: params["willRetry"]?.boolValue ?? false
                )
            )
        case "warning", "guardianWarning", "configWarning", "deprecationNotice":
            let message = params["message"]?.stringValue
                ?? params["summary"]?.stringValue
                ?? String(describing: params)
            eventContinuation.yield(.warning(message))
        case "serverRequest/resolved":
            if let requestID = requestID(from: params["requestId"]) {
                pendingApprovals.removeValue(forKey: requestID)
            }
        default:
            eventContinuation.yield(.unknownMessage(method: method, raw: raw))
        }
    }

    private enum TextDeltaKind { case agent, command, fileChange }

    private func yieldTextDelta(_ kind: TextDeltaKind, params: AgentJSON, raw: AgentJSON) {
        guard let context = context(from: params), let delta = params["delta"]?.stringValue else {
            eventContinuation.yield(.unknownMessage(method: nil, raw: raw))
            return
        }
        switch kind {
        case .agent: eventContinuation.yield(.agentMessageDelta(context: context, delta: delta))
        case .command: eventContinuation.yield(.commandOutputDelta(context: context, delta: delta))
        case .fileChange: eventContinuation.yield(.fileChangeOutputDelta(context: context, delta: delta))
        }
    }

    private func context(from params: AgentJSON) -> AgentEventContext? {
        guard let threadID = params["threadId"]?.stringValue,
              let turnID = params["turnId"]?.stringValue
        else {
            return nil
        }
        return AgentEventContext(
            threadID: threadID,
            turnID: turnID,
            itemID: params["itemId"]?.stringValue
        )
    }

    private func requestID(from json: AgentJSON?) -> AgentRequestID? {
        switch json {
        case let .integer(value): .integer(value)
        case let .string(value): .string(value)
        default: nil
        }
    }

    private func approvalResult(
        for request: AgentApprovalRequest,
        response: AgentApprovalResponse
    ) throws -> AgentJSON {
        if case let .custom(value) = response { return value }

        switch request.kind {
        case .command, .fileChange:
            let decision: String
            switch response {
            case .accept: decision = "accept"
            case .acceptForSession: decision = "acceptForSession"
            case .decline: decision = "decline"
            case .cancel: decision = "cancel"
            default: throw unsupportedApproval(request, response)
            }
            return .object(["decision": .string(decision)])

        case .legacyCommand, .legacyFileChange:
            let decision: String
            switch response {
            case .accept: decision = "approved"
            case .acceptForSession: decision = "approved_for_session"
            case .decline: decision = "denied"
            case .cancel: decision = "abort"
            default: throw unsupportedApproval(request, response)
            }
            return .object(["decision": .string(decision)])

        case .permissions:
            let permissions: AgentJSON
            let scope: String
            switch response {
            case .accept:
                permissions = request.rawParams["permissions"] ?? .emptyObject
                scope = "turn"
            case .acceptForSession:
                permissions = request.rawParams["permissions"] ?? .emptyObject
                scope = "session"
            case let .grantPermissions(granted, requestedScope):
                permissions = granted
                scope = requestedScope == "session" ? "session" : "turn"
            case .decline, .cancel:
                permissions = .emptyObject
                scope = "turn"
            default:
                throw unsupportedApproval(request, response)
            }
            return .object(["permissions": permissions, "scope": .string(scope)])

        case .userInput:
            guard case let .userInputAnswers(answers) = response else {
                throw unsupportedApproval(request, response)
            }
            return .object([
                "answers": .object(
                    answers.mapValues { .object(["answers": .array($0.map(AgentJSON.string))]) }
                )
            ])

        case .mcpElicitation:
            let action: String
            switch response {
            case .decline: action = "decline"
            case .cancel: action = "cancel"
            default: throw unsupportedApproval(request, response)
            }
            return .object([
                "action": .string(action),
                "content": .null,
                "_meta": .null
            ])
        }
    }

    private func unsupportedApproval(
        _ request: AgentApprovalRequest,
        _ response: AgentApprovalResponse
    ) -> CodexBridgeError {
        CodexBridgeError.unsupportedApproval(
            method: request.method,
            response: String(describing: response)
        )
    }

    private func sendRequest(
        method: String,
        params: AgentJSON,
        requiresInitialization: Bool = true
    ) async throws -> AgentJSON {
        guard process?.isRunning == true, standardInput != nil else {
            throw CodexBridgeError.notRunning
        }
        if requiresInitialization && !initialized {
            throw CodexBridgeError.notInitialized
        }

        let id = AgentRequestID.integer(nextRequestID)
        nextRequestID += 1
        return try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<AgentJSON, Error>) in
            pendingRequests[id] = PendingRequest(method: method, continuation: continuation)
            do {
                try sendEnvelope(AgentRPCEnvelope(id: id, method: method, params: params))
                scheduleTimeout(for: id)
            } catch {
                pendingRequests.removeValue(forKey: id)
                continuation.resume(throwing: error)
            }
        }
    }

    private func scheduleTimeout(for id: AgentRequestID) {
        let timeout = requestTimeout
        Task { [weak self] in
            try? await Task.sleep(for: timeout)
            await self?.timeoutRequest(id)
        }
    }

    private func timeoutRequest(_ id: AgentRequestID) {
        guard let pending = pendingRequests.removeValue(forKey: id) else { return }
        pending.continuation.resume(
            throwing: CodexBridgeError.requestTimedOut(method: pending.method)
        )
    }

    private func sendNotification(method: String, params: AgentJSON? = nil) throws {
        try sendEnvelope(AgentRPCEnvelope(method: method, params: params))
    }

    private func sendEnvelope(_ envelope: AgentRPCEnvelope) throws {
        guard let standardInput else { throw CodexBridgeError.notRunning }
        do {
            var data = try encoder.encode(envelope)
            data.append(0x0A)
            try standardInput.write(contentsOf: data)
        } catch {
            throw CodexBridgeError.transportClosed(error.localizedDescription)
        }
    }

    private func processDidExit(status: Int32) {
        guard !handledTermination else { return }
        handledTermination = true
        let expected = stopRequested
        process = nil
        standardInput = nil
        initialized = false
        serverInfo = nil
        stdoutHandle?.readabilityHandler = nil
        stderrHandle?.readabilityHandler = nil
        stdoutHandle = nil
        stderrHandle = nil

        failPendingRequests(
            with: CodexBridgeError.transportClosed("process exited with status \(status)")
        )
        pendingApprovals.removeAll()
        eventContinuation.yield(
            .processExited(status: status, expected: expected, stderrTail: stderrTail)
        )
        if expected {
            eventContinuation.yield(.connectionChanged(.disconnected))
        } else {
            eventContinuation.yield(
                .connectionChanged(.failed("Codex app-server exited with status \(status)."))
            )
        }
    }

    private func failPendingRequests(with error: Error) {
        let pending = pendingRequests.values
        pendingRequests.removeAll()
        for request in pending {
            request.continuation.resume(throwing: error)
        }
    }
}
