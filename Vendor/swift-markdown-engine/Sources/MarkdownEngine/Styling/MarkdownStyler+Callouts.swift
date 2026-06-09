//
//  MarkdownStyler+Callouts.swift
//  MarkdownEngine
//
//  Obsidian-style blockquote callout rendering.
//

import AppKit
import Foundation

extension MarkdownStyler {

    static func styleCallouts(_ ctx: StylingContext) -> [StyledRange] {
        var attrs: [StyledRange] = []
        let blockCodeTokens = ctx.codeTokens.filter { $0.kind == .codeBlock }

        for (idx, token) in ctx.tokens.enumerated() where token.kind == .callout {
            if MarkdownDetection.isInsideCodeBlock(range: token.range, codeTokens: blockCodeTokens) { continue }

            let source = ctx.nsText.substring(with: token.contentRange)
            guard let callout = MarkdownCalloutParser.parseCalloutBlock(source) else { continue }

            attrs.append((token.range, [NSAttributedString.Key.spellingState: 0]))

            if ctx.activeTokenIndices.contains(idx) {
                attrs.append(contentsOf: activeCalloutSourceAttributes(for: token, source: source, callout: callout, ctx: ctx))
                continue
            }

            guard let image = MarkdownCalloutRenderer.render(callout: callout, ctx: ctx) else {
                attrs.append(contentsOf: activeCalloutSourceAttributes(for: token, source: source, callout: callout, ctx: ctx))
                continue
            }

            let rendered = appendRenderedStandaloneBlock(
                for: token,
                rawContent: source,
                image: image,
                imageBounds: CGRect(origin: .zero, size: image.size),
                paragraphSpacingBefore: ctx.configuration.callout.paragraphSpacingBefore,
                paragraphSpacing: ctx.configuration.callout.paragraphSpacing,
                alignment: .left,
                mode: .collapsedSource(markerTexts: []),
                ctx: ctx,
                attrs: &attrs
            )

            if !rendered {
                attrs.append(contentsOf: activeCalloutSourceAttributes(for: token, source: source, callout: callout, ctx: ctx))
            }
        }

        return attrs
    }

    private static func activeCalloutSourceAttributes(
        for token: MarkdownToken,
        source: String,
        callout: MarkdownCallout,
        ctx: StylingContext
    ) -> [StyledRange] {
        var attrs: [StyledRange] = []
        let accent = MarkdownCalloutRenderer.palette(for: callout.kind, theme: ctx.configuration.theme).accent
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = ctx.baseDefaultLineHeight + 1
        paragraph.maximumLineHeight = ctx.baseDefaultLineHeight + 1
        paragraph.paragraphSpacing = ctx.baseParagraphSpacing

        attrs.append((token.range, [.paragraphStyle: paragraph]))

        let nsSource = source as NSString
        var cursor = 0
        while cursor < nsSource.length {
            var lineStart = 0
            var lineEnd = 0
            var contentsEnd = 0
            nsSource.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: cursor, length: 0))
            let lineRange = NSRange(location: lineStart, length: max(0, contentsEnd - lineStart))
            let line = nsSource.substring(with: lineRange) as NSString

            if let quoteOffset = firstQuoteOffset(in: line as String) {
                let quoteRange = NSRange(location: token.range.location + lineStart + quoteOffset, length: 1)
                attrs.append((quoteRange, [.foregroundColor: ctx.configuration.theme.mutedText]))

                let markerStart = quoteOffset + 1
                if markerStart < line.length {
                    let afterQuote = line.substring(from: markerStart) as NSString
                    let leadingSpace = afterQuote.hasPrefix(" ") || afterQuote.hasPrefix("\t") ? 1 : 0
                    let markerCandidateLocation = markerStart + leadingSpace
                    if markerCandidateLocation < line.length,
                       line.substring(from: markerCandidateLocation).hasPrefix("[!") {
                        let markerSearchRange = NSRange(location: markerCandidateLocation, length: line.length - markerCandidateLocation)
                        if let closeRange = line.range(of: "]", options: [], range: markerSearchRange).nonNotFound {
                            let markerRange = NSRange(
                                location: token.range.location + lineStart + markerCandidateLocation,
                                length: closeRange.location + closeRange.length - markerCandidateLocation
                            )
                            attrs.append((markerRange, [
                                .foregroundColor: accent,
                                .font: NSFontManager.shared.convert(ctx.baseFont, toHaveTrait: .boldFontMask)
                            ]))
                        }
                    }
                }
            }

