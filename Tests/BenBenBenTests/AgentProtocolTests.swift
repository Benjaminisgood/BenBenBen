import Foundation
import XCTest
@testable import BenBenBen

final class AgentProtocolTests: XCTestCase {
    func testInitializeEnvelopeUsesPlainJSONRPCWireShape() throws {
        let envelope = AgentRPCEnvelope(
            id: .integer(1),
            method: "initialize",
            params: .object(["capabilities": .object(["experimentalApi": .bool(false)])])
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(envelope)) as? [String: Any]
        )
        XCTAssertEqual(object["id"] as? Int, 1)
        XCTAssertEqual(object["method"] as? String, "initialize")
        let params = try XCTUnwrap(object["params"] as? [String: Any])
        let capabilities = try XCTUnwrap(params["capabilities"] as? [String: Any])
        XCTAssertEqual(capabilities["experimentalApi"] as? Bool, false)
    }

    func testLooseJSONRoundTripPreservesUnknownFieldsAndRequestIDTypes() throws {
        let fixture = #"{"method":"future/event","id":"opaque-7","params":{"addedLater":true,"count":4,"ratio":1.5,"nothing":null}}"#
        let envelope = try JSONDecoder().decode(AgentRPCEnvelope.self, from: Data(fixture.utf8))

        XCTAssertEqual(envelope.id, .string("opaque-7"))
        XCTAssertEqual(envelope.method, "future/event")
        XCTAssertEqual(envelope.params?["addedLater"], .bool(true))
        XCTAssertEqual(envelope.params?["count"], .integer(4))
        XCTAssertEqual(envelope.params?["ratio"], .number(1.5))
        XCTAssertEqual(envelope.params?["nothing"], .null)

        let roundTripped = try JSONDecoder().decode(
            AgentRPCEnvelope.self,
            from: JSONEncoder().encode(envelope)
        )
        XCTAssertEqual(roundTripped, envelope)
    }

    func testExecutableDetectorAndFullJSONLContractAgainstFakeServer() async throws {
        let fixture = try TemporaryCodexAppServer()
        defer { fixture.remove() }
        let installation = try await CodexExecutableDetector.probe(fixture.executableURL)
        XCTAssertEqual(installation.version, CodexProtocolBaseline.codexVersion)
        XCTAssertTrue(installation.matchesGeneratedSchema)

        let runtime = CodexProcessActor(
            installation: installation,
            requestTimeout: .seconds(3)
        )
        let eventStream = runtime.eventStream()
        async let eventCollection = Self.collectThroughApproval(eventStream)

        let server: CodexServerInfo
        do {
            server = try await runtime.start()
        } catch {
            XCTFail("Fake app-server transport failed: \(error); trace: \(fixture.trace)")
            throw error
        }
        XCTAssertEqual(server.platformOS, "macos")
        XCTAssertEqual(server.codexHome, "/tmp/fake-codex-home")

        let events = try await eventCollection
        XCTAssertTrue(events.contains { event in
            if case let .agentMessageDelta(context, delta) = event {
                return context.threadID == "thread-1" && delta == "hello"
            }
            return false
        })
        XCTAssertTrue(events.contains { event in
            if case let .commandOutputDelta(_, delta) = event { return delta == "tests passed\n" }
            return false
        })
        XCTAssertTrue(events.contains { event in
            if case let .diffUpdated(_, diff) = event { return diff.contains("+new") }
            return false
        })
        XCTAssertTrue(events.contains { event in
            if case let .tokenUsageUpdated(_, _, usage) = event {
                return usage.total.totalTokens == 12 && usage.last.outputTokens == 3
            }
            return false
        })
        XCTAssertTrue(events.contains { event in
            if case .turnCompleted = event { return true }
            return false
        })
        XCTAssertTrue(events.contains { event in
            if case let .unknownMessage(method, _) = event { return method == "future/event" }
            return false
        })

        let approvals = events.compactMap { event -> AgentApprovalRequest? in
            if case let .approvalRequested(request) = event { return request }
            return nil
        }
        XCTAssertEqual(Set(approvals.map(\.kind)), [.command, .fileChange, .permissions])
        let commandApproval = try XCTUnwrap(approvals.first { $0.kind == .command })
        XCTAssertEqual(commandApproval.command, "git status --short")
        try await runtime.respondToApproval(id: commandApproval.id, response: .decline)
        let fileApproval = try XCTUnwrap(approvals.first { $0.kind == .fileChange })
        try await runtime.respondToApproval(id: fileApproval.id, response: .accept)
        let permissionApproval = try XCTUnwrap(approvals.first { $0.kind == .permissions })
        try await runtime.respondToApproval(id: permissionApproval.id, response: .acceptForSession)

        let account = try await runtime.readAccount(refreshToken: false)
        XCTAssertEqual(account.account, .chatGPT(email: "ben@example.com", plan: "pro"))
        XCTAssertTrue(account.requiresOpenAIAuth)
        XCTAssertTrue(fixture.trace.contains(#""decision":"decline""#))
        XCTAssertTrue(fixture.trace.contains(#""decision":"accept""#))
        XCTAssertTrue(fixture.trace.contains(#""scope":"session""#))

        let login = try await runtime.startChatGPTLogin()
        XCTAssertEqual(login.loginID, "login-1")
        XCTAssertEqual(login.authorizationURL?.host, "chatgpt.com")

        let page = try await runtime.listThreads(AgentThreadListQuery(limit: 25, cwd: ["/tmp/project"]))
        XCTAssertEqual(page.threads.map(\.id), ["thread-1"])
        XCTAssertEqual(page.nextCursor, "next-page")

        let started = try await runtime.startThread(AgentThreadStartOptions(cwd: "/tmp/project"))
        XCTAssertEqual(started.id, "thread-new")
        let resumed = try await runtime.resumeThread(id: "thread-1", cwd: "/tmp/project")
        XCTAssertEqual(resumed.id, "thread-1")
        try await runtime.archiveThread(id: "thread-1")

        let turn = try await runtime.startTurn(
            threadID: "thread-new",
            text: "Run tests",
            localImagePath: "/tmp/current-screen.png"
        )
        XCTAssertEqual(turn.id, "turn-new")
        XCTAssertTrue(fixture.trace.contains(#""type":"localImage""#))
        XCTAssertTrue(fixture.trace.contains("current-screen.png"))
        let steeredID = try await runtime.steerTurn(
            threadID: "thread-new",
            turnID: "turn-new",
            text: "Also lint"
        )
        XCTAssertEqual(steeredID, "turn-new")
        try await runtime.interruptTurn(threadID: "thread-new", turnID: "turn-new")
        await runtime.stop()
    }

    func testUnexpectedProcessExitCanRestartCleanly() async throws {
        let fixture = try TemporaryCodexAppServer(mode: "crashOnce")
        defer { fixture.remove() }
        let installation = try await CodexExecutableDetector.probe(fixture.executableURL)
        let runtime = CodexProcessActor(installation: installation, requestTimeout: .seconds(3))

        do {
            _ = try await runtime.start()
            XCTFail("The first fixture process should crash during initialize")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("process exited"))
        }

        let restarted = try await runtime.start()
        XCTAssertEqual(restarted.userAgent, "benbenben-fixture")
        XCTAssertGreaterThanOrEqual(fixture.trace.components(separatedBy: "in ").count - 1, 2)
        await runtime.stop()
    }

    func testVersionMismatchProducesContractWarningEvent() async throws {
        let fixture = try TemporaryCodexAppServer(version: "9.9.9")
        defer { fixture.remove() }
        let installation = try await CodexExecutableDetector.probe(fixture.executableURL)
        XCTAssertFalse(installation.matchesGeneratedSchema)
        let runtime = CodexProcessActor(installation: installation, requestTimeout: .seconds(3))
        let stream = runtime.eventStream()
        async let collected = Self.collectThroughVersionMismatch(stream)

        _ = try await runtime.start()
        let events = try await collected
        XCTAssertTrue(events.contains { event in
            if case let .protocolVersionMismatch(expected, actual) = event {
                return expected == CodexProtocolBaseline.codexVersion && actual == "9.9.9"
            }
            return false
        })
        await runtime.stop()
    }

    @MainActor
    func testAgentStoreReplacesAThreadThatCannotBeResumed() async throws {
        let fixture = try TemporaryCodexAppServer(mode: "missingThread")
        defer { fixture.remove() }
        let installation = try await CodexExecutableDetector.probe(fixture.executableURL)
        let runtime = CodexProcessActor(installation: installation, requestTimeout: .seconds(3))
        let store = AgentStore(runtime: runtime)

        await store.connect(threadQuery: AgentThreadListQuery(limit: 25, cwd: ["/tmp/project"]))
        let sent = await store.send(
            "Build an HTML exercise",
            to: "missing-thread",
            fallbackOptions: AgentThreadStartOptions(cwd: "/tmp/project")
        )

        XCTAssertEqual(sent?.threadID, "thread-new")
        XCTAssertEqual(sent?.turn.id, "turn-new")
        XCTAssertEqual(store.selectedThreadID, "thread-new")
        let trace = fixture.trace.replacingOccurrences(of: "\\/", with: "/")
        XCTAssertTrue(trace.contains("thread/resume"))
        XCTAssertTrue(trace.contains("thread/start"))
        await runtime.stop()
    }

    func testInstalledStableSchemaStillContainsBridgeSurface() async throws {
        let installation: CodexInstallation
        do {
            installation = try await CodexExecutableDetector.detect()
        } catch {
            throw XCTSkip("Codex executable is not installed in this test environment")
        }

        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("BenBenBenSchema-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: output) }

        let process = Process()
        process.executableURL = installation.executableURL
        process.arguments = ["app-server", "generate-json-schema", "--out", output.path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)

        let clientRequest = try String(
            contentsOf: output.appendingPathComponent("ClientRequest.json"),
            encoding: .utf8
        )
        let serverNotification = try String(
            contentsOf: output.appendingPathComponent("ServerNotification.json"),
            encoding: .utf8
        )
        let serverRequest = try String(
            contentsOf: output.appendingPathComponent("ServerRequest.json"),
            encoding: .utf8
        )

        for method in [
            "initialize", "account/read", "account/login/start", "thread/list", "thread/start",
            "thread/resume", "thread/archive", "turn/start", "turn/steer", "turn/interrupt"
        ] {
            XCTAssertTrue(clientRequest.contains("\"\(method)\""), "Missing stable method \(method)")
        }
        for method in [
            "item/agentMessage/delta", "item/commandExecution/outputDelta",
            "turn/diff/updated", "thread/tokenUsage/updated", "turn/completed"
        ] {
            XCTAssertTrue(serverNotification.contains("\"\(method)\""), "Missing notification \(method)")
        }
        for method in [
            "item/commandExecution/requestApproval", "item/fileChange/requestApproval",
            "item/permissions/requestApproval"
        ] {
            XCTAssertTrue(serverRequest.contains("\"\(method)\""), "Missing server request \(method)")
        }
    }

    private static func collectThroughApproval(_ stream: AsyncStream<AgentEvent>) async throws -> [AgentEvent] {
        try await withThrowingTaskGroup(of: [AgentEvent].self) { group in
            group.addTask {
                var events: [AgentEvent] = []
                for await event in stream {
                    events.append(event)
                    let approvalCount = events.reduce(into: 0) { count, event in
                        if case .approvalRequested = event { count += 1 }
                    }
                    if approvalCount == 3 { return events }
                }
                return events
            }
            group.addTask {
                try await Task.sleep(for: .seconds(3))
                throw AgentProtocolTestError.timedOut
            }
            guard let result = try await group.next() else { throw AgentProtocolTestError.timedOut }
            group.cancelAll()
            return result
        }
    }

    private static func collectThroughVersionMismatch(_ stream: AsyncStream<AgentEvent>) async throws -> [AgentEvent] {
        try await withThrowingTaskGroup(of: [AgentEvent].self) { group in
            group.addTask {
                var events: [AgentEvent] = []
                for await event in stream {
                    events.append(event)
                    if case .protocolVersionMismatch = event { return events }
                }
                return events
            }
            group.addTask {
                try await Task.sleep(for: .seconds(3))
                throw AgentProtocolTestError.timedOut
            }
            guard let result = try await group.next() else { throw AgentProtocolTestError.timedOut }
            group.cancelAll()
            return result
        }
    }
}

private enum AgentProtocolTestError: Error {
    case timedOut
}

private final class TemporaryCodexAppServer {
    let root: URL
    let executableURL: URL

    init(mode: String = "full", version: String = CodexProtocolBaseline.codexVersion) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BenBenBenCodexFixture-\(UUID().uuidString)", isDirectory: true)
        executableURL = root.appendingPathComponent("codex")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let rendered = Self.script
            .replacingOccurrences(of: "__FIXTURE_MODE__", with: mode)
            .replacingOccurrences(of: "__FIXTURE_VERSION__", with: version)
        try Data(rendered.utf8).write(to: executableURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: executableURL.path
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    var trace: String {
        (try? String(contentsOf: root.appendingPathComponent("codex.log"), encoding: .utf8)) ?? "<empty>"
    }

    private static let script = #"""
#!/usr/bin/python3
import json
from pathlib import Path
import sys

TRACE = Path(__file__).with_suffix(".log")
MODE = "__FIXTURE_MODE__"
VERSION = "__FIXTURE_VERSION__"

def trace(value):
    with TRACE.open("a", encoding="utf-8") as handle:
        handle.write(value + "\n")

if len(sys.argv) > 1 and sys.argv[1] == "--version":
    trace("version")
    print("codex-cli " + VERSION)
    raise SystemExit(0)

def emit(value):
    trace("out " + json.dumps(value, separators=(",", ":")))
    print(json.dumps(value, separators=(",", ":")), flush=True)

def thread(thread_id):
    return {
        "id": thread_id,
        "sessionId": thread_id,
        "preview": "Fixture thread",
        "name": None,
        "cwd": "/tmp/project",
        "modelProvider": "openai",
        "createdAt": 1,
        "updatedAt": 2,
        "status": {"type": "idle"},
        "futureField": "must be ignored"
    }

def turn(turn_id, status="inProgress"):
    return {"id": turn_id, "status": status, "items": [], "error": None}

for line in sys.stdin:
    trace("in " + line.rstrip("\n"))
    message = json.loads(line)
    method = message.get("method")
    request_id = message.get("id")
    params = message.get("params", {})

    if method == "initialize":
        crash_marker = Path(__file__).with_suffix(".crashed")
        if MODE == "crashOnce" and not crash_marker.exists():
            crash_marker.write_text("crashed", encoding="utf-8")
            raise SystemExit(23)
        assert params["capabilities"]["experimentalApi"] is False
        assert params["capabilities"]["requestAttestation"] is False
        emit({"id": request_id, "result": {
            "userAgent": "benbenben-fixture",
            "codexHome": "/tmp/fake-codex-home",
            "platformFamily": "unix",
            "platformOs": "macos",
            "futureInitializeField": 1
        }})
    elif method == "initialized":
        emit({"method": "item/agentMessage/delta", "params": {
            "threadId": "thread-1", "turnId": "turn-1", "itemId": "item-1", "delta": "hello"
        }})
        emit({"method": "item/commandExecution/outputDelta", "params": {
            "threadId": "thread-1", "turnId": "turn-1", "itemId": "cmd-1", "delta": "tests passed\n"
        }})
        emit({"method": "turn/diff/updated", "params": {
            "threadId": "thread-1", "turnId": "turn-1", "diff": "@@ -1 +1 @@\n-old\n+new"
        }})
        emit({"method": "thread/tokenUsage/updated", "params": {
            "threadId": "thread-1", "turnId": "turn-1",
            "tokenUsage": {
                "total": {"totalTokens": 12, "inputTokens": 7, "cachedInputTokens": 2, "outputTokens": 5, "reasoningOutputTokens": 1},
                "last": {"totalTokens": 6, "inputTokens": 3, "cachedInputTokens": 0, "outputTokens": 3, "reasoningOutputTokens": 1},
                "modelContextWindow": 100
            }
        }})
        emit({"method": "turn/completed", "params": {"threadId": "thread-1", "turn": turn("turn-1", "completed")}})
        emit({"method": "future/event", "params": {"newField": True}})
        emit({"method": "future/request", "id": "future-1", "params": {}})
        emit({"method": "item/commandExecution/requestApproval", "id": "approval-1", "params": {
            "threadId": "thread-1", "turnId": "turn-1", "itemId": "cmd-2",
            "startedAtMs": 1, "environmentId": "local", "command": "git status --short",
            "cwd": "/tmp/project", "reason": "fixture approval"
        }})
        emit({"method": "item/fileChange/requestApproval", "id": "approval-2", "params": {
            "threadId": "thread-1", "turnId": "turn-1", "itemId": "file-1",
            "reason": "write fixture diff", "grantRoot": "/tmp/project"
        }})
        emit({"method": "item/permissions/requestApproval", "id": "approval-3", "params": {
            "threadId": "thread-1", "turnId": "turn-1", "itemId": "permission-1",
            "reason": "read another directory", "permissions": {"read": ["/tmp/shared"]}
        }})
    elif method == "account/read":
        emit({"id": request_id, "result": {"account": {
            "type": "chatgpt", "email": "ben@example.com", "planType": "pro", "newAccountField": True
        }, "requiresOpenaiAuth": True}})
    elif method == "account/login/start":
        assert params == {"type": "chatgpt"}
        emit({"id": request_id, "result": {
            "type": "chatgpt", "loginId": "login-1", "authUrl": "https://chatgpt.com/login"
        }})
    elif method == "thread/list":
        assert params["limit"] == 25
        emit({"id": request_id, "result": {"data": [thread("thread-1")], "nextCursor": "next-page", "backwardsCursor": None}})
    elif method == "thread/start":
        assert params["approvalPolicy"] == "on-request"
        assert params["sandbox"] == "workspace-write"
        assert params["approvalsReviewer"] == "user"
        emit({"id": request_id, "result": {"thread": thread("thread-new")}})
    elif method == "thread/resume":
        if MODE == "missingThread" and params["threadId"] == "missing-thread":
            emit({"id": request_id, "error": {"code": -32600, "message": "thread not found: missing-thread"}})
        else:
            emit({"id": request_id, "result": {"thread": thread(params["threadId"])}})
    elif method == "thread/archive":
        emit({"id": request_id, "result": {}})
    elif method == "turn/start":
        assert params["input"][0]["text_elements"] == []
        emit({"id": request_id, "result": {"turn": turn("turn-new")}})
    elif method == "turn/steer":
        assert params["expectedTurnId"] == "turn-new"
        emit({"id": request_id, "result": {"turnId": "turn-new"}})
    elif method == "turn/interrupt":
        emit({"id": request_id, "result": {}})
    elif method is None and request_id == "future-1":
        assert message["error"]["code"] == -32601
    elif method is None and request_id == "approval-1":
        assert message["result"] == {"decision": "decline"}
    elif method is None and request_id == "approval-2":
        assert message["result"] == {"decision": "accept"}
    elif method is None and request_id == "approval-3":
        assert message["result"] == {"permissions": {"read": ["/tmp/shared"]}, "scope": "session"}
    else:
        emit({"id": request_id, "error": {"code": -32601, "message": "fixture does not implement request"}})
"""#
}
