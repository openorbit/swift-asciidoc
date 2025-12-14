//
// Copyright (c) 2025 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

package func parseInlines(_ text: String, baseSpan: AdocRange?) -> [AdocInline] {
    var result: [AdocInline] = []
    var buffer = ""
    var i = text.startIndex
    let end = text.endIndex

    func flushBuffer() {
        if !buffer.isEmpty {
            result.append(.text(buffer, span: baseSpan))
            buffer.removeAll(keepingCapacity: true)
        }
    }
    func parseInlineMacro(
        in text: String,
        from start: String.Index,
        baseSpan: AdocRange?
    ) -> (node: AdocInline, nextIndex: String.Index)? {
        guard text[start].isLetter else { return nil }

        // Parse identifier (name)
        var nameEnd = start
        while nameEnd < text.endIndex, (text[nameEnd].isLetter || text[nameEnd].isNumber || text[nameEnd] == "-" || text[nameEnd] == "_") {
            // Check for attached footnote collision "Wordfootnote:"
            if nameEnd > start, text[nameEnd] == "f" {
                 let rest = text[nameEnd...]
                 if rest.hasPrefix("footnote:") {
                     break
                 }
            }
            nameEnd = text.index(after: nameEnd)
        }
        let name = String(text[start..<nameEnd])

        // Expect colon
        guard nameEnd < text.endIndex, text[nameEnd] == ":" else { return nil }
        let afterColon = text.index(after: nameEnd)

        // Parse Target (chars until '[')
        var targetEnd = afterColon
        while targetEnd < text.endIndex, text[targetEnd] != "[" {
            if text[targetEnd].isNewline || text[targetEnd].isWhitespace { return nil } 
            targetEnd = text.index(after: targetEnd)
        }

        // Expect '['
        guard targetEnd < text.endIndex, text[targetEnd] == "[" else { return nil }
        
        let targetString: String? = (targetEnd == afterColon) ? nil : String(text[afterColon..<targetEnd])

        // Find matching ']' (simple version: no nesting)
        var j = text.index(after: targetEnd)
        while j < text.endIndex, text[j] != "]" {
            j = text.index(after: j)
        }
        guard j < text.endIndex, text[j] == "]" else { return nil }

        let bodyRange = text.index(after: targetEnd)..<j
        let body = String(text[bodyRange])

        // Map whole macro to a span
        let span = spanForRange(in: text, base: baseSpan, range: start..<text.index(after: j))

        // Special handling for legacy math macros
        if let mathKind = AdocMathKind(macroName: name) {
             // Math macros using the macro syntax usually put the expression in the "body" 
             // and have no target (or target IS the body if using `latexmath:expression`).
             // Standard asciidoc `stem:[expr]` -> target=nil, body=expr
            let node = AdocInline.math(kind: mathKind, body: body, display: false, span: span)
            let next = text.index(after: j)
            return (node, next)
        }


        
        // Special handling for index terms
        if name == "indexterm" || name == "indexterm2" {
             let visible = (name == "indexterm2")
             // Split body by commas
             let parts = body.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
             let node = AdocInline.indexTerm(terms: parts, visible: visible, span: span)
             let next = text.index(after: j)
             return (node, next)
        }

        // Special handling for footnotes
        if name == "footnote" {
            // Recursively parse the body
            let bodySpan = spanForRange(in: text, base: baseSpan, range: bodyRange)
            let contentInlines = parseInlines(body, baseSpan: bodySpan)

            let node = AdocInline.footnote(content: contentInlines, ref: targetString, id: nil, span: span) // ID resolved later
            let next = text.index(after: j)
            return (node, next)
        }

        let node: AdocInline = .inlineMacro(name: name, target: targetString, body: body, span: span)

        let next = text.index(after: j)
        return (node, next)
    }

    func parseDollarMath(from start: String.Index) -> (AdocInline, String.Index)? {
        var display = false
        var bodyStart = text.index(after: start)
        if bodyStart < end, text[bodyStart] == "$" {
            display = true
            bodyStart = text.index(after: bodyStart)
        }

        var i = bodyStart
        var closeEnd: String.Index?

        while i < end {
            let ch = text[i]
            if ch == "\\" {
                // Skip escaped characters
                i = text.index(after: i)
                if i < end { i = text.index(after: i) }
                continue
            }

            if ch == "$" {
                if display {
                    let next = text.index(after: i)
                    guard next < end else { break }
                    if text[next] == "$" {
                        closeEnd = text.index(after: next)
                        break
                    }
                } else {
                    closeEnd = text.index(after: i)
                    break
                }
            }

            i = text.index(after: i)
        }

        guard let closingEnd = closeEnd else { return nil }

        let closingStart: String.Index
        if display {
            guard let idx = text.index(closingEnd, offsetBy: -2, limitedBy: text.startIndex) else {
                return nil
            }
            closingStart = idx
        } else {
            closingStart = text.index(before: closingEnd)
        }

        guard bodyStart < closingStart else { return nil }

        let bodyRange = bodyStart..<closingStart
        let body = String(text[bodyRange])

        let spanRange = start..<closingEnd
        let span = spanForRange(in: text, base: baseSpan, range: spanRange)

        let inline = AdocInline.math(kind: .latex, body: body, display: display, span: span)
        return (inline, closingEnd)
    }

    func parseBareURL(from start: String.Index) -> (AdocInline, String.Index)? {
        // Very simple autolink: http://… or https://…
        let slice = text[start...]
        guard slice.hasPrefix("http://") || slice.hasPrefix("https://") else {
            return nil
        }

        var i = start
        // URL goes until whitespace; we keep trailing punctuation for now
        while i < end, !text[i].isWhitespace {
            i = text.index(after: i)
        }

        let urlRange = start..<i
        let url = String(text[urlRange])

        // Span specific to this URL
        let span = spanForRange(in: text, base: baseSpan, range: urlRange)

        // Label = URL itself for now
        let labelInline: AdocInline = .text(url, span: span)

        let node = AdocInline.link(
            target: url,
            text: [labelInline],
            span: span
        )

        return (node, i)
    }

    func parseLinkLike(from start: String.Index) -> (AdocInline, String.Index)? {
        let slice = text[start...]
        let kind: String
        if slice.hasPrefix("link:") {
            kind = "link"
        } else if slice.hasPrefix("xref:") {
            kind = "xref"
        } else {
            return nil
        }

        var i = start
        // skip "link:" or "xref:"
        i = text.index(i, offsetBy: 5) // both are 5 chars
        let targetStart = i

        // target until '['
        while i < end, text[i] != "[" {
            i = text.index(after: i)
        }
        guard i < end, text[i] == "[" else { return nil }

        let target = String(text[targetStart..<i])

        i = text.index(after: i) // after '['
        let labelStart = i
        while i < end, text[i] != "]" {
            i = text.index(after: i)
        }
        guard i < end, text[i] == "]" else { return nil }

        let label = String(text[labelStart..<i])
        let next = text.index(after: i) // position after ']'

        let innerInlines = parseInlines(label, baseSpan: baseSpan)
        if kind == "link" {
            return (.link(target: target, text: innerInlines, span: baseSpan), next)
        } else {
            let xrefTarget = AdocXrefTarget(raw: target)
            return (.xref(target: xrefTarget, text: innerInlines, span: baseSpan), next)
        }
    }

    func parseChevronXref(from start: String.Index) -> (AdocInline, String.Index)? {
        guard text.distance(from: start, to: end) >= 4 else { return nil }
        let first = start
        let second = text.index(after: first)
        guard text[first] == "<", text[second] == "<" else { return nil }

        let bodyStart = text.index(after: second)
        var cursor = bodyStart
        var closingStart: String.Index?
        var closingEnd: String.Index?

        while cursor < end {
            if text[cursor] == ">" {
                let next = text.index(after: cursor)
                if next < end, text[next] == ">" {
                    closingStart = cursor
                    closingEnd = text.index(after: next)
                    break
                }
            }
            cursor = text.index(after: cursor)
        }

        guard let closeStart = closingStart, let closeEnd = closingEnd else {
            return nil
        }

        let bodyRange = bodyStart..<closeStart
        let payload = String(text[bodyRange])

        let parts = payload.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
        guard let firstPart = parts.first else { return nil }
        let targetText = firstPart.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetText.isEmpty else { return nil }

        let labelText: String? = parts.count > 1
            ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            : nil
        let labelInlines = labelText.map { parseInlines($0, baseSpan: baseSpan) } ?? []

        let spanRange = start..<closeEnd
        let span = spanForRange(in: text, base: baseSpan, range: spanRange)
        let node = AdocInline.xref(
            target: AdocXrefTarget(raw: targetText),
            text: labelInlines,
            span: span
        )
        return (node, closeEnd)
    }

    func parseIndexTermSyntax(from start: String.Index) -> (AdocInline, String.Index)? {
        // Must start with ((
        guard text.distance(from: start, to: end) >= 4 else { return nil }
        let second = text.index(after: start)
        guard text[second] == "(" else { return nil } // ((
        
        let third = text.index(after: second)
        // Check if triple: (((
        let isTriple = (third < end && text[third] == "(")
        
        let bodyStart: String.Index
        if isTriple {
            bodyStart = text.index(after: third)
        } else {
            bodyStart = third // content starts after ((
        }
        
        // Scan for delimiter: ))) or ))
        // Simple scan: find closing parens
        var i = bodyStart
        var closingStart: String.Index? = nil
        var closingEnd: String.Index? = nil
        
        while i < end {
            if text[i] == ")" {
                // Potential close
                let next = text.index(after: i)
                if next < end, text[next] == ")" { // ))
                     if isTriple {
                         let next2 = text.index(after: next)
                         if next2 < end, text[next2] == ")" { // )))
                             closingStart = i
                             closingEnd = text.index(after: next2)
                             break
                         }
                     } else {
                         // Double
                         closingStart = i
                         closingEnd = text.index(after: next)
                         break
                     }
                }
            }
            i = text.index(after: i)
        }
        
        guard let close = closingStart, let finish = closingEnd else { return nil }
        
        let bodyRange = bodyStart..<close
        let body = String(text[bodyRange])
        // For triple (invisible), split by commas.
        // For double (visible), treat as single term (usually).
        // Standard AsciiDoc: ((Term, S)) -> Text "Term, S", Index "Term, S".
        // (((T1, S1))) -> Index T1 > S1.
        
        let terms: [String]
        if isTriple {
             terms = body.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        } else {
             // Visible: single term (trimmed)
             terms = [body.trimmingCharacters(in: .whitespacesAndNewlines)]
        }
        
        let span = spanForRange(in: text, base: baseSpan, range: start..<finish)
        let node = AdocInline.indexTerm(terms: terms, visible: !isTriple, span: span)
        
        return (node, finish)
    }

    enum DelimitedKind {
        case strong
        case emphasis
        case mono
        case superscript
        case `subscript`
    }
    func parseDelimited(
        from start: String.Index,
        delimiter: String,
        kind: DelimitedKind
    ) -> (AdocInline, String.Index)? {
        let delimFirst = delimiter.first!
        let delimLen = delimiter.count

        var j = text.index(start, offsetBy: delimLen)
        var closingStart: String.Index? = nil

        while j < end {
            if text[j] == delimFirst {
                var k = j
                var matched = true
                for ch in delimiter {
                    if k == end || text[k] != ch {
                        matched = false
                        break
                    }
                    k = text.index(after: k)
                }
                if matched {
                    closingStart = j
                    break
                }
            }
            j = text.index(after: j)
        }

        guard let close = closingStart else { return nil }

        // Content (no delimiters)
        // ... after `guard let close = closingStart else { return nil }`

        let innerStart = text.index(start, offsetBy: delimLen)
        guard innerStart < close else { return nil }
        let innerRange: Range<String.Index> = innerStart..<close

        // Constrained boundary rule for * and _ :
        // only treat as markup if surrounded by non-alphanumerics.
        if kind == .strong || kind == .emphasis {
            let open = start

            let charBefore: Character? = {
                if open > text.startIndex {
                    return text[text.index(before: open)]
                }
                return nil
            }()

            let afterClose = text.index(close, offsetBy: delimLen)
            let charAfter: Character? = (afterClose < end) ? text[afterClose] : nil

            func isBoundary(_ ch: Character?) -> Bool {
                guard let ch else { return true } // start/end of string is fine
                if ch.isLetter || ch.isNumber {
                    return false                  // inside a word → not a boundary
                }
                return true                       // whitespace / punctuation / symbol
            }

            // If either side is alphanumeric, treat the delimiter as literal.
            if !isBoundary(charBefore) || !isBoundary(charAfter) {
                return nil
            }
        }

        // Span for content only (used for inner inlines)
        let innerSpan = spanForRange(in: text, base: baseSpan, range: innerRange)
        let outerSpan = baseSpan

        let innerText = text[innerRange]
        let innerInlines = parseInlines(String(innerText), baseSpan: innerSpan)

        let next = text.index(close, offsetBy: delimLen)

        switch kind {
        case .mono:
            return (.mono(innerInlines, span: outerSpan), next)
        case .strong:
            return (.strong(innerInlines, span: outerSpan), next)
        case .emphasis:
            return (.emphasis(innerInlines, span: outerSpan), next)
        case .superscript:
            return (.superscript(innerInlines, span: outerSpan), next)
        case .subscript:
            return (.subscript(innerInlines, span: outerSpan), next)
        }
    }

    while i < end {
        let c = text[i]

        // Escapes: \X → literal X
        if c == "\\" {
            let next = text.index(after: i)
            if next < end {
                buffer.append(text[next])
                i = text.index(after: next)
            } else {
                buffer.append(c)
                i = text.index(after: i)
            }
            continue
        }

        // ink:target[text] / xref:target[text]
        // Must try this *before* generic inline macro, otherwise "link:..." is parsed as a generic macro.
        if let (inline, next) = parseLinkLike(from: i) {
            flushBuffer()
            result.append(inline)
            i = next
            continue
        }

        if let (macroNode, next) = parseInlineMacro(in: text, from: i, baseSpan: baseSpan) {
            flushBuffer()
            result.append(macroNode)
            i = next
            continue
        }

        let ch = text[i]

        if ch == "$" {
            if let (mathInline, next) = parseDollarMath(from: i) {
                flushBuffer()
                result.append(mathInline)
                i = next
                continue
            }
        }

        // Index terms: (((...))) or ((...))
        if c == "(" {
             if let (node, next) = parseIndexTermSyntax(from: i) {
                 flushBuffer()
                 result.append(node)
                 i = next
                 continue
             }
        }

        if c == "<" {
            if let (inline, next) = parseChevronXref(from: i) {
                flushBuffer()
                result.append(inline)
                i = next
                continue
            }
        }

        // Bare URLs: http://… / https://…
        if let (inline, next) = parseBareURL(from: i) {
            flushBuffer()
            result.append(inline)
            i = next
            continue
        }



        // Strong / emphasis: *text* / _text_
        if c == "*" || c == "_" {
            let kind: DelimitedKind = (c == "*") ? .strong : .emphasis
            let delimiter = String(c)

            if let (inline, nextIdx) = parseDelimited(
                from: i,
                delimiter: delimiter,
                kind: kind
            ) {
                flushBuffer()
                result.append(inline)
                i = nextIdx
                continue
            }

            buffer.append(c)
            i = text.index(after: i)
            continue
        }

        // Mono/code: `code`
        if c == "`" {
            if let (inline, nextIdx) = parseDelimited(
                from: i,
                delimiter: "`",
                kind: .mono
            ) {
                flushBuffer()
                result.append(inline)
                i = nextIdx
                continue
            }
            buffer.append(c)
            i = text.index(after: i)
            continue
        }

        // Superscript / subscript: ^x^ / ~x~
        if c == "^" || c == "~" {
            let kind: DelimitedKind = (c == "^") ? .superscript : .subscript
            let delimiter = String(c)

            if let (inline, nextIdx) = parseDelimited(
                from: i,
                delimiter: delimiter,
                kind: kind
            ) {
                flushBuffer()
                result.append(inline)
                i = nextIdx
                continue
            }

            // No closing delimiter → literal
            buffer.append(c)
            i = text.index(after: i)
            continue
        }
        // Default: plain text
        buffer.append(c)
        i = text.index(after: i)
    }

    flushBuffer()
    return result
}