            if lineEnd <= cursor { break }
            cursor = lineEnd
        }

        return attrs
    }

    private static func firstQuoteOffset(in line: String) -> Int? {
        var offset = 0
        for character in line {
            if character == " " || character == "\t" {
                offset += 1
                if offset <= 3 { continue }
            }
            return character == ">" ? offset : nil
        }
        return nil
    }
}

private enum MarkdownCalloutRenderer {
    struct Palette {
        let accent: NSColor
        let background: NSColor
        let border: NSColor
        let title: NSColor
        let body: NSColor
    }

    static func palette(for kind: String, theme: MarkdownEditorTheme) -> Palette {
        let accent: NSColor
        switch kind.lowercased() {
        case "tip", "hint", "success", "check", "done":
            accent = .systemGreen
        case "warning", "warn", "caution", "attention", "important":
            accent = .systemOrange
        case "danger", "error", "failure", "fail", "missing", "bug":
            accent = .systemRed
        case "question", "help", "faq":
            accent = .systemPurple
        case "example":
            accent = .systemIndigo
        case "quote", "cite":
            accent = theme.mutedText
        default:
            accent = .systemBlue
        }

        return Palette(
            accent: accent,
            background: accent.withAlphaComponent(0.115),
            border: accent.withAlphaComponent(0.32),
            title: accent.withAlphaComponent(0.98),
            body: theme.bodyText.withAlphaComponent(0.86)
        )
    }

    static func render(callout: MarkdownCallout, ctx: MarkdownStyler.StylingContext) -> NSImage? {
        let config = ctx.configuration.callout
        let maxWidth = calloutMaxWidth(ctx: ctx)
        let width = max(config.minimumWidth, maxWidth)
        let contentX = config.horizontalPadding + config.accentWidth + 9
        let contentWidth = max(60, width - contentX - config.horizontalPadding)

        let palette = palette(for: callout.kind, theme: ctx.configuration.theme)
        let titleFont = NSFontManager.shared.convert(ctx.baseFont, toHaveTrait: .boldFontMask)
        let bodyFont = ctx.baseFont
        let title = attributedTitle(callout.title, font: titleFont, color: palette.title)
        let body = attributedBody(callout.body, font: bodyFont, color: palette.body)

        let titleTextWidth = ceil(title.size().width)
        let titleHeight = ceil(titleFont.ascender - titleFont.descender + titleFont.leading)
        let titleRowHeight = max(config.iconSize, titleHeight)
        let bodyHeight = callout.body.isEmpty
            ? 0
            : textHeight(body, font: bodyFont, width: contentWidth)
        let height = ceil(
            config.verticalPadding
            + titleRowHeight
            + (bodyHeight > 0 ? config.bodyTopSpacing + bodyHeight : 0)
            + config.verticalPadding
        )
        guard width > 0, height > 0 else { return nil }

        let image = NSImage(size: CGSize(width: width, height: height), flipped: true) { rect in
            drawCallout(
                callout: callout,
                rect: rect,
                title: title,
                body: body,
                titleTextWidth: titleTextWidth,
                contentX: contentX,
                contentWidth: contentWidth,
                titleRowHeight: titleRowHeight,
                palette: palette,
                config: config
            )
            return true
        }
        return image
    }

    private static func calloutMaxWidth(ctx: MarkdownStyler.StylingContext) -> CGFloat {
        if let textContainer = ctx.layoutBridge?.firstTextContainer {
            let width = textContainer.containerSize.width - textContainer.lineFragmentPadding * 2
            if width > 0 && width < 10_000 {
                return max(160, width)
            }
        }
        return ctx.configuration.callout.fallbackMaxWidth
    }

