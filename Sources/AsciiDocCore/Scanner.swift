//
// Copyright (c) 2025 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

import Foundation

private extension Substring {
    /// Range covering the whole substring in its own index space.
    var range: Range<Index> { startIndex..<endIndex }

    /// Trim leading and trailing spaces / tabs, returning the trimmed view + its range within the original substring.
    func trimmingHSpaces() -> (trimmed: Substring, range: Range<Index>) {
        var i = startIndex
        var j = endIndex

        while i < j, self[i] == " " || self[i] == "\t" {
            i = index(after: i)
        }
        while j > i {
            let before = index(before: j)
            if self[before] == " " || self[before] == "\t" {
                j = before
            } else {
                break
            }
        }
        return (self[i..<j], i..<j)
    }

    var isContinuationLine: Bool {
        return self == "+"
    }

    /// Does the line look like a block attribute line? (starts with '[' after optional indent)
    var isBlockMetaLine: Bool {
        var i = startIndex
        while i < endIndex, self[i] == " " || self[i] == "\t" {
            i = index(after: i)
        }
        return i < endIndex && self[i] == "["
    }

    /// Does the (trimmed) line start with ':'?
    var isAttrLine: Bool {
        let (t, _) = trimmingHSpaces()
        return t.first == ":"
    }
}

struct LineRow {
    let lineNumber: Int
    let content: Substring      // content only (no terminator), may be empty for blank lines
    let origin: LineOrigin?

    var lineRange : AdocRange {
        let stack = origin?.fileStackDescription()
        return AdocRange(
            start: .init(offset: content.startIndex, line: lineNumber, column: 1, fileStack: stack),
            end:   .init(offset: content.endIndex, line: lineNumber, column: content.count, fileStack: stack)
        )
    }
}

// Not sure if there is a better way than this.
extension Substring {
    func trimRight() -> Substring {
        if let end = self.lastIndex(where: { !$0.isWhitespace }) {
            return self[..<self.index(after: end)]
        } else {
            return self[self.startIndex..<self.startIndex]   // empty Substring
        }
    }
}

extension String {
    func enumerateLines(origins: [LineOrigin]? = nil) -> [LineRow] {
        var rows: [LineRow] = []
        var no = 1
        var idx = 0
        // split keeps blanks; CRLF counts as a single separator per Unicode rules
        for field in self.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let origin = origins.flatMap { idx < $0.count ? $0[idx] : nil }
            rows.append(LineRow(lineNumber: no, content: field.trimRight(), origin: origin))
            no += 1
            idx += 1
        }

        if rows.last?.content.isEmpty == true {
            rows.removeLast()
        }
        // Trailing newline produces a final empty field above; nothing else to do.
        return rows
    }
}
public enum BlockFenceKind: Sendable, Equatable {
    case listing      // ----
    case example      // ====
    case sidebar      // ****
    case quote        // ____
    case passthrough  // ++++
    case table        // |=== (treated as boundary rather than fence length)
    case open         //
    case literal
    case other(char: UInt8) // fallback if extended sets are needed
}

public enum ListKind: Sendable, Equatable {
    case unordered(Character)  // '*' or '-'
    case ordered               // '.' prefix (level by dots) or `1.` style (captured separately)
    case callout               // "<1> ..." markers
}
public enum DirectiveKind: Sendable, Equatable {
    case include, ifdef, ifndef, ifeval, endif, other(name: String)
}

public enum LineTok: Sendable {
    case blank
    case text(range: Range<String.Index>)
    case continuation
    case directive(kind: DirectiveKind, payloadRange: Range<String.Index>)
    case attrSet(nameRange: Range<String.Index>, valueRange: Range<String.Index>?)   // :name: value
    case attrUnset(nameRange: Range<String.Index>)                          // :name!:
    case listItem(kind: ListKind, level: Int, ordinal: Int?, checkbox: Character?, contentRange: Range<String.Index>)
    case dlistItem(
        termRange: Range<String.Index>,  // each term’s range within the line
        separator: Range<String.Index>,  // The separator between terms and desc, without space / newline
        descRange: Range<String.Index>?  // optional description text after separator
    )

