import Foundation

protocol AgentRuntime: Sendable {
    func eventStream() -> AsyncStream<AgentEvent>
    func start() async throws -> CodexServerInfo
    func stop() async
    func readAccount(refreshToken: Bool) async throws -> AgentAccountStatus
    func startChatGPTLogin() async throws -> AgentLoginFlow
    func listThreads(_ query: AgentThreadListQuery) async throws -> AgentThreadPage
    func readThread(id: String, includeTurns: Bool) async throws -> AgentThreadHistory
    func startThread(_ options: AgentThreadStartOptions) async throws -> AgentThread
    func resumeThread(id: String, cwd: String?) async throws -> AgentThread
    func archiveThread(id: String) async throws
    func startTurn(
        threadID: String,
        text: String,
        localImagePath: String?,
        options: AgentTurnStartOptions
    ) async throws -> AgentTurn
    func steerTurn(threadID: String, turnID: String, text: String) async throws -> String
    func interruptTurn(threadID: String, turnID: String) async throws
    func respondToApproval(id: AgentRequestID, response: AgentApprovalResponse) async throws
}