    private static func drawCallout(
        callout: MarkdownCallout,
        rect: CGRect,
        title: NSAttributedString,
        body: NSAttributedString,
        titleTextWidth: CGFloat,
        contentX: CGFloat,
        contentWidth: CGFloat,
        titleRowHeight: CGFloat,
        palette: Palette,
        config: CalloutStyle
    ) {
        let bounds = rect.insetBy(dx: config.borderWidth / 2, dy: config.borderWidth / 2)
        let rounded = NSBezierPath(
            roundedRect: bounds,
            xRadius: config.cornerRadius,
            yRadius: config.cornerRadius
        )
        palette.background.setFill()
        rounded.fill()
        palette.border.setStroke()
        rounded.lineWidth = config.borderWidth
        rounded.stroke()

        let accentRect = CGRect(
            x: bounds.minX,
            y: bounds.minY,
            width: config.accentWidth,
            height: bounds.height
        )
        let accentPath = NSBezierPath(
            roundedRect: accentRect,
            xRadius: config.cornerRadius,
            yRadius: config.cornerRadius
        )
        palette.accent.setFill()
        accentPath.fill()

        let titleY = config.verticalPadding
        let iconRect = CGRect(
            x: contentX,
            y: titleY + (titleRowHeight - config.iconSize) / 2,
            width: config.iconSize,
            height: config.iconSize
        )
        drawIcon(for: callout.kind, in: iconRect, palette: palette)

        let titleRect = CGRect(
            x: iconRect.maxX + config.titleGap,
            y: titleY + (titleRowHeight - title.size().height) / 2,
            width: min(titleTextWidth + 2, max(10, contentWidth - config.iconSize - config.titleGap)),
            height: max(title.size().height, titleRowHeight)
        )
        title.draw(with: titleRect, options: [.usesLineFragmentOrigin, .usesFontLeading])

        if body.length > 0 {
            let bodyRect = CGRect(
                x: contentX,
                y: titleY + titleRowHeight + config.bodyTopSpacing,
                width: contentWidth,
                height: rect.height - titleY - titleRowHeight - config.bodyTopSpacing - config.verticalPadding
            )
            body.draw(with: bodyRect, options: [.usesLineFragmentOrigin, .usesFontLeading])
        }
    }

    private static func drawIcon(for kind: String, in rect: CGRect, palette: Palette) {
        let circle = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
        palette.accent.withAlphaComponent(0.18).setFill()
        circle.fill()
        palette.accent.withAlphaComponent(0.75).setStroke()
        circle.lineWidth = 1
        circle.stroke()

        let glyph: String
        switch kind.lowercased() {
        case "tip", "hint", "success", "check", "done":
            glyph = "v"
        case "question", "help", "faq":
            glyph = "?"
        case "note", "info", "abstract", "summary", "tldr":
            glyph = "i"
        case "quote", "cite":
            glyph = "\""
        default:
            glyph = "!"
        }

        let font = NSFont.systemFont(ofSize: max(10, rect.height * 0.62), weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: palette.accent
        ]
        let glyphSize = (glyph as NSString).size(withAttributes: attrs)
        let glyphRect = CGRect(
            x: rect.midX - glyphSize.width / 2,
            y: rect.midY - glyphSize.height / 2 - 0.5,
            width: glyphSize.width,
            height: glyphSize.height
        )
        (glyph as NSString).draw(in: glyphRect, withAttributes: attrs)
    }

    private static func attributedTitle(_ text: String, font: NSFont, color: NSColor) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: color
        ])
    }

    private static func attributedBody(_ text: String, font: NSFont, color: NSColor) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = 1.5
        paragraph.paragraphSpacing = 4
        return NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ])
    }

    private static func textHeight(_ text: NSAttributedString, font: NSFont, width: CGFloat) -> CGFloat {
        let fallbackLineHeight = ceil(font.ascender - font.descender + font.leading)
        guard text.length > 0 else { return fallbackLineHeight }
        let bounds = text.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return max(fallbackLineHeight, ceil(bounds.height))
    }
}

private extension NSRange {
    var nonNotFound: NSRange? {
        location == NSNotFound ? nil : self
    }
}