    case blockFence(kind: BlockFenceKind, len: Int)
    case atxSection(level: Int, titleRange: Range<String.Index>)
    case tableBoundary(styleChar: Character)
    /// Block metadata line (a.k.a. Block Attribute List / BAL), with shorthand extraction.
    /// - rawRange: the entire bracketed content including brackets
    /// - idRange: range of the `#id` shorthand *value* (without the '#') if present
    /// - roleRanges: ranges for each `.role` shorthand (without the '.')
    /// - optionRanges: ranges for each `%option` shorthand (without the '%')
    case blockMeta(rawRange: Range<String.Index>,
                   idRange: Range<String.Index>?,
                   roleRanges: [Range<String.Index>],
                   optionRanges: [Range<String.Index>])
    case error(message: String)
}

public struct LineView: Sendable {
    public let lineNumber: Int
    public let startOffset: Int
    public let endOffset: Int
    public let contentStartOffset: Int
    public let contentEndOffset: Int
    public var isBlank: Bool { contentStartOffset >= contentEndOffset }
}

public struct Token: Sendable {
    public var kind: LineTok
    public var line: Int
    public var string: Substring
    public var range: AdocRange
}

struct LineScanner {

    private enum FenceKind { case listing, sidebar, quote, example, open }
    private func detectAttributeDefinition(on line: LineRow) -> LineTok? {
        let s = line.content
        let (trimmed, trimmedRange) = s.trimmingHSpaces()
        guard trimmed.first == ":" else { return nil }

        var i = trimmed.index(after: trimmed.startIndex) // after leading ':'
        let end = trimmed.endIndex

        // name: run of non ':' / '!' chars
        let nameStart = i
        while i < end, trimmed[i] != ":", trimmed[i] != "!" {
            i = trimmed.index(after: i)
        }
        guard i < end else { return nil }
        let nameEnd = i

        if trimmed[i] == "!" {
            // :name!:  unset
            i = trimmed.index(after: i)
            guard i < end, trimmed[i] == ":" else { return nil }
            let absNameStart = line.content.index(trimmedRange.lowerBound, offsetBy: trimmed.distance(from: trimmed.startIndex, to: nameStart))
            let absNameEnd   = line.content.index(trimmedRange.lowerBound, offsetBy: trimmed.distance(from: trimmed.startIndex, to: nameEnd))
            return .attrUnset(nameRange: absNameStart..<absNameEnd)
        } else {
            // :name: value
            // i currently at ':'
            i = trimmed.index(after: i) // after ':'
            // optional space
            if i < end, trimmed[i] == " " { i = trimmed.index(after: i) }
            let valueStart = i

            let absNameStart = line.content.index(trimmedRange.lowerBound, offsetBy: trimmed.distance(from: trimmed.startIndex, to: nameStart))
            let absNameEnd   = line.content.index(trimmedRange.lowerBound, offsetBy: trimmed.distance(from: trimmed.startIndex, to: nameEnd))
            let absValueStart = line.content.index(trimmedRange.lowerBound, offsetBy: trimmed.distance(from: trimmed.startIndex, to: valueStart))
            let absValueEnd   = line.content.index(trimmedRange.lowerBound, offsetBy: trimmed.distance(from: trimmed.startIndex, to: end))

            return .attrSet(nameRange: absNameStart..<absNameEnd,
                            valueRange: absValueStart..<absValueEnd)
        }
    }

