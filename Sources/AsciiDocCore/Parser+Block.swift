//
// Copyright (c) 2025 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

import Foundation

func parseDirectivePayload(_ payload: String) -> (target: String, body: String?) {
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

func parseMacroAttributeList(_ body: String) -> [String: String] {
    var result: [String: String] = [:]
    var current = ""
    var inQuotes = false
    var quoteChar: Character? = nil

    func flush() {
        let part = current.trimmingCharacters(in: .whitespacesAndNewlines)
        current = ""
        guard !part.isEmpty else { return }
        if let eq = part.firstIndex(of: "=") {
            let key = part[..<eq].trimmingCharacters(in: .whitespacesAndNewlines)
            let valueStart = part.index(after: eq)
            var value = part[valueStart...].trimmingCharacters(in: .whitespacesAndNewlines)
            if value.count >= 2 {
                if (value.first == "\"" && value.last == "\"") || (value.first == "'" && value.last == "'") {
                    value = String(value.dropFirst().dropLast())
                }
            }
            if !key.isEmpty {
                result[String(key)] = String(value)
            }
        } else {
            result[part] = ""
        }
    }

    for ch in body {
        if inQuotes {
            if ch == "\\" {
                current.append(ch)
                continue
            }
            if let currentQuote = quoteChar, ch == currentQuote {
                inQuotes = false
                quoteChar = nil
            }
            current.append(ch)
            continue
        }

        if ch == "\"" || ch == "'" {
            inQuotes = true
            quoteChar = ch
            current.append(ch)
            continue
        }

        if ch == "," {
            flush()
            continue
        }
        current.append(ch)
    }

    flush()
    return result
}

func normalizeXADAttributeValue(_ value: String, xadOptions: XADOptions) -> String {
    guard xadOptions.enabled else { return value }
    var index = value.startIndex
    while index < value.endIndex, value[index].isWhitespace {
        index = value.index(after: index)
    }
    guard index < value.endIndex, value[index] == "\\" else { return value }
    let nextIndex = value.index(after: index)
    guard nextIndex < value.endIndex else { return value }
    let nextChar = value[nextIndex]
    guard nextChar == "{" || nextChar == "[" else { return value }
    var result = value
    result.remove(at: index)
    return result
}

func consumesMultilineJSON(_ value: String, xadOptions: XADOptions) -> Bool {
    guard xadOptions.enabled else { return false }
    var index = value.startIndex
    while index < value.endIndex, value[index].isWhitespace {
        index = value.index(after: index)
    }
    guard index < value.endIndex else { return false }
    let lead = value[index]
    guard lead == "{" || lead == "[" else { return false }
    return !isJSONBalanced(value)
}

func isJSONBalanced(_ value: String) -> Bool {
    var braceDepth = 0
    var bracketDepth = 0
    var inString = false
    var escapeNext = false

    for ch in value {
        if inString {
            if escapeNext {
                escapeNext = false
                continue
            }
            if ch == "\\" {
                escapeNext = true
                continue
            }
            if ch == "\"" {
                inString = false
            }
            continue
        }

        if ch == "\"" {
            inString = true
            continue
        }
        if ch == "{" { braceDepth += 1 }
        else if ch == "}" { braceDepth -= 1 }
        else if ch == "[" { bracketDepth += 1 }
        else if ch == "]" { bracketDepth -= 1 }
    }

    return braceDepth <= 0 && bracketDepth <= 0 && !inString
}

func parseAttributeAssignmentsFromDelimitedBlock(
    it: inout TokenIter,
    xadOptions: XADOptions
) -> [(name: String, value: String?, unset: Bool)]? {
    guard let open = it.peek(), case .blockFence(let kind, _) = open.kind, kind == .listing else {
        return nil
    }
    it.consume()

    var lines: [String] = []
    while let tok = it.peek() {
        if case .blockFence(let kind, _) = tok.kind, kind == .listing {
            it.consume()
            break
        }
        lines.append(it.rawLineText(of: tok))
        it.consume()
    }

    return parseAttributeAssignmentsFromLines(lines, xadOptions: xadOptions)
}

func parseAttributeAssignmentsFromLines(
    _ lines: [String],
    xadOptions: XADOptions
) -> [(name: String, value: String?, unset: Bool)] {
    var assignments: [(name: String, value: String?, unset: Bool)] = []
    var index = 0

    while index < lines.count {
        let rawLine = lines[index]
        let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.hasPrefix(":") {
            index += 1
            continue
        }
        let nameStart = trimmed.index(after: trimmed.startIndex)
        guard let nameEnd = trimmed[nameStart...].firstIndex(of: ":") else {
            index += 1
            continue
        }
        var name = String(trimmed[nameStart..<nameEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
        var value = String(trimmed[trimmed.index(after: nameEnd)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        var unset = false

        if name.hasSuffix("!") && value.isEmpty {
            unset = true
            name = String(name.dropLast())
        }

        if !value.isEmpty {
            value = normalizeXADAttributeValue(value, xadOptions: xadOptions)
            if consumesMultilineJSON(value, xadOptions: xadOptions) {
                var merged = value
                var nextIndex = index + 1
                while nextIndex < lines.count, consumesMultilineJSON(merged, xadOptions: xadOptions) {
                    merged.append("\n")
                    merged.append(lines[nextIndex])
                    nextIndex += 1
                }
                value = merged
                index = nextIndex
            } else {
                index += 1
            }
        } else {
            index += 1
        }

        if !name.isEmpty {
            assignments.append((name: name, value: value.isEmpty ? "" : value, unset: unset))
        }
    }

    return assignments
}

private func consumeAttributeMultilineJSON(
    initial: String,
    it: inout TokenIter,
    xadOptions: XADOptions
) -> String {
    guard consumesMultilineJSON(initial, xadOptions: xadOptions) else { return initial }

    var result = initial
    while true {
        guard let nextTok = it.peek(), case .text(let r) = nextTok.kind else { break }
        let nextLine = it.textFromRelative(range: r, token: nextTok)
        result.append("\n")
        result.append(nextLine)
        it.consume()
        if !consumesMultilineJSON(result, xadOptions: xadOptions) {
            break
        }
    }
    return result
}

extension AdocParser {

    // Parse a sequence of blocks until `stop` says “this token belongs to the caller”.
    // Parse blocks until `stop` returns true for the *next* token.
    func parseBlocks(
        it: inout TokenIter,
        env: inout AttrEnv,
        warnings: inout [AdocWarning],
        stop: (Token) -> Bool
    ) -> [AdocBlock] {
        var blocks: [AdocBlock] = []

        while let tok = it.peek(), !stop(tok) {
            let before = it.index


            if let block = parseBlock(it: &it, env: &env, warnings: &warnings) {
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

    func applyAttributeAssignments(
        _ assignments: [(name: String, value: String?, unset: Bool)],
        env: inout AttrEnv
    ) {
        for assignment in assignments {
            if assignment.unset {
                env.applyAttributeUnset(name: assignment.name)
                continue
            }
            let rawValue = assignment.value
            let normalized = rawValue.map { normalizeXADAttributeValue($0, xadOptions: env.xadOptions) }
            env.applyAttributeSet(name: assignment.name, value: normalized)
        }
    }

    private func parseBlockWithScopedAttributes(
        _ assignments: [(name: String, value: String?, unset: Bool)],
        it: inout TokenIter,
        env: inout AttrEnv,
        warnings: inout [AdocWarning],
        warningSpan: AdocRange?
    ) -> AdocBlock? {
        while let next = it.peek(), case .blank = next.kind {
            it.consume()
        }

        env.pushScope()
        applyAttributeAssignments(assignments, env: &env)
        let block = parseBlock(it: &it, env: &env, warnings: &warnings)
        _ = env.popScope()
        if block == nil, env.xadOptions.enabled {
            warnings.append(
                AdocWarning(
                    message: "blockattr has no following block to apply to.",
                    span: warningSpan
                )
            )
        }
        return block
    }

    func parseBlock(
        it: inout TokenIter,
        env: inout AttrEnv,
        warnings: inout [AdocWarning]
    ) -> AdocBlock? {
        // Slurp block metadata (ID, roles, options, attributes, title, span)
        let meta = consumeBlockMeta(it: &it, env: env)

        guard let tok = it.peek() else { return nil }

        if env.xadOptions.enabled, meta.primaryStyle == "attrs" {
            warnings.append(
                AdocWarning(
                    message: "attrs is only valid immediately after a section title.",
                    span: meta.span
                )
            )
        }

        if case .attrSet(let nameR, let valueR) = tok.kind {
            let name = it.textFromRelative(range: nameR, token: tok)
            var value = valueR.map { it.textFromRelative(range: $0, token: tok) }
            it.consume()
            if let raw = value {
                value = normalizeXADAttributeValue(raw, xadOptions: env.xadOptions)
            }
            if let raw = value {
                value = consumeAttributeMultilineJSON(
                    initial: raw,
                    it: &it,
                    xadOptions: env.xadOptions
                )
            }
            env.applyAttributeSet(name: name, value: value)
            return nil
        }

        if case .attrUnset(let nameR) = tok.kind {
            let name = it.textFromRelative(range: nameR, token: tok)
            it.consume()
            env.applyAttributeUnset(name: name)
            return nil
        }

        if meta.primaryStyle == "blockattr" {
            if let assignments = parseAttributeAssignmentsFromDelimitedBlock(it: &it, xadOptions: env.xadOptions) {
                return parseBlockWithScopedAttributes(
                    assignments,
                    it: &it,
                    env: &env,
                    warnings: &warnings,
                    warningSpan: meta.span
                )
            }
        }

        var inner: AdocBlock?

        // Lists / DLists: handled up front, since they consume multiple lines
        switch tok.kind {
        case .atxSection(let level, let titleRange):
            if let section = parseSection(from: tok, level: level, titleRange: titleRange,
                                          it: &it, env: &env, warnings: &warnings) {
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
                    env: &env,
                    warnings: &warnings,
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
                    env: &env,
                    warnings: &warnings,
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
                if let q = parseQuote(it: &it, env: &env, warnings: &warnings) {
                    inner = .quote(q)
                }

            case .verseBlock:
                if let q = parseQuote(it: &it, env: &env, warnings: &warnings) {
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
                if let s = parseSidebar(it: &it, env: &env, warnings: &warnings) {
                    inner = .sidebar(s)
                }

            case .example:
                if let e = parseExample(it: &it, env: &env, warnings: &warnings) {
                    inner = .example(e)
                }

            case .open:
                if let o = parseOpen(it: &it, env: &env, warnings: &warnings) {
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

                 if name == "attrs", env.xadOptions.enabled {
                     warnings.append(
                         AdocWarning(
                             message: "attrs is only valid immediately after a section title.",
                             span: it.spanForLine(tok)
                         )
                     )
                     return nil
                 }

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

                 if name == "attrpush", env.xadOptions.enabled {
                     let attrs = parseMacroAttributeList(payloadParts.body ?? "")
                     env.pushScope()
                     applyAttributeAssignments(
                         attrs.map { (name: $0.key, value: $0.value, unset: false) },
                         env: &env
                     )
                     return nil
                 }

                 if name == "attrpop", env.xadOptions.enabled {
                     let popped = env.popScope()
                     if !popped {
                         warnings.append(
                             AdocWarning(
                                 message: "attrpop without a matching attrpush.",
                                 span: it.spanForLine(tok)
                             )
                         )
                     }
                     return nil
                 }

                 if name == "blockattr", env.xadOptions.enabled {
                     var merged: [String: String] = parseMacroAttributeList(payloadParts.body ?? "")

                     while let nextTok = it.peek() {
                         if case .blank = nextTok.kind {
                             it.consume()
                             continue
                         }
                         guard case .directive(let nextKind, let nextPayloadRange) = nextTok.kind else {
                             break
                         }
                         let nextName: String = {
                             switch nextKind {
                             case .include: return "include"
                             case .ifdef: return "ifdef"
                             case .ifndef: return "ifndef"
                             case .ifeval: return "ifeval"
                             case .endif: return "endif"
                             case .other(let n): return n
                             }
                         }()
                         guard nextName == "blockattr" else { break }
                         it.consume()
                         let nextPayload = String(nextTok.string[nextPayloadRange])
                         let nextParts = parseDirectivePayload(nextPayload)
                         let nextAttrs = parseMacroAttributeList(nextParts.body ?? "")
                         for (k, v) in nextAttrs { merged[k] = v }
                     }

                     let assignments = merged.map { (name: $0.key, value: $0.value, unset: false) }
                     return parseBlockWithScopedAttributes(
                         assignments,
                         it: &it,
                         env: &env,
                         warnings: &warnings,
                         warningSpan: it.spanForLine(tok)
                     )
                 }

                 if name == "get", env.xadOptions.enabled {
                     let attrs = parseMacroAttributeList(payloadParts.body ?? "")
                     let path = attrs["path"] ?? (payloadParts.target.isEmpty ? nil : payloadParts.target)
                     if let path {
                         let join = attrs["join"]
                         let span = it.spanForLine(tok)
                         let text: String
                         if let resolved = env.resolveAttribute(path, join: join) {
                             text = resolved
                         } else {
                             text = String(tok.string)
                         }
                         let para = AdocParagraph(
                             text: AdocText(plain: text, span: span),
                             id: meta.id,
                             title: meta.title,
                             reftext: nil,
                             meta: .init(),
                             span: span
                         )
                         inner = .paragraph(para)
                         break
                     }
                 }

                 if name == "set", env.xadOptions.enabled {
                     let attrs = parseMacroAttributeList(payloadParts.body ?? "")
                     let path = attrs["path"] ?? (payloadParts.target.isEmpty ? nil : payloadParts.target)
                     if let path {
                         let rawValue = attrs["value"] ?? payloadParts.body ?? ""
                         let normalizedValue = normalizeXADAttributeValue(rawValue, xadOptions: env.xadOptions)
                         env.applyAttributeSet(name: path, value: normalizedValue)
                         return nil
                     }
                 }

                 let macroAttrs = parseMacroAttributeList(payloadParts.body ?? "")
                let macro = AdocBlockMacro(
                     name: name,
                     target: payloadParts.target,
                    attributes: macroAttrs,
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
