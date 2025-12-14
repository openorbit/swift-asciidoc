//
// Copyright (c) 2025 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

import Foundation

private func parseDirectivePayload(_ payload: String) -> (target: String, body: String?) {
    guard let open = payload.firstIndex(of: "["),
          let close = payload.lastIndex(of: "]"),
          close > open else {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed, nil)
    }

    let targetSlice = payload[..<open]
    let bodySlice = payload[payload.index(after: open)..<close]

    let target = String(targetSlice).trimmingCharacters(in: .whitespacesAndNewlines)
    let body = String(bodySlice).trimmingCharacters(in: .whitespacesAndNewlines)

    return (
        target,
        body.isEmpty ? nil : body
    )
}

extension AdocParser {

    // Parse a sequence of blocks until `stop` says “this token belongs to the caller”.
    // Parse blocks until `stop` returns true for the *next* token.
    func parseBlocks(
        it: inout TokenIter,
        env: AttrEnv,
        stop: (Token) -> Bool
    ) -> [AdocBlock] {
        var blocks: [AdocBlock] = []

        while let tok = it.peek(), !stop(tok) {
            let before = it.index


            if let block = parseBlock(it: &it, env: env) {
                blocks.append(block)
            } else {
                // Safety to avoid infinite loops: always consume something.
                if it.index == before {
                    // TODO: Report ICE or similar thing
                    it.consume()
                }
            }

        }
        return blocks
    }
    func parseBlock(
        it: inout TokenIter,
        env: AttrEnv
    ) -> AdocBlock? {
        // Slurp block metadata (ID, roles, options, attributes, title, span)
        let meta = consumeBlockMeta(it: &it, env: env)

        guard let tok = it.peek() else { return nil }

        var inner: AdocBlock?

        // Lists / DLists: handled up front, since they consume multiple lines
        switch tok.kind {
        case .atxSection(let level, let titleRange):
            if let section = parseSection(from: tok, level: level, titleRange: titleRange,
                                          it: &it, env: env) {
                var block = AdocBlock.section(section)
                meta.applyMeta(to: &block)
                return block;
            } else {
                return nil
            }
        case .listItem:
            if let (key, listKind) = listDispatchInfo(from: tok) {
                var stack: [ListMarkerKey] = [key]
                let isBibliography = meta.primaryStyle == "bibliography"
                if let list = parseList(
                    for: key,
                    listKind: listKind,
                    it: &it,
                    env: env,
                    stack: &stack,
                    bibliographyStyle: isBibliography
                ) {
                    inner = .list(list)
                } else {
                    // Make sure we always progress to avoid infinite loops
                    it.consume()
                }
            } else {
                it.consume()
            }

        case .dlistItem:
            if let marker = dlistMarker(from: tok, in: it.text) {
                var stack: [String] = [marker]
                if let dlist = parseDList(
                    for: marker,
                    it: &it,
                    env: env,
                    stack: &stack
                ) {
                    inner = .dlist(dlist)
                } else {
                    it.consume()
                }
            } else {
                it.consume()
            }
        case .continuation:
            // Outside list/dlist parsing, treat "+" as a literal line.
            let span = it.spanForLine(tok)
            let text = String(tok.string)    // should just be "+"
            let para = AdocParagraph(
                text: AdocText(plain: text, span: span),
                id: nil,
                title: nil,
                reftext: nil,
                meta: .init(),
                span: span
            )
            it.consume()
            return .paragraph(para)
        default:
            // Everything else goes through the meta + dispatchKind pipeline
            let kind = dispatchKind(meta: meta, firstToken: tok)

            switch kind {
            case .paragraph:
                if let para = parseParagraph(it: &it, env: env) {
                    inner = .paragraph(para)
                }

            case .literalParagraph:
                if let para = parseParagraph(it: &it, env: env) {
                    let span = combinedSpan(metaSpan: meta.span, innerSpan: para.span)
                    let lit = AdocLiteralBlock(
                        text: para.text,
                        delimiter: nil,
                        id: meta.id ?? para.id,
                        title: meta.title ?? para.title,
                        reftext: para.reftext,
                        meta: para.meta,
                        span: span
                    )
                    inner = .literalBlock(lit)
                }

            case .listing, .sourceListing:
                if var listing = parseListing(it: &it, env: env) {
                    if kind == .sourceListing {
                        listing.meta.attributes["source"] = "true"
                    }
                    inner = .listing(listing)
                }

            case .literalBlock:
                if let lit = parseLiteralBlock(it: &it, env: env) {
                    inner = .literalBlock(lit)
                }

            case .quote:
                if let q = parseQuote(it: &it, env: env) {
                    inner = .quote(q)
                }

            case .verseBlock:
                if let q = parseQuote(it: &it, env: env) {
                    let span = combinedSpan(metaSpan: meta.span, innerSpan: q.span)
                    let verse = AdocVerse(
                        text: nil,
                        blocks: q.blocks,
                        delimiter: q.delimiter,
                        id: meta.id ?? q.id,
                        title: meta.title ?? q.title,
                        reftext: q.reftext,
                        attribution: q.attribution,
                        citetitle: q.citetitle,
                        meta: q.meta,
                        span: span
                    )
                    inner = .verse(verse)
                }

            case .verseParagraph:
                if let para = parseParagraph(it: &it, env: env) {
                    let span = combinedSpan(metaSpan: meta.span, innerSpan: para.span)
                    let verse = AdocVerse(
                        text: para.text,
                        blocks: [],
                        delimiter: nil,
                        id: meta.id ?? para.id,
                        title: meta.title ?? para.title,
                        reftext: para.reftext,
                        meta: para.meta,
                        span: span
                    )
                    inner = .verse(verse)
                }

            case .sidebar:
                if let s = parseSidebar(it: &it, env: env) {
                    inner = .sidebar(s)
                }

            case .example:
                if let e = parseExample(it: &it, env: env) {
                    inner = .example(e)
                }

            case .open:
                if let o = parseOpen(it: &it, env: env) {
                    inner = .open(o)
                }

            case .table:
                if let tok = it.peek(),
                   let styleChar = styleCharFromToken(tok),
                   let t = parseTable(styleChar: styleChar, it: &it, env: env, meta: meta) {
                    inner = .table(t)
                }

            case .blockMacro:
                guard let tok = it.next(), case .directive(let kind, let payloadRange) = tok.kind else { return nil }
                // Manual parse from Parser.swift logic
                 let name: String = {
                     switch kind {
                     case .include: return "include"
                     case .ifdef: return "ifdef"
                     case .ifndef: return "ifndef"
                     case .ifeval: return "ifeval"
                     case .endif: return "endif"
                     case .other(let n): return n
                     }
                 }()
                 let payload = String(tok.string[payloadRange])
                 let payloadParts = parseDirectivePayload(payload)

                 let targetForMath = payloadParts.target.isEmpty ? nil : payloadParts.target
                 if let mathKind = AdocMathKind(macroName: name),
                    let mathBody = payloadParts.body ?? targetForMath,
                    !mathBody.isEmpty {
                     let span = it.spanForLine(tok)
                     let mathBlock = AdocMathBlock(
                         kind: mathKind,
                         body: mathBody,
                         display: true,
                         id: nil,
                         title: nil,
                         reftext: nil,
                         meta: .init(),
                         span: span
                     )
                     inner = .math(mathBlock)
                     break
                 }

                 let macro = AdocBlockMacro(
                     name: name,
                     target: payloadParts.target,
                     id: meta.id, title: meta.title, reftext: nil, // use metadata consumed
                     meta: .init(), // TODO: merge meta properly?
                     span: it.spanForLine(tok)
                 )
                 var m = macro
                 m.apply(meta: meta) // Use applyMeta extension for macros
                 inner = .blockMacro(m)

            case .unknown:
                it.consume()
            }
        }

        // If nothing parsed, bail out
        guard var block = inner else { return nil }

        // 4.5) Paragraph-based shorthand admonitions like `NOTE: Text`
        if meta.admonitionKind == nil, case .paragraph(var para) = block {
            if let (label, content) = detectShorthandAdmonition(in: para.text.plain) {
                // Rebuild the paragraph text without the label
                para.text = AdocText(plain: content, span: para.text.span)
                block = .paragraph(para)

                let span = combinedSpan(metaSpan: meta.span, innerSpan: para.span)
                let admon = AdocAdmonition(
                    kind: label,              // already uppercased from helper
                    blocks: [block],
                    delimiter: nil,
                    id: meta.id,
                    title: meta.title,
                    reftext: nil,
                    meta: .init(),
                    span: span
                )
                var wrapped: AdocBlock = .admonition(admon)
                meta.applyMeta(to: &wrapped)
                return wrapped
            }
        }

        // Admonition wrapping (orthogonal: [NOTE], [TIP], etc.)
        if let kind = meta.admonitionKind {
            let span = combinedSpan(metaSpan: meta.span, innerSpan: block.span)
            let admon = AdocAdmonition(
                kind: kind.uppercased(),
                blocks: [block],
                delimiter: nil,
                id: meta.id,
                title: meta.title,
                reftext: nil,
                meta: .init(),
                span: span
            )
            var wrapped: AdocBlock = .admonition(admon)
            meta.applyMeta(to: &wrapped)
            return wrapped
        }

        // Normal metadata application ...
        meta.applyMeta(to: &block)
        return block
    }