    private func detectBlockMeta(on line: LineRow) -> LineTok? {
        let s = line.content
        guard !s.isEmpty else { return nil }

        // Trim leading / trailing horizontal spaces
        let (trimmed, outerRange) = s.trimmingHSpaces()
        guard !trimmed.isEmpty else { return nil }

        // Must be [ ... ]
        guard trimmed.first == "[", trimmed.last == "]" else { return nil }

        // Double-bracket anchors ([[id]]) are not block meta; let parser handle them.
        if trimmed.hasPrefix("[["), trimmed.hasSuffix("]]") {
            return nil
        }

        // Inner content between brackets
        let innerStart = trimmed.index(after: trimmed.startIndex)
        let innerEnd   = trimmed.index(before: trimmed.endIndex)
        guard innerStart <= innerEnd else { return nil }

        let inner = trimmed[innerStart..<innerEnd]

        // Map inner slice into line.content indices for rawRange
        let offsetToInnerStart = trimmed.distance(from: trimmed.startIndex, to: innerStart)
        let offsetToInnerEnd   = trimmed.distance(from: trimmed.startIndex, to: innerEnd)

        let absInnerStart = line.content.index(outerRange.lowerBound, offsetBy: offsetToInnerStart)
        let absInnerEnd   = line.content.index(outerRange.lowerBound, offsetBy: offsetToInnerEnd)

        let rawRange: Range<String.Index> = absInnerStart..<absInnerEnd

        var idRange: Range<String.Index>? = nil
        var roleRanges: [Range<String.Index>] = []
        var optionRanges: [Range<String.Index>] = []

        // Scan inner for #id, .role, %option sequences,
        // including mixed forms like "#id.role1.role2%optA%optB"
        var i = inner.startIndex
        while i < inner.endIndex {
            let c = inner[i]

            if c == "#" || c == "." || c == "%" {
                let kind = c
                let nameStart = inner.index(after: i)
                var j = nameStart

                // name goes until one of these separators or end:
                // another # . % , or whitespace
                while j < inner.endIndex {
                    let d = inner[j]
                    if d == "#" || d == "." || d == "%" || d == "," || d == " " || d == "\t" {
                        break
                    }
                    j = inner.index(after: j)
                }

                if nameStart < j {
                    // Map name range into line.content indices
                    let offStart = inner.distance(from: inner.startIndex, to: nameStart)
                    let offEnd   = inner.distance(from: inner.startIndex, to: j)

                    let absStart = line.content.index(absInnerStart, offsetBy: offStart)
                    let absEnd   = line.content.index(absInnerStart, offsetBy: offEnd)

                    switch kind {
                    case "#":
                        if idRange == nil {
                            idRange = absStart..<absEnd
                        }
                    case ".":
                        roleRanges.append(absStart..<absEnd)
                    case "%":
                        optionRanges.append(absStart..<absEnd)
                    default:
                        break
                    }
                }

                i = j
                continue
            }

            // Skip any other character (letters in attributes, commas, spaces, etc.)
            i = inner.index(after: i)
        }

        return .blockMeta(
            rawRange: rawRange,
            idRange: idRange,
            roleRanges: roleRanges,
            optionRanges: optionRanges
        )
    }

    private func detectTableBoundary(on line: LineRow) -> (style: Character, count: Int)? {
        let s = line.content
        guard !s.isEmpty else { return nil }

        // Trim leading + trailing spaces/tabs
        let (trimmed, _) = s.trimmingHSpaces()
        guard !trimmed.isEmpty else { return nil }

        // First character must be a valid table style marker
        let markers: Set<Character> = ["|", ",", ":", ";", "!"]
        guard let first = trimmed.first, markers.contains(first) else {
            return nil
        }

        // Everything following MUST be '='
        var i = trimmed.index(after: trimmed.startIndex)
        var eqCount = 0
        while i < trimmed.endIndex {
            if trimmed[i] != "=" {
                return nil
            }
            eqCount += 1
            i = trimmed.index(after: i)
        }

        // Must have at least one '=' to be a fence
        guard eqCount > 0 else { return nil }

        return (style: first, count: eqCount)
    }

    private func detectAtx(line: LineRow) -> (level: Int, titleRel: Substring)? {
        var idx = line.content.startIndex
        var level = -1
        while idx < line.content.endIndex, line.content[idx] == "=" {
            idx = line.content.index(after: idx)
            level += 1
        }

        guard level >= 0, level <= 5 ,idx < line.content.endIndex, line.content[idx] == " " else {
            return nil
        }
        idx = line.content.index(after: idx)

        return (level, line.content[idx...])
    }

    /// Parse a checkbox `[ ]`, `[x]`, `[X]` starting at or after `from`.
    /// Returns (middleChar, nextIndex) where middleChar is ' ', 'x', or 'X',
    /// or nil if there is no valid checkbox at this position.
    private func parseCheckbox(
        in line: Substring,
        from fromIndex: Substring.Index
    ) -> (mark: Character, next: Substring.Index)? {
        var i = fromIndex
        let end = line.endIndex

        // skip leading spaces/tabs
        while i < end, line[i] == " " || line[i] == "\t" {
            i = line.index(after: i)
        }
        guard i < end, line[i] == "[" else { return nil }

        let open = i
        let mid = line.index(after: open)
        guard mid < end else { return nil }
        let close = line.index(after: mid)
        guard close < end, line[close] == "]" else { return nil }

        let midChar = line[mid]

        // allow ' ', 'x', 'X'; anything else is not a checkbox
        guard midChar == " " || midChar == "x" || midChar == "X" else { return nil }

        var j = line.index(after: close)
        // optional space after ]
        if j < end, line[j] == " " || line[j] == "\t" {
            j = line.index(after: j)
        }
        return (mark: midChar, next: j)
    }

