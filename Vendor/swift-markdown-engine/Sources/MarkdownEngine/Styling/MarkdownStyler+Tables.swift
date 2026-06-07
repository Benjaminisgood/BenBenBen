//
//  MarkdownStyler+Tables.swift
//  MarkdownEngine
//
//  GitHub-style pipe table rendering.
//

import AppKit
import Foundation

extension MarkdownStyler {

    static func styleTables(_ ctx: StylingContext) -> [StyledRange] {
        var attrs: [StyledRange] = []

        for (idx, token) in ctx.tokens.enumerated() where token.kind == .table {
            if MarkdownDetection.isInsideCodeBlock(range: token.range, codeTokens: ctx.codeTokens) { continue }

            let source = ctx.nsText.substring(with: token.contentRange)
            guard let table = MarkdownTableParser.parseTableBlock(source) else { continue }

            attrs.append((token.range, [NSAttributedString.Key.spellingState: 0]))

            if ctx.activeTokenIndices.contains(idx) {
                attrs.append(contentsOf: activeTableSourceAttributes(for: token, source: source, ctx: ctx))
                continue
            }

            guard let image = MarkdownTableRenderer.render(table: table, ctx: ctx) else {
                attrs.append(contentsOf: activeTableSourceAttributes(for: token, source: source, ctx: ctx))
                continue
            }

            let rendered = appendRenderedStandaloneBlock(
                for: token,
                rawContent: source,
                image: image,
                imageBounds: CGRect(origin: .zero, size: image.size),
                paragraphSpacingBefore: ctx.configuration.table.paragraphSpacingBefore,
                paragraphSpacing: ctx.configuration.table.paragraphSpacing,
                alignment: .left,
                mode: .collapsedSource(markerTexts: []),
                ctx: ctx,
                attrs: &attrs
            )

            if !rendered {
                attrs.append(contentsOf: activeTableSourceAttributes(for: token, source: source, ctx: ctx))
            }
        }

        return attrs
    }

    private static func activeTableSourceAttributes(
        for token: MarkdownToken,
        source: String,
        ctx: StylingContext
    ) -> [StyledRange] {
        var attrs: [StyledRange] = []
        let lineHeight = ceil(ctx.codeFont.ascender - ctx.codeFont.descender + ctx.codeFont.leading)
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        paragraph.lineSpacing = 0
        paragraph.paragraphSpacing = ctx.baseParagraphSpacing

        attrs.append((token.range, [
            .font: ctx.codeFont,
            .paragraphStyle: paragraph
        ]))

        for (offset, codeUnit) in source.utf16.enumerated() where codeUnit == 124 || codeUnit == 45 || codeUnit == 58 {
            let range = NSRange(location: token.range.location + offset, length: 1)
            attrs.append((range, [.foregroundColor: ctx.configuration.theme.mutedText]))
        }

        return attrs
    }
}

private enum MarkdownTableRenderer {
    static func render(table: MarkdownTable, ctx: MarkdownStyler.StylingContext) -> NSImage? {
        let config = ctx.configuration.table
        let columnCount = table.header.count
        guard columnCount > 0 else { return nil }

        let headerFont = NSFontManager.shared.convert(ctx.baseFont, toHaveTrait: .boldFontMask)
        let bodyFont = ctx.baseFont
        let theme = ctx.configuration.theme
        let renderedRows = renderedCellRows(
            table: table,
            headerFont: headerFont,
            bodyFont: bodyFont,
            theme: theme,
            ctx: ctx
        )
        let maxWidth = tableMaxWidth(ctx: ctx)
        let columnWidths = resolvedColumnWidths(
            renderedRows: renderedRows,
            config: config,
            maxWidth: maxWidth
        )
        guard !columnWidths.isEmpty else { return nil }

        let rowHeights = renderedRows.enumerated().map { index, row in
            resolvedRowHeight(
                row: row,
                isHeader: index == 0,
                columnWidths: columnWidths,
                headerFont: headerFont,
                bodyFont: bodyFont,
                config: config
            )
        }
        let tableWidth = ceil(columnWidths.reduce(0, +))
        let tableHeight = ceil(rowHeights.reduce(0, +))
        guard tableWidth > 0, tableHeight > 0 else { return nil }

        let image = NSImage(size: CGSize(width: tableWidth, height: tableHeight), flipped: true) { rect in
            drawTable(
                table: table,
                renderedRows: renderedRows,
                rect: rect,
                columnWidths: columnWidths,
                rowHeights: rowHeights,
                theme: theme,
                config: config
            )
            return true
        }
        return image
    }

