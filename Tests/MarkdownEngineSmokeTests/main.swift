import AppKit
import Foundation

enum MarkdownEngineSmokeTestFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message):
            return message
        }
    }
}

@main
struct MarkdownEngineSmokeTests {
    static func main() throws {
        try testTableWithInlineCodeCellRendersAsImage()
        try testImportantCalloutRendersAsImageWhenInactive()
        try testStandardDashBulletReceivesVisualBulletAttribute()
        print("Markdown engine smoke tests passed")
    }

    private static func testTableWithInlineCodeCellRendersAsImage() throws {
        let text = """
        | 项目 | 内容 |
        | --- | --- |
        | 论文 | Gleaves, J. T.; Ebner, J. R.; Kuechler, T. C. Temporal Analysis of Products (TAP): A Unique Catalyst Evaluation System with Submillisecond Time Resolution |
        | 期刊 | Catalysis Reviews Science and Engineering, 1988, 30(1), 49-116 |
        | DOI | 10.1080/01614948808078616 |
        | 本页范围 | I. Introduction; II. Transient Experiments; III. The TAP Experiment |
        | 本地原文 | `/Users/ben/Desktop/TAP/Temporal Analysis of Products  TAP  A Unique Catalyst Evaluation System with Submillisecond Time Resolution.pdf` |
        """

        let tokens = MarkdownTokenizer.parseTokens(in: text)
        try expect(tokens.filter { $0.kind == .table }.count == 1, "Expected one table token")
        try expect(tokens.filter { $0.kind == .inlineCode }.count == 1, "Expected inline code inside the table")

        let attributes = MarkdownStyler.styleAttributes(
            text: text,
            fontName: "SF Pro",
            fontSize: 15,
            caretLocation: (text as NSString).length,
            activeTokenIndices: [],
            precomputedTokens: tokens
        )

        try expect(attributes.contains { _, attrs in
            attrs[.latexImage] is NSImage
        }, "Expected rendered table image attributes")
    }

    private static func testImportantCalloutRendersAsImageWhenInactive() throws {
        let text = """
        > [!important]
        > 这个方法依赖 Knudsen diffusion 已经可靠标定。若惰性气体曲线受黏性流、死体积或仪器函数影响，后续脱附能都会偏。
        """

        let tokens = MarkdownTokenizer.parseTokens(in: text)
        try expect(tokens.filter { $0.kind == .callout }.count == 1, "Expected one callout token")

        let attributes = MarkdownStyler.styleAttributes(
            text: text,
            fontName: "SF Pro",
            fontSize: 15,
            caretLocation: (text as NSString).length,
            activeTokenIndices: [],
            precomputedTokens: tokens
        )

        try expect(attributes.contains { _, attrs in
            attrs[.latexImage] is NSImage
        }, "Expected rendered callout image attributes")
    }

    private static func testStandardDashBulletReceivesVisualBulletAttribute() throws {
        let text = "- 粘贴来的列表项"

        let attributes = MarkdownStyler.styleAttributes(
            text: text,
            fontName: "SF Pro",
            fontSize: 15,
            caretLocation: (text as NSString).length,
            activeTokenIndices: []
        )

        try expect(attributes.contains { range, attrs in
            range.location == 0 && range.length == 1 && attrs[.markdownListBullet] != nil
        }, "Expected dash marker to receive visual bullet attributes")
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) throws {
        guard condition() else {
            throw MarkdownEngineSmokeTestFailure.failed(message)
        }
    }
}