    private enum BlockDispatchKind {
        case paragraph              // normal para
        case literalParagraph       // paragraph masquerading as literal
        case verseParagraph         // verse as simple text (if you want it)

        case listing
        case literalBlock           // delimited literal (.... or [literal] + fence)
        case sourceListing          // [source] listing variant

        case quote
        case verseBlock             // [verse] + quote fences

        case sidebar
        case example
        case open
        case table
        case blockMacro
        case unknown
    }


    private func dispatchKind(
        meta: AdocBlockMeta?,
        firstToken tok: Token
    ) -> BlockDispatchKind {
        // let style = meta?.primaryStyle

        switch tok.kind {
        case .tableBoundary:
            return .table

        case .blockFence(let fenceKind, _):
            switch fenceKind {
            case .listing:
                if meta?.isLiteralStyle == true { return .literalBlock }
                if meta?.isSourceStyle  == true { return .sourceListing }
                return .listing

            case .literal:
                return .literalBlock

            case .quote:
                if meta?.isVerseStyle == true { return .verseBlock }
                return .quote

            case .example:
                if meta?.isQuoteStyle == true { return .quote }
                if meta?.isVerseStyle == true { return .verseBlock }
                return .example

            case .sidebar:
                return .sidebar

            case .open:
                if meta?.isExampleStyle == true { return .example }
                if meta?.isQuoteStyle   == true { return .quote }
                if meta?.isSidebarStyle == true { return .sidebar }
                return .open

            case .passthrough, .other:
                return .unknown
            default:
                return .unknown
            }

        case .text, .attrSet, .attrUnset:
            // Paragraph-based masquerading
            if meta?.isLiteralStyle == true { return .literalParagraph }
            if meta?.isVerseStyle   == true { return .verseParagraph }
            if meta?.isQuoteStyle   == true { return .quote } // single-line quote masquerade
            return .paragraph

        case .directive:
            return .blockMacro

        case .listItem:
            // handled elsewhere; not a "single block" in this dispatch
            return .unknown

        default:
            return .unknown
        }
    }