    private static func tableMaxWidth(ctx: MarkdownStyler.StylingContext) -> CGFloat {
        if let textContainer = ctx.layoutBridge?.firstTextContainer {
            let width = textContainer.containerSize.width - textContainer.lineFragmentPadding * 2
            if width > 0 && width < 10_000 {
                return max(120, width)
            }
        }
        return ctx.configuration.table.fallbackMaxWidth
    }

    private static func renderedCellRows(
        table: MarkdownTable,
        headerFont: NSFont,
        bodyFont: NSFont,
        theme: MarkdownEditorTheme,
        ctx: MarkdownStyler.StylingContext
    ) -> [[NSAttributedString]] {
        let rows = [table.header] + table.rows
        return rows.enumerated().map { rowIndex, row in
            let isHeader = rowIndex == 0
            let font = isHeader ? headerFont : bodyFont
            let color = isHeader
                ? theme.bodyText.withAlphaComponent(0.92)
                : theme.bodyText.withAlphaComponent(0.78)
            return row.map {
                attributedCellText($0, font: font, color: color, ctx: ctx)
            }
        }
    }

    private static func resolvedColumnWidths(
        renderedRows: [[NSAttributedString]],
        config: TableStyle,
        maxWidth: CGFloat
    ) -> [CGFloat] {
        let columnCount = renderedRows.first?.count ?? 0

        var widths = (0..<columnCount).map { column -> CGFloat in
            let maxTextWidth = renderedRows.map { row -> CGFloat in
                guard row.indices.contains(column) else { return 0 }
                return attributedTextWidth(row[column])
            }.max() ?? 0

            return min(
                max(maxTextWidth + config.cellHorizontalPadding * 2, config.minimumColumnWidth),
                config.maximumColumnWidth
            )
        }

        let total = widths.reduce(0, +)
        guard total > maxWidth else { return widths.map(ceil) }

        let minWidth = max(36, min(config.minimumColumnWidth, maxWidth / CGFloat(max(columnCount, 1))))
        let minTotal = minWidth * CGFloat(columnCount)
        if minTotal >= maxWidth {
            let compressed = maxWidth / CGFloat(columnCount)
            return widths.map { _ in floor(compressed) }
        }

        let extraTotal = widths.reduce(0) { $0 + max(0, $1 - minWidth) }
        let allowedExtra = maxWidth - minTotal
        widths = widths.map { width in
            let extra = max(0, width - minWidth)
            let scaledExtra = extraTotal > 0 ? extra / extraTotal * allowedExtra : 0
            return minWidth + scaledExtra
        }
        return widths.map(floor)
    }

    private static func resolvedRowHeight(
        row: [NSAttributedString],
        isHeader: Bool,
        columnWidths: [CGFloat],
        headerFont: NSFont,
        bodyFont: NSFont,
        config: TableStyle
    ) -> CGFloat {
        let font = isHeader ? headerFont : bodyFont
        let contentHeights = columnWidths.enumerated().map { column, width -> CGFloat in
            let text = row.indices.contains(column) ? row[column] : NSAttributedString()
            let contentWidth = max(12, width - config.cellHorizontalPadding * 2)
            return textHeight(text, font: font, width: contentWidth)
        }
        let fallbackLineHeight = ceil(font.ascender - font.descender + font.leading)
        return ceil((contentHeights.max() ?? fallbackLineHeight) + config.cellVerticalPadding * 2)
    }