/// Compute a sub-span for a content range inside a single line.
/// - Parameters:
///   - text: the full inline text passed to `parseInlines`
///   - base: the base span for the whole text (line-level)
///   - range: half-open range [lowerBound, upperBound) of *content*
///            (no delimiters), in `text` coordinates.
/// - Returns: an AdocRange whose columns cover exactly that content.
private func spanForRange(in text: String,
                          base: AdocRange?,
                          range: Range<String.Index>) -> AdocRange? {
    guard let base = base else { return nil }

    let line = base.start.line

    // Inclusive indices for the content
    let startIndex = range.lowerBound
    guard startIndex <= range.upperBound else { return nil }

    // If empty content, collapse to base.start
    if range.isEmpty {
        return AdocRange(start: base.start, end: base.start)
    }

    let lastIndex = text.index(before: range.upperBound)

    // Column offsets from the start of the text
    let startDelta = text.distance(from: text.startIndex, to: startIndex)
    let endDelta   = text.distance(from: text.startIndex, to: lastIndex)

    let startCol = base.start.column + startDelta
    let endCol   = base.start.column + endDelta

    let fileStack = base.start.fileStack
    let startPos = AdocPos(offset: startIndex, line: line, column: startCol, fileStack: fileStack)
    let endPos   = AdocPos(offset: lastIndex,  line: line, column: endCol, fileStack: fileStack)

    return AdocRange(start: startPos, end: endPos)
}

// Slice is a range inside tok.string (Substring)
package func spanForSlice(_ slice: Range<String.Index>, in tok: Token) -> AdocRange {
    let lineStr   = tok.string
    let lineStart = lineStr.startIndex

    // Columns are 1-based, end column is inclusive
    let startCol = lineStr.distance(from: lineStart, to: slice.lowerBound) + 1
    let endCol   = lineStr.distance(from: lineStart, to: slice.upperBound)   // upperBound is after last char

    let fileStack = tok.range.start.fileStack
    let startPos = AdocPos(
        offset: slice.lowerBound,
        line: tok.line,
        column: startCol,
        fileStack: fileStack
    )

    let endPos = AdocPos(
        offset: slice.upperBound,   // still exclusive in terms of index
        line: tok.line,
        column: endCol,             // inclusive column number
        fileStack: fileStack
    )

    return AdocRange(start: startPos, end: endPos)
}
