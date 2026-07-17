import XCTest
@testable import BenBenBen

final class VoiceCommandIntentTests: XCTestCase {
    func testScreenSharingVoiceCommands() {
        XCTAssertEqual(VoiceCommandIntent.parse("看看我的屏幕上有什么").screenAction, .enable)
        let stop = VoiceCommandIntent.parse("不要看屏幕了")
        XCTAssertEqual(stop.screenAction, .disable)
        XCTAssertTrue(stop.isPureScreenCommand)

        XCTAssertFalse(
            VoiceCommandIntent.parse("不要看屏幕了，继续执行当前任务").isPureScreenCommand
        )
    }

    func testPureWindowCommandFindsArtifactKind() {
        let intent = VoiceCommandIntent.parse("打开 MD 窗口里的实验记录")
        XCTAssertEqual(intent.artifactKind, .markdown)
        XCTAssertTrue(intent.isPureWindowCommand)
    }

    func testArtifactWorkRequestIsNotConsumedAsWindowOnlyCommand() {
        let intent = VoiceCommandIntent.parse("打开 Python 窗口并帮我分析这个文件")
        XCTAssertEqual(intent.artifactKind, .python)
        XCTAssertFalse(intent.isPureWindowCommand)
    }

    func testTaskDetailCommandTargetsSixthWindow() {
        let intent = VoiceCommandIntent.parse("显示任务详情")
        XCTAssertTrue(intent.showsTaskWindow)
        XCTAssertTrue(intent.isPureWindowCommand)
    }
}
