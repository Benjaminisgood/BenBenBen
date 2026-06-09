//
//  MarkdownCalloutParser.swift
//  MarkdownEngine
//
//  Obsidian-style blockquote callout parsing.
//

import Foundation

struct MarkdownCallout {
    let kind: String
    let title: String
    let body: String
    let range: NSRange
}

enum MarkdownCalloutParser {
    private struct LineInfo {
        let text: String
        let range: NSRange
        let lineEnd: Int
    }

    private struct MarkerLine {
        let kind: String
        let title: String?
    }

    private static let markerRegex = try! NSRegularExpression(
        pattern: #"^\[!([A-Za-z][A-Za-z0-9_-]*)\]([+-]?)(?:[ \t]+([^\r\n]+))?[ \t]*$"#
    )

    static func parseCallouts(in text: String, excluding excludedRanges: [NSRange]) -> [MarkdownCallout] {
        let nsText = text as NSString
        let lines = lineInfos(in: nsText)
        guard !lines.isEmpty else { return [] }

        var callouts: [MarkdownCallout] = []
        var index = 0

        while index < lines.count {
            let markerCandidate = lines[index]
            guard !overlapsAny(markerCandidate.range, excludedRanges),
                  let marker = parseMarkerLine(markerCandidate.text) else {
                index += 1
                continue
            }

            var bodyLines: [String] = []
            var blockEnd = markerCandidate.lineEnd
            var rowIndex = index + 1

            while rowIndex < lines.count {
                let line = lines[rowIndex]
                if overlapsAny(line.range, excludedRanges) { break }
                guard let quoteContent = strippedQuoteContent(from: line.text) else { break }

                bodyLines.append(quoteContent)
                blockEnd = line.lineEnd
                rowIndex += 1
            }

            let body = bodyLines.joined(separator: "\n")
                .trimmingCharacters(in: .newlines)
            let range = NSRange(
                location: markerCandidate.range.location,
                length: blockEnd - markerCandidate.range.location
            )
            callouts.append(MarkdownCallout(
                kind: marker.kind.lowercased(),
                title: marker.title ?? displayTitle(for: marker.kind),
                body: body,
                range: range
            ))
            index = max(rowIndex, index + 1)
        }

        return callouts
    }

    static func parseCalloutBlock(_ source: String) -> MarkdownCallout? {
        parseCallouts(in: source, excluding: []).first
    }

    static func displayTitle(for kind: String) -> String {
        switch kind.lowercased() {
        case "note":
            return "Note"
        case "abstract", "summary", "tldr":
            return "Summary"
        case "info":
            return "Info"
        case "todo":
            return "Todo"
        case "tip", "hint":
            return "Tip"
        case "success", "check", "done":
            return "Success"
        case "question", "help", "faq":
            return "Question"
        case "warning", "warn", "caution", "attention":
            return "Warning"
        case "important":
            return "Important"
        case "failure", "fail", "missing":
            return "Failure"
        case "danger", "error":
            return "Danger"
        case "bug":
            return "Bug"
        case "example":
            return "Example"
        case "quote", "cite":
            return "Quote"
        default:
            return kind.prefix(1).uppercased() + kind.dropFirst()
        }
    }

    private static func parseMarkerLine(_ line: String) -> MarkerLine? {
        guard let quoteContent = strippedQuoteContent(from: line) else { return nil }
        let nsContent = quoteContent as NSString
        let fullRange = NSRange(location: 0, length: nsContent.length)
        guard let match = markerRegex.firstMatch(in: quoteContent, options: [], range: fullRange) else {
            return nil
        }

        let kind = nsContent.substring(with: match.range(at: 1))
        let rawTitle: String? = {
            let titleRange = match.range(at: 3)
            guard titleRange.location != NSNotFound else { return nil }
            let title = nsContent.substring(with: titleRange)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? nil : title
        }()
        return MarkerLine(kind: kind, title: rawTitle)
    }

    private static func strippedQuoteContent(from line: String) -> String? {
        var index = line.startIndex
        var skippedIndent = 0
        while index < line.endIndex, skippedIndent < 3 {
            let character = line[index]
            guard character == " " || character == "\t" else { break }
            skippedIndent += character == "\t" ? 3 : 1
            index = line.index(after: index)
        }

        guard index < line.endIndex, line[index] == ">" else { return nil }
        index = line.index(after: index)

        if index < line.endIndex, (line[index] == " " || line[index] == "\t") {
            index = line.index(after: index)
        }

        return String(line[index...])
    }

    private static func lineInfos(in text: NSString) -> [LineInfo] {
        var lines: [LineInfo] = []
        var cursor = 0

        while cursor < text.length {
            var lineStart = 0
            var lineEnd = 0
            var contentsEnd = 0
            text.getLineStart(
                &lineStart,
                end: &lineEnd,
                contentsEnd: &contentsEnd,
                for: NSRange(location: cursor, length: 0)
            )

            let contentRange = NSRange(location: lineStart, length: max(0, contentsEnd - lineStart))
            lines.append(LineInfo(
                text: text.substring(with: contentRange),
                range: contentRange,
                lineEnd: lineEnd
            ))

            if lineEnd <= cursor { break }
            cursor = lineEnd
        }

        return lines
    }

    private static func overlapsAny(_ range: NSRange, _ candidates: [NSRange]) -> Bool {
        candidates.contains { NSIntersectionRange(range, $0).length > 0 }
    }
}