    private func detectList(on line: LineRow) -> LineTok? {
        let s = line.content
        guard !s.isEmpty else { return nil }

        var markerIndex = s.startIndex
        let end = s.endIndex

        // Skip leading spaces/tabs (list markers can be indented)
        while markerIndex < end, s[markerIndex] == " " || s[markerIndex] == "\t" {
            markerIndex = s.index(after: markerIndex)
        }
        if markerIndex == end { return nil }

        let firstChar = s[markerIndex]

        // -------- Callout: <1> text --------
        if firstChar == "<" {
            var j = s.index(after: markerIndex)
            let digitsStart = j
            while j < end, s[j].isNumber {
                j = s.index(after: j)
            }
            let hasDigits = digitsStart < j

            if hasDigits, j < end, s[j] == ">" {
                var afterMarker = s.index(after: j)

                if afterMarker < end, s[afterMarker].isWhitespace {
                    afterMarker = s.index(after: afterMarker)
                }

                let contentRange = afterMarker..<end
                let digits = String(s[digitsStart..<j])
                let ordinal = Int(digits)

                return .listItem(
                    kind: .callout,
                    level: 1,
                    ordinal: ordinal,
                    checkbox: nil,
                    contentRange: contentRange
                )
            }
        }

        // -------- Unordered: *, -, + --------
        if firstChar == "*" || firstChar == "-" || firstChar == "+" {
            let markerChar = firstChar
            var count = 0
            var i = markerIndex
            while i < end, s[i] == markerChar {
                count += 1
                i = s.index(after: i)
            }

            // Special rule: for '-' we do NOT allow "--" as a nested list marker.
            // Only a single '-' is a valid bullet.
            if markerChar == "-", count > 1 {
                return nil
            }

            // Require space after markers
            guard i < end, s[i] == " " else { return nil }
            i = s.index(after: i)

            // Optional checkbox
            var checkbox: Character? = nil
            if let (mark, nextIndex) = parseCheckbox(in: s, from: i) {
                checkbox = mark
                i = nextIndex
            }

            let contentStart = i
            let contentRange = contentStart..<end

            // Level: '*' and '+' can nest by count; '-' fixed at level 1
            let level: Int
            if markerChar == "-" {
                level = 1
            } else {
                level = max(1, count)
            }

            return .listItem(
                kind: .unordered(markerChar),
                level: level,
                ordinal: nil,
                checkbox: checkbox,
                contentRange: contentRange
            )
        }

        // -------- Dot-only ordered lists: ". foo", ".. foo", etc. --------
        if firstChar == "." {
            var dotCount = 0
            var i = markerIndex
            while i < end, s[i] == "." {
                dotCount += 1
                i = s.index(after: i)
            }

            // Must have a space after the dot run
            guard i < end, s[i] == " " else { return nil }
            i = s.index(after: i)

            // Optional checkbox
            var checkbox: Character? = nil
            if let (mark, nextIndex) = parseCheckbox(in: s, from: i) {
                checkbox = mark
                i = nextIndex
            }

            let contentStart = i
            let contentRange = contentStart..<end

            let level = max(1, dotCount)

            return .listItem(
                kind: .ordered,
                level: level,
                ordinal: nil,        // dot-only markers have no numeric ordinal
                checkbox: checkbox,
                contentRange: contentRange
            )
        }

        // -------- Normal ordered lists: "1. foo", "2.1. foo", "A.. foo" --------
        var i = markerIndex
        var seenAlnum = false
        var sawDot = false
        var lastWasDot = false
        var inGroup = false

        let markerStart = i
        var lastGroupStart = i
        var lastGroupEnd = i

        // parse marker: [A-Za-z0-9.]+ but must end in '.'
        while i < end {
            let c = s[i]
            if c.isNumber || c.isLetter {
                if !inGroup {
                    inGroup = true
                    lastGroupStart = i
                }
                seenAlnum = true
                lastWasDot = false
                i = s.index(after: i)
            } else if c == "." {
                sawDot = true
                if inGroup {
                    lastGroupEnd = i
                    inGroup = false
                }
                lastWasDot = true
                i = s.index(after: i)
            } else {
                break
            }
        }

        // Must have alnum, at least one dot, and end with dot
        guard seenAlnum, sawDot, lastWasDot else { return nil }

        let markerEnd = i

        // Level = count of dot groups (e.g. "2.1." → 2)
        var level = 0
        var k = markerStart
        var prevDot = false
        while k < markerEnd {
            let c = s[k]
            if c == "." {
                if !prevDot { level += 1 }
                prevDot = true
            } else {
                prevDot = false
            }
            k = s.index(after: k)
        }
        guard level > 0 else { return nil }

        // Require a space after marker
        guard i < end, s[i] == " " else { return nil }
        i = s.index(after: i)

        // Optional checkbox
        var checkbox: Character? = nil
        if let (mark, nextIndex) = parseCheckbox(in: s, from: i) {
            checkbox = mark
            i = nextIndex
        }

        let contentStart = i
        let contentRange = contentStart..<end

        // Ordinal = last numeric group before the final dot, if numeric
        var ordinal: Int? = nil
        if lastGroupStart < lastGroupEnd {
            let group = s[lastGroupStart..<lastGroupEnd]
            if group.allSatisfy({ $0.isNumber }) {
                ordinal = Int(group)
            }
        }

        return .listItem(
            kind: .ordered,
            level: level,
            ordinal: ordinal,
            checkbox: checkbox,
            contentRange: contentRange
        )
    }