    /// If the line starts with `WARNING:` (or NOTE/TIP/CAUTION/IMPORTANT),
    /// returns (kind, rangeOfRemainingTextWithinString).
    private func detectAdmonitionShorthand(in tok: Token) -> (kind: String, bodyRange: Range<Substring.Index>)? {
        guard case .text = tok.kind else { return nil }
        let s = tok.string

        // Find the colon that terminates the marker
        guard let colon = s.firstIndex(of: ":") else { return nil }
        let marker = s[s.startIndex..<colon]

        // Must be non-empty, alphabetic, and ALL CAPS
        guard !marker.isEmpty,
              marker.allSatisfy({ $0.isLetter && $0.isUppercase }),
              knownAdmonitions.contains(String(marker)) else {
            return nil
        }

        // Skip the colon and a single optional space
        var bodyStart = s.index(after: colon)
        if bodyStart < s.endIndex, s[bodyStart] == " " {
            bodyStart = s.index(after: bodyStart)
        }

        return (kind: String(marker), bodyRange: bodyStart..<s.endIndex)
    }
}

/// Detects paragraph admonition shorthand like `NOTE: Text` on the first line.
/// Returns (KIND, contentWithoutLabel) if matched, or nil otherwise.
/// KIND is returned uppercased (NOTE, TIP, WARNING, CAUTION, IMPORTANT).
private func detectShorthandAdmonition(in paragraphText: String) -> (kind: String, content: String)? {
    // Only consider the first line; keep the rest unchanged
    let full = paragraphText
    let firstLineEnd = full.firstIndex(of: "\n") ?? full.endIndex
    let firstLine = full[..<firstLineEnd]

    // Shorthand must start at column 1 (no leading spaces in our plain text)
    let labels = ["NOTE", "TIP", "WARNING", "CAUTION", "IMPORTANT"]

    for label in labels {
        let prefix = label + ":"
        guard firstLine.hasPrefix(prefix) else { continue }

        var contentStart = firstLine.index(firstLine.startIndex, offsetBy: prefix.count)
        // optional single space after colon
        if contentStart < firstLineEnd, firstLine[contentStart] == " " {
            contentStart = firstLine.index(after: contentStart)
        }

        // New first line content (without the label+colon+space)
        let newFirstLine = firstLine[contentStart..<firstLineEnd]

        // Reassemble full paragraph text: newFirstLine + rest of original
        var result = String(newFirstLine)
        if firstLineEnd < full.endIndex {
            result.append(contentsOf: full[firstLineEnd...])
        }

        return (kind: label, content: result)
    }

    return nil
}

private func styleCharFromToken(_ tok: Token) -> Character? {
    if case .tableBoundary(let styleChar) = tok.kind {
        return styleChar
    }
    return nil
}
