//
//  MarkdownTableParser.swift
//  MarkdownEngine
//
//  GitHub-style pipe table parsing shared by tokenization and rendering.
//

import Foundation

enum MarkdownTableAlignment {
    case left
    case center
    case right
}

struct MarkdownTable {
    let header: [String]
    let alignments: [MarkdownTableAlignment]
    let rows: [[String]]
    let range: NSRange
}

enum MarkdownTableParser {
    private struct LineInfo {
        let text: String
        let range: NSRange
        let lineEnd: Int
    }

    static func parseTables(in text: String, excluding excludedRanges: [NSRange]) -> [MarkdownTable] {
        let nsText = text as NSString
        let lines = lineInfos(in: nsText)
        guard lines.count >= 2 else { return [] }

        var tables: [MarkdownTable] = []
        var index = 0
        while index + 1 < lines.count {
            let headerLine = lines[index]
            let separatorLine = lines[index + 1]
            let headerCells = splitRow(headerLine.text)
            guard headerCells.count >= 2,
                  let alignments = parseSeparatorRow(separatorLine.text),
                  alignments.count >= 2 else {
                index += 1
                continue
            }

            let headerAndSeparatorRange = NSRange(
                location: headerLine.range.location,
                length: separatorLine.lineEnd - headerLine.range.location
            )
            guard !overlapsAny(headerAndSeparatorRange, excludedRanges) else {
                index += 1
                continue
            }

            let columnCount = max(headerCells.count, alignments.count)
            var rows: [[String]] = []
            var blockEnd = separatorLine.lineEnd
            var rowIndex = index + 2

            while rowIndex < lines.count {
                let rowLine = lines[rowIndex]
                let trimmed = rowLine.text.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty { break }
                if overlapsAny(rowLine.range, excludedRanges) { break }

                let cells = splitRow(rowLine.text)
                guard cells.count >= 2 else { break }
                rows.append(normalized(cells, count: columnCount))
                blockEnd = rowLine.lineEnd
                rowIndex += 1
            }

            let tokenRange = NSRange(
                location: headerLine.range.location,
                length: blockEnd - headerLine.range.location
            )
            tables.append(MarkdownTable(
                header: normalized(headerCells, count: columnCount),
                alignments: normalized(alignments, count: columnCount),
                rows: rows,
                range: tokenRange
            ))
            index = max(rowIndex, index + 2)
        }

        return tables
    }

    static func parseTableBlock(_ source: String) -> MarkdownTable? {
        parseTables(in: source, excluding: []).first
    }

    static func splitRow(_ line: String) -> [String] {
        var row = line.trimmingCharacters(in: .whitespaces)
        if row.first == "|" {
            row.removeFirst()
        }
        if row.last == "|", !lastPipeIsEscaped(in: row) {
            row.removeLast()
        }

        var cells: [String] = []
        var current = ""
        var isEscaped = false

        for character in row {
            if isEscaped {
                if character != "|" {
                    current.append("\\")
                }
                current.append(character)
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
            } else if character == "|" {
                cells.append(trimmedCell(current))
                current = ""
            } else {
                current.append(character)
            }
        }

        if isEscaped {
            current.append("\\")
        }
        cells.append(trimmedCell(current))
        return cells
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

    private static func parseSeparatorRow(_ line: String) -> [MarkdownTableAlignment]? {
        let cells = splitRow(line)
        guard cells.count >= 2 else { return nil }

        var alignments: [MarkdownTableAlignment] = []
        for rawCell in cells {
            let cell = rawCell
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "\t", with: "")
            guard isSeparatorCell(cell) else { return nil }

            switch (cell.hasPrefix(":"), cell.hasSuffix(":")) {
            case (true, true):
                alignments.append(.center)
            case (false, true):
                alignments.append(.right)
            default:
                alignments.append(.left)
            }
        }
        return alignments
    }

    private static func isSeparatorCell(_ cell: String) -> Bool {
        guard !cell.isEmpty else { return false }
        var value = cell
        if value.first == ":" { value.removeFirst() }
        if value.last == ":" { value.removeLast() }
        return value.count >= 3 && value.allSatisfy { $0 == "-" }
    }

    private static func normalized(_ cells: [String], count: Int) -> [String] {
        if cells.count == count { return cells }
        if cells.count > count { return Array(cells.prefix(count)) }
        return cells + Array(repeating: "", count: count - cells.count)
    }

    private static func normalized(_ alignments: [MarkdownTableAlignment], count: Int) -> [MarkdownTableAlignment] {
        if alignments.count == count { return alignments }
        if alignments.count > count { return Array(alignments.prefix(count)) }
        return alignments + Array(repeating: .left, count: count - alignments.count)
    }

    private static func trimmedCell(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespaces)
    }

    private static func overlapsAny(_ range: NSRange, _ candidates: [NSRange]) -> Bool {
        candidates.contains { NSIntersectionRange(range, $0).length > 0 }
    }

    private static func lastPipeIsEscaped(in row: String) -> Bool {
        guard row.last == "|" else { return false }
        var slashCount = 0
        var index = row.index(before: row.endIndex)
        while index > row.startIndex {
            index = row.index(before: index)
            if row[index] == "\\" {
                slashCount += 1
            } else {
                break
            }
        }
        return slashCount % 2 == 1
    }
}