    private func detectDList(on line: LineRow) -> LineTok? {
        let s = line.content
        guard !s.isEmpty else { return nil }

        let start = s.startIndex
        let end   = s.endIndex

        var i = start
        while i < end {
            let ch = s[i]

            // Only ':' or ';' can start a dlist marker
            guard ch == ":" || ch == ";" else {
                i = s.index(after: i)
                continue
            }

            // Count how many identical chars in a row
            var j = i
            while j < end, s[j] == ch {
                j = s.index(after: j)
            }
            let runLen = s.distance(from: i, to: j)

            // Valid markers:
            //   ::, :::, ::::  (for ':')
            //   ;;             (for ';')
            let isValidMarker: Bool
            switch ch {
            case ":":
                isValidMarker = (2...4).contains(runLen)
            case ";":
                isValidMarker = (runLen == 2)
            default:
                isValidMarker = false
            }

            if !isValidMarker {
                i = s.index(after: i)
                continue
            }

            // Next char must be space or EOL
            if j == end || s[j] == " " {
                let termRange = start ..< i              // everything before the marker
                let sepRange  = i ..< j                  // the marker itself ("::", ";;", etc.)

                var descRange: Range<String.Index>? = nil
                if j < end {
                    // Skip exactly one space after the marker; rest is description (if any)
                    let descStart = s.index(after: j)
                    if descStart < end {
                        descRange = descStart ..< end
                    }
                }

                return .dlistItem(
                    termRange: termRange,
                    separator: sepRange,
                    descRange: descRange
                )
            }

            // Marker run not followed by space/EOL → not a dlist; move on
            i = s.index(after: i)
        }

        return nil
    }
    
    private func detectDirective(on line: LineRow) -> LineTok? {
        let s = line.content

        // Trim outer horizontal spaces first
        let (trimmed, trimmedRange) = s.trimmingHSpaces()
        guard !trimmed.isEmpty else { return nil }

        var i = trimmed.startIndex
        let end = trimmed.endIndex

        // Parse directive name: [a-zA-Z0-9_-]+ (adjust if you like)
        let nameStart = i
        while i < end,
              trimmed[i].isLetter || trimmed[i].isNumber || trimmed[i] == "_" || trimmed[i] == "-" {
            i = trimmed.index(after: i)
        }
        guard i > nameStart else { return nil }          // need at least one char in name
        let nameEnd = i

        // Expect "::" exactly
        guard i < end, trimmed[i] == ":" else { return nil }
        i = trimmed.index(after: i)
        guard i < end, trimmed[i] == ":" else { return nil }
        i = trimmed.index(after: i)

        // Map name → DirectiveKind
        let nameStr = String(trimmed[nameStart..<nameEnd])
        let dirKind: DirectiveKind = {
            switch nameStr.lowercased() {
            case "include": return .include
            case "ifdef":   return .ifdef
            case "ifndef":  return .ifndef
            case "ifeval":  return .ifeval
            case "endif":   return .endif
            default:        return .other(name: nameStr)
            }
        }()

        // Payload: rest of the line after "::", trimmed of leading/trailing spaces
        //    (We keep whatever syntax is there: target + [attrs], expression, etc.)
        // Skip one optional leading space
        if i < end, trimmed[i] == " " || trimmed[i] == "\t" {
            i = trimmed.index(after: i)
        }
        let payloadStart = i
        var payloadEnd = end

        // Trim trailing spaces/tabs from the payload
        while payloadEnd > payloadStart {
            let before = trimmed.index(before: payloadEnd)
            if trimmed[before] == " " || trimmed[before] == "\t" {
                payloadEnd = before
            } else {
                break
            }
        }

        // Convert payload range back into the original line.content index space
        let offsetToPayloadStart = trimmed.distance(from: trimmed.startIndex, to: payloadStart)
        let offsetToPayloadEnd   = trimmed.distance(from: trimmed.startIndex, to: payloadEnd)

        let absPayloadStart = line.content.index(trimmedRange.lowerBound,
                                                 offsetBy: offsetToPayloadStart)
        let absPayloadEnd   = line.content.index(trimmedRange.lowerBound,
                                                 offsetBy: offsetToPayloadEnd)

        let payloadRange: Range<String.Index> = absPayloadStart..<absPayloadEnd

        return .directive(kind: dirKind, payloadRange: payloadRange)
    }