    private static func drawTable(
        table: MarkdownTable,
        renderedRows: [[NSAttributedString]],
        rect: CGRect,
        columnWidths: [CGFloat],
        rowHeights: [CGFloat],
        theme: MarkdownEditorTheme,
        config: TableStyle
    ) {
        let rounded = NSBezierPath(
            roundedRect: rect.insetBy(dx: config.borderWidth / 2, dy: config.borderWidth / 2),
            xRadius: config.cornerRadius,
            yRadius: config.cornerRadius
        )
        NSGraphicsContext.saveGraphicsState()
        rounded.addClip()

        let backgroundColor = theme.bodyText.withAlphaComponent(0.035)
        let headerBackground = theme.bodyText.withAlphaComponent(0.10)
        let stripeBackground = theme.bodyText.withAlphaComponent(0.055)
        let borderColor = theme.mutedText.withAlphaComponent(0.28)

        backgroundColor.setFill()
        rect.fill()

        var y: CGFloat = 0
        for (rowIndex, row) in renderedRows.enumerated() {
            let rowHeight = rowHeights[rowIndex]
            let rowRect = CGRect(x: 0, y: y, width: rect.width, height: rowHeight)

            if rowIndex == 0 {
                headerBackground.setFill()
                rowRect.fill()
            } else if rowIndex % 2 == 0 {
                stripeBackground.setFill()
                rowRect.fill()
            }

            var x: CGFloat = 0
            for (column, columnWidth) in columnWidths.enumerated() {
                let cell = row.indices.contains(column) ? row[column] : NSAttributedString()
                let alignment = table.alignments.indices.contains(column) ? table.alignments[column] : .left
                let cellRect = CGRect(x: x, y: y, width: columnWidth, height: rowHeight)
                    .insetBy(dx: config.cellHorizontalPadding, dy: config.cellVerticalPadding)
                drawText(cell, in: cellRect, alignment: alignment)
                x += columnWidth
            }

            y += rowHeight
        }

        borderColor.setStroke()
        let grid = NSBezierPath()
        grid.lineWidth = config.borderWidth

        var x: CGFloat = 0
        for width in columnWidths.dropLast() {
            x += width
            grid.move(to: CGPoint(x: x, y: 0))
            grid.line(to: CGPoint(x: x, y: rect.height))
        }

        y = 0
        for height in rowHeights.dropLast() {
            y += height
            grid.move(to: CGPoint(x: 0, y: y))
            grid.line(to: CGPoint(x: rect.width, y: y))
        }

        grid.stroke()
        NSGraphicsContext.restoreGraphicsState()

        borderColor.setStroke()
        rounded.lineWidth = config.borderWidth
        rounded.stroke()
    }

    private static func drawText(
        _ text: NSAttributedString,
        in rect: CGRect,
        alignment: MarkdownTableAlignment
    ) {
        guard text.length > 0 else { return }
        let mutableText = NSMutableAttributedString(attributedString: text)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        switch alignment {
        case .left:
            paragraph.alignment = .left
        case .center:
            paragraph.alignment = .center
        case .right:
            paragraph.alignment = .right
        }
        mutableText.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: mutableText.length))

        mutableText.draw(
            with: rect,
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
    }

    private static func attributedCellText(
        _ text: String,
        font: NSFont,
        color: NSColor,
        ctx: MarkdownStyler.StylingContext
    ) -> NSAttributedString {
        let fallbackAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let output = NSMutableAttributedString()
        let nsText = text as NSString
        let inlineLatexTokens = MarkdownTokenizer.parseTokens(in: text)
            .filter { $0.kind == .inlineLatex }
            .sorted { $0.range.location < $1.range.location }

        var cursor = 0
        for token in inlineLatexTokens {
            guard token.range.location >= cursor,
                  NSMaxRange(token.range) <= nsText.length else {
                continue
            }

            if token.range.location > cursor {
                let plainRange = NSRange(location: cursor, length: token.range.location - cursor)
                output.append(NSAttributedString(
                    string: nsText.substring(with: plainRange),
                    attributes: fallbackAttributes
                ))
            }

            let rawToken = nsText.substring(with: token.range)
            let latexContent = nsText.substring(with: token.contentRange)
            if let entry = ctx.services.latex.render(latex: latexContent, fontSize: font.pointSize, theme: ctx.configuration.theme) {
                let attachment = NSTextAttachment()
                attachment.image = entry.image
                attachment.bounds = CGRect(
                    x: 0,
                    y: -entry.baselineOffset,
                    width: entry.size.width,
                    height: entry.size.height
                )
                output.append(NSAttributedString(attachment: attachment))
            } else {
                output.append(NSAttributedString(
                    string: rawToken,
                    attributes: fallbackAttributes
                ))
            }
            cursor = NSMaxRange(token.range)
        }

        if cursor < nsText.length {
            let tailRange = NSRange(location: cursor, length: nsText.length - cursor)
            output.append(NSAttributedString(
                string: nsText.substring(with: tailRange),
                attributes: fallbackAttributes
            ))
        }

        return output
    }

    private static func attributedTextWidth(_ text: NSAttributedString) -> CGFloat {
        guard text.length > 0 else { return 0 }
        return ceil(text.size().width)
    }

    private static func textHeight(_ text: NSAttributedString, font: NSFont, width: CGFloat) -> CGFloat {
        let fallbackLineHeight = ceil(font.ascender - font.descender + font.leading)
        guard text.length > 0 else { return fallbackLineHeight }

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let mutableText = NSMutableAttributedString(attributedString: text)
        mutableText.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: mutableText.length))
        let bounds = mutableText.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return max(fallbackLineHeight, ceil(bounds.height))
    }
}
