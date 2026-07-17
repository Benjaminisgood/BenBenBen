import XCTest
@testable import BenBenBen

final class AgentUserInputQuestionTests: XCTestCase {
    func testRequestProjectsQuestionsAndOptionsForTaskWindow() {
        let request = AgentApprovalRequest(
            id: .integer(1),
            kind: .userInput,
            method: "item/tool/requestUserInput",
            threadID: "thread-1",
            turnID: "turn-1",
            itemID: "item-1",
            reason: nil,
            command: nil,
            cwd: nil,
            rawParams: .object([
                "questions": .array([
                    .object([
                        "id": .string("choice"),
                        "header": .string("方案"),
                        "question": .string("选择哪一个？"),
                        "options": .array([
                            .object([
                                "label": .string("方案 A"),
                                "description": .string("更稳妥")
                            ])
                        ])
                    ])
                ])
            ])
        )

        XCTAssertEqual(request.userInputQuestions.first?.id, "choice")
        XCTAssertEqual(request.userInputQuestions.first?.options.first?.label, "方案 A")
    }
}