    func scan(_ text: String) -> [Token] {
        scan(PreprocessedSource(text: text))
    }

    func scan(_ source: PreprocessedSource) -> [Token] {
        var toks: [Token] = []
        var inTable = false

        for line in source.text.enumerateLines(origins: source.lineOrigins) {
            let lineRange = line.lineRange
            let content = line.content

            // Blank
            if content.isEmpty {
                toks.append(Token(kind: .blank, line: line.lineNumber, string: content, range: lineRange))
                continue
            }

            if let table = detectTableBoundary(on: line) {
                inTable.toggle()

                toks.append(Token(
                    kind: .tableBoundary(styleChar: table.style),
                    line: line.lineNumber,
                    string: line.content,
                    range: lineRange
                ))
                continue
            }

            // Inside a table: everything that is not a boundary is just text
            if inTable {
                toks.append(Token(kind: .text(range: content.range),
                                  line: line.lineNumber,
                                  string: content,
                                  range: lineRange))
                continue
            }


            // Continuation (+)
            if content.isContinuationLine {
                toks.append(Token(kind: .continuation, line: line.lineNumber, string: content, range: lineRange))
                continue
            }

            // Block attributes [NOTE], [id=...], [cols="3*"], etc.
            if let metaTok = detectBlockMeta(on: line) {
                toks.append(Token(kind: metaTok, line: line.lineNumber, string: content, range: lineRange))
                continue
            }

            // Attribute definitions :name: value / :name!:
            if let attrTok = detectAttributeDefinition(on: line) {
                toks.append(Token(kind: attrTok, line: line.lineNumber, string: content, range: lineRange))
                continue
            }


            // Block fences (----, ****, ====, ____)
            let blockFenceCharacters: Set<Character> = ["-", "=", "*", "_", "+", "."]

            if let ch = content.first, blockFenceCharacters.contains(ch) {
                if content.count == 2 {
                    if content.allSatisfy({ $0 == "-" }) {
                        toks.append(Token(kind: .blockFence(kind: .open, len: content.count),
                                          line: line.lineNumber, string: content, range: lineRange))
                        continue
                    }
                } else if content.count >= 4 {
                    if content.allSatisfy({ $0 == ch }) {
                        let kind: BlockFenceKind = {
                            switch ch {
                            case "-": return .listing
                            case "=": return .example
                            case "*": return .sidebar
                            case "_": return .quote
                            case "+": return .passthrough
                            case ".": return .literal
                            default:  return .other(char: ch.asciiValue ?? 0x3F)
                            }
                        }()
                        toks.append(Token(kind: .blockFence(kind: kind, len: content.count),
                                          line: line.lineNumber, string: content, range: lineRange))
                        continue
                    }
                }
            }

            // ATX section ==, ===, etc.
            if let (level, title) = detectAtx(line: line) {
                toks.append(Token(kind: .atxSection(level: level, titleRange: title.range),
                                  line: line.lineNumber,
                                  string: content, range: lineRange))
                continue
            }

            if let listTok = detectList(on: line) {
                toks.append(Token(kind: listTok,
                                  line: line.lineNumber,
                                  string: line.content,
                                  range: line.lineRange))
                continue
            }

            if let dlistTok = detectDList(on: line) {
                toks.append(Token(kind: dlistTok,
                                  line: line.lineNumber,
                                  string: line.content,
                                  range: line.lineRange))
                continue
            }

            // Directives (include::, image::, etc.)
            if let dirTok = detectDirective(on: line) {
                toks.append(Token(kind: dirTok, line: line.lineNumber, string: content, range: lineRange))
                continue
            }

            // Default text
            toks.append(Token(kind: .text(range: content.range),
                              line: line.lineNumber,
                              string: content, range: lineRange))
        }
        return toks
    }
}
