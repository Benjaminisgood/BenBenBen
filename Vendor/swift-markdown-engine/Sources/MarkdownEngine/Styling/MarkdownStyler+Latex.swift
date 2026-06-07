//
//  MarkdownStyler+Latex.swift
//  MarkdownEngine
//
//  Created by Luca Chen on 16.03.26.
//
//  Block ($$...$$) and inline ($...$) LaTeX formula rendering.
//

import AppKit
import Foundation

extension MarkdownStyler {

    // MARK: Block LaTeX $$...$$

    static func styleBlockLatex(_ ctx: StylingContext) -> [StyledRange] {
        var attrs: [StyledRange] = []
        let blockLatexTokens = ctx.tokens.enumerated().filter { $0.element.kind == .blockLatex }
        for (idx, token) in blockLatexTokens {
            if MarkdownDetection.isInsideCodeBlock(range: token.range, codeTokens: ctx.codeTokens) { continue }
            let isActive = ctx.activeTokenIndices.contains(idx)
            let rawLatexContent = ctx.nsText.substring(with: token.contentRange)
            let latexContent = rawLatexContent.trimmingCharacters(in: .whitespacesAndNewlines)

            attrs.append((token.range, [NSAttributedString.Key.spellingState: 0]))

            guard token.standaloneParagraphRange(in: ctx.nsText) != nil else { continue }

            let latexFontSize = HeadingHelpers.latexFontSize(for: token, tokens: ctx.tokens, baseFont: ctx.baseFont)

            if isActive {
                appendSecondaryMarkers(for: token, to: &attrs, theme: ctx.configuration.theme)
            } else if !latexContent.isEmpty,
                      let entry = renderFirstBlockLatexCandidate(latexContent, fontSize: latexFontSize, ctx: ctx) {
                _ = appendRenderedStandaloneBlock(
                    for: token,
                    rawContent: rawLatexContent,
                    image: entry.image,
                    imageBounds: CGRect(
                        x: 0,
                        y: entry.baselineOffset,
                        width: entry.size.width,
                        height: entry.size.height
                    ),
                    paragraphSpacingBefore: ctx.configuration.blockLatex.paragraphSpacingBefore,
                    paragraphSpacing: ctx.configuration.blockLatex.paragraphSpacing,
                    alignment: .center,
                    mode: .collapsedSource(markerTexts: token.markerRanges.map { ctx.nsText.substring(with: $0) }),
                    ctx: ctx,
                    attrs: &attrs
                )
            } else {
                appendSecondaryMarkers(for: token, to: &attrs, theme: ctx.configuration.theme)
            }
        }
        return attrs
    }

    private static func renderFirstBlockLatexCandidate(
        _ latex: String,
        fontSize: CGFloat,
        ctx: StylingContext
    ) -> LatexRenderResult? {
        for candidate in blockLatexRenderCandidates(from: latex) {
            if let entry = ctx.services.latex.render(latex: candidate, fontSize: fontSize, theme: ctx.configuration.theme) {
                return entry
            }
        }
        return nil
    }

    private static func blockLatexRenderCandidates(from latex: String) -> [String] {
        let trimmed = latex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let foldedLines = trimmed
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard foldedLines != trimmed else { return [trimmed] }
        return [trimmed, foldedLines]
    }

    // MARK: Inline LaTeX $formula$

    static func styleInlineLatex(_ ctx: StylingContext) -> [StyledRange] {
        var attrs: [StyledRange] = []
        for (idx, token) in ctx.tokens.enumerated() where token.kind == .inlineLatex {
            if MarkdownDetection.isInsideCodeBlock(range: token.range, codeTokens: ctx.codeTokens) { continue }

            attrs.append((token.range, [NSAttributedString.Key.spellingState: 0]))

            let isActive = ctx.activeTokenIndices.contains(idx)
            let latexContent = ctx.nsText.substring(with: token.contentRange)
            let latexFontSize = HeadingHelpers.latexFontSize(for: token, tokens: ctx.tokens, baseFont: ctx.baseFont)

            if isActive {
                for markerRange in token.markerRanges {
                    attrs.append((markerRange, [.foregroundColor: ctx.configuration.theme.mutedText]))
                }
            } else {
                if let entry = ctx.services.latex.render(latex: latexContent, fontSize: latexFontSize, theme: ctx.configuration.theme) {
                    let imageBounds = CGRect(x: 0, y: entry.baselineOffset, width: entry.size.width, height: entry.size.height)
                    let contentLength = token.contentRange.length
                    let openMarkerText = token.markerRanges.indices.contains(0)
                        ? ctx.nsText.substring(with: token.markerRanges[0])
                        : "$"
                    let closeMarkerText = token.markerRanges.indices.contains(1)
                        ? ctx.nsText.substring(with: token.markerRanges[1])
                        : "$"
                    let tinyOpenMarkerWidth = HeadingHelpers.textWidth(openMarkerText, font: ctx.latexMarkerFont)
                    let baseCloseMarkerWidth = HeadingHelpers.textWidth(closeMarkerText, font: ctx.baseFont)

                    if contentLength > 0 {
                        let firstCharRange = NSRange(location: token.contentRange.location, length: 1)
                        let firstChar = ctx.nsText.substring(with: firstCharRange)
                        attrs.append((firstCharRange, [
                            .latexImage: entry.image,
                            .latexBounds: NSValue(rect: imageBounds),
                            .foregroundColor: NSColor.clear,
                            .font: ctx.latexMarkerFont,
                            .kern: entry.size.width - HeadingHelpers.textWidth(firstChar, font: ctx.latexMarkerFont)
                        ]))

                        if contentLength > 1 {
                            let restRange = NSRange(location: token.contentRange.location + 1, length: contentLength - 1)
                            let restText = ctx.nsText.substring(with: restRange)
                            attrs.append((restRange, [
                                .foregroundColor: NSColor.clear,
                                .font: ctx.latexMarkerFont,
                                .kern: -HeadingHelpers.textWidth(restText, font: ctx.latexMarkerFont)
                            ]))
                        }
                    }

                    let openMarker = token.markerRanges[0]
                    attrs.append((openMarker, [
                        .font: ctx.latexMarkerFont,
                        .foregroundColor: NSColor.clear,
                        .kern: -tinyOpenMarkerWidth
                    ]))
                    let closeMarker = token.markerRanges[1]
                    attrs.append((closeMarker, [
                        .foregroundColor: NSColor.clear,
                        .kern: -baseCloseMarkerWidth
                    ]))
                } else {
                    for markerRange in token.markerRanges {
                        attrs.append((markerRange, [.foregroundColor: ctx.configuration.theme.mutedText]))
                    }
                }
            }
        }
        return attrs
    }
}
