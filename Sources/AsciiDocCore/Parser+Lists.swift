//
// Copyright (c) 2025 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

import Foundation

extension AdocParser {
    enum OrderedStyle: Equatable {
        case arabic        // 1.
        case lowerAlpha    // a.
        case upperAlpha    // A.
        // roman variants could be added later
    }

    enum ListMarkerKey: Equatable {
        case unordered(symbol: Character, run: Int)   // "*", "**", "-", etc
        case orderedDot(depth: Int)                   // ".", "..", "..."
        case orderedExplicit(style: OrderedStyle)     // "1.", "A.", etc
        case callout                                  // "<1> ..." markers
    }

    func markerKey(forListItem tok: Token) -> ListMarkerKey? {
        let s = tok.string
        var start = s.startIndex
        while start < s.endIndex, s[start] == " " || s[start] == "\t" {
            start = s.index(after: start)
        }
        guard start < s.endIndex else { return nil }
        let first = s[start]

        // Callout markers: "<1>"
        if first == "<" {
            var i = s.index(after: s.startIndex)
            let digitsStart = i
            while i < s.endIndex, s[i].isNumber {
                i = s.index(after: i)
            }
            if digitsStart < i, i < s.endIndex, s[i] == ">" {
                return .callout
            }
        }

        // Unordered: '*' run or single '-'
        if first == "*" || first == "-" {
            var run = 1
            var i = s.index(after: start)
            while i < s.endIndex, s[i] == first {
                run += 1
                i = s.index(after: i)
            }
            // Scanner guarantees run == 1 for '-' and may be >1 for '*'
            return .unordered(symbol: first, run: run)
        }

        // Ordered dot: ". foo", ".. foo", ...
        if first == "." {
            var depth = 0
            var i = start
            while i < s.endIndex, s[i] == "." {
                depth += 1
                i = s.index(after: i)
            }
            return .orderedDot(depth: depth)
        }

        // Explicit enumerator: "1. ", "A. ", etc. (usually only at top level)
        if let dot = s[start...].firstIndex(of: ".") {
            let head = s[start..<dot]
            if head.allSatisfy({ $0.isNumber }) {
                return .orderedExplicit(style: .arabic)
            }
            if head.allSatisfy({ $0.isLowercase }) {
                return .orderedExplicit(style: .lowerAlpha)
            }
            if head.allSatisfy({ $0.isUppercase }) {
                return .orderedExplicit(style: .upperAlpha)
            }
        }

        return nil
    }

    func inferredListKind(from key: ListMarkerKey) -> AdocListKind {
        switch key {
        case .unordered(let symbol, _):
            return .unordered(marker: String(symbol))
        case .orderedDot:
            return .ordered(marker: ".")
        case .orderedExplicit:
            return .ordered(marker: ".") // Could refine later by style
        case .callout:
            return .callout
        }
    }
    // Helper: build an AdocListItem from the current .listItem token.
    // Reuse your existing principal / checkbox / span logic inside this.
    // Build one list item from the current .listItem token.
    // IMPORTANT: this function CONSUMES the current .listItem token.
    /// Build one list item from the current `.listItem` token.
    /// IMPORTANT: this function CONSUMES the `.listItem` token.
    /// Build one list item from the current `.listItem` token.
    /// IMPORTANT: this function CONSUMES the `.listItem` token.
    private func makeListItem(
        it: inout TokenIter,
        env: AttrEnv,
        markerKey: ListMarkerKey,
        bibliographyStyle: Bool
    ) -> AdocListItem {
        guard let tok = it.peek(), case .listItem = tok.kind else {
            // Shouldn't happen, but return a stub if it does
            return AdocListItem(
                marker: "",
                principal: AdocText(plain: "", span: nil),
                blocks: [],
                id: nil,
                title: nil,
                reftext: nil,
                meta: .init(),
                span: nil
            )
        }

        let principalRange = principalSlice(in: tok, markerKey: markerKey)
        var principalPlain = String(tok.string[principalRange])
        let principalSpan  = spanForSlice(principalRange, in: tok)
        let itemSpan       = tok.range

        var bibliographyMarker: (id: String, label: String?)?
        if bibliographyStyle, let parsed = extractBibliographyAnchor(from: principalPlain) {
            principalPlain = parsed.remainder
            bibliographyMarker = (parsed.id, parsed.label)
        }

        var principalText = AdocText(plain: principalPlain, span: principalSpan)
        principalText = principalText.applyingAttributes(using: env)

        let markerString: String = {
            switch markerKey {
            case .unordered(let symbol, _):
                return String(symbol)     // bullet marker
            case .orderedDot:
                return "."                // dot-based ordered
            case .orderedExplicit:
                return "."                // refine later if needed
            case .callout:
                if case let .listItem(_, _, ordinal, _, _) = tok.kind,
                   let ord = ordinal {
                    return "<\(ord)>"
                }
                // Fallback: try to recover digits from the raw line
                let line = tok.string
                if let open = line.firstIndex(of: "<"),
                   let close = line[open...].firstIndex(of: ">"),
                   line.index(after: open) < close {
                    let digits = line[line.index(after: open)..<close]
                    let number = digits.isEmpty ? "1" : String(digits)
                    return "<\(number)>"
                }
                return "<1>"
            }
        }()

        // CONSUME the list-item token
        it.consume()

        var item = AdocListItem(
            marker: markerString,
            principal: principalText,
            blocks: [],
            id: nil,
            title: nil,
            reftext: nil,
            meta: .init(),
            span: itemSpan
        )

        if bibliographyStyle, let marker = bibliographyMarker {
            item.id = marker.id
            if let label = marker.label, !label.isEmpty {
                var labelText = AdocText(plain: label, span: nil)
                labelText = labelText.applyingAttributes(using: env)
                item.reftext = labelText
            }
        }

        return item
    }

    private func extractBibliographyAnchor(from source: String) -> (remainder: String, id: String, label: String?)? {
        var start = source.startIndex
        while start < source.endIndex, source[start].isWhitespace {
            start = source.index(after: start)
        }
        guard start < source.endIndex else { return nil }

        let slice = source[start...]
        guard slice.hasPrefix("[[[") else { return nil }
        guard let close = slice.range(of: "]]]") else { return nil }

        let innerStart = slice.index(slice.startIndex, offsetBy: 3)
        let inner = slice[innerStart..<close.lowerBound]
        let trimmedInner = inner.trimmingCharacters(in: .whitespaces)
        guard !trimmedInner.isEmpty else { return nil }

        let rawParts = trimmedInner.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
        guard let idPartRaw = rawParts.first?.trimmingCharacters(in: .whitespaces), !idPartRaw.isEmpty else {
            return nil
        }
        let labelPartRaw = rawParts.count > 1 ? rawParts[1].trimmingCharacters(in: .whitespaces) : nil

        var afterAnchor = slice[close.upperBound...]
        while afterAnchor.first == "]" {
            afterAnchor = afterAnchor.dropFirst()
        }
        let trimmedRemainder = afterAnchor.drop { $0.isWhitespace }
        let remainder = String(trimmedRemainder)

        let labelString: String?
        if let labelPartRaw, !labelPartRaw.isEmpty {
            labelString = labelPartRaw
        } else {
            labelString = nil
        }

        return (remainder: remainder, id: idPartRaw, label: labelString)
    }


    func parseList(
        for marker: ListMarkerKey,
        listKind: AdocListKind,
        it: inout TokenIter,
        env: AttrEnv,
        stack: inout [ListMarkerKey],
        bibliographyStyle: Bool = false
    ) -> AdocList? {
        stack.append(marker)
        defer { _ = stack.popLast() }

        var items: [AdocListItem] = []
        var firstTok: Token?
        var lastTok: Token?

        outer: while let tok = it.peek() {
            switch tok.kind {

            case .blank:
                // Blank lines between items are allowed; just skip them
                it.consume()
                continue outer

            case .listItem:
                guard let key = markerKey(forListItem: tok) else {
                    // Not a valid marker after all; consume and skip
                    it.consume()
                    continue outer
                }

                if firstTok == nil { firstTok = tok }
                lastTok = tok

                if key == marker {
                    // Same marker → sibling item on this level
                    let item = makeListItem(it: &it, env: env, markerKey: key, bibliographyStyle: bibliographyStyle) // consumes token
                    items.append(item)
                    continue outer
                }

                if stack.dropLast().contains(key) {
                    // Marker belongs to an *outer* level — stop here and let caller handle it
                    return finalizeList(
                        kind: listKind,
                        items: items,
                        firstTok: firstTok,
                        lastTok: lastTok
                    )
                }

                // New marker not in any outer level → nested list under last item
                if var lastItem = items.popLast() {
                    if let nested = parseList(
                        for: key,
                        listKind: inferredListKind(from: key),
                        it: &it,
                        env: env,
                        stack: &stack,
                        bibliographyStyle: false
                    ) {
                        lastItem.blocks.append(.list(nested))
                    }
                    items.append(lastItem)
                    continue outer
                } else {
                    // No items yet; this should be a separate list handled by caller
                    return finalizeList(
                        kind: listKind,
                        items: items,
                        firstTok: firstTok,
                        lastTok: lastTok
                    )
                }

            case .continuation:
                // Attach the following block(s) to the last item.
                // IMPORTANT: if the next token is a `.listItem`, we must call
                // `parseList` directly (with current `stack`) so nested lists
                // see outer markers and can snap back correctly.
                it.consume() // consume '+'

                guard var lastItem = items.popLast() else { continue outer }

                if let nextTok = it.peek() {
                    switch nextTok.kind {
                    case .listItem:
                        if let key = markerKey(forListItem: nextTok) {
                            if let nested = parseList(
                                for: key,
                                listKind: inferredListKind(from: key),
                                it: &it,
                                env: env,
                                stack: &stack,
                                bibliographyStyle: false
                            ) {
                                lastItem.blocks.append(.list(nested))
                            }
                        } else {
                            // Invalid list marker; fall back to generic block parsing
                            if let block = parseBlock(it: &it, env: env) {
                                lastItem.blocks.append(block)
                            }
                        }

                    default:
                        if let block = parseBlock(it: &it, env: env) {
                            lastItem.blocks.append(block)
                        }
                    }
                }

                items.append(lastItem)
                continue outer

            default:
                // Any other structural token ends this list level
                break outer
            }
        }

        return finalizeList(
            kind: listKind,
            items: items,
            firstTok: firstTok,
            lastTok: lastTok
        )
    }

    // Compute principal absolute range for a list line by scanning the *source text*
    // using UTF-8 offsets. This avoids double-applying relative transforms.
    private func principalSlice(
        in tok: Token,
        markerKey: ListMarkerKey
    ) -> Range<Substring.Index> {
        let s = tok.string
        var i = s.startIndex
        let end = s.endIndex

        // Optional leading whitespace
        while i < end, s[i].isWhitespace {
            i = s.index(after: i)
        }

        // Skip marker according to key
        switch markerKey {
        case .unordered(let symbol, let run):
            var remaining = run
            while remaining > 0, i < end, s[i] == symbol {
                i = s.index(after: i)
                remaining -= 1
            }

        case .orderedDot(let depth):
            var remaining = depth
            while remaining > 0, i < end, s[i] == "." {
                i = s.index(after: i)
                remaining -= 1
            }

        case .orderedExplicit:
            // Skip until first '.' (e.g. "1.", "A.", "2.1.")
            while i < end, s[i] != "." {
                i = s.index(after: i)
            }
            if i < end && s[i] == "." {
                i = s.index(after: i)
            }
        case .callout:
            if i < end, s[i] == "<" {
                i = s.index(after: i)
                while i < end, s[i].isNumber {
                    i = s.index(after: i)
                }
                if i < end, s[i] == ">" {
                    i = s.index(after: i)
                }
            }
        }

        // One optional space
        if i < end, s[i].isWhitespace {
            i = s.index(after: i)
        }

        // Optional checkbox: "[ ]", "[x]", "[X]" possibly followed by a space
        if i < end, s[i] == "[" {
            let startBracket = i
            let afterBracket = s.index(after: startBracket)
            if afterBracket < end {
                let closing = s.index(after: afterBracket)
                if closing < end, s[closing] == "]" {
                    let bodyChar = s[afterBracket]
                    if bodyChar == " " || bodyChar == "x" || bodyChar == "X" {
                        i = s.index(after: closing)
                        if i < end, s[i].isWhitespace {
                            i = s.index(after: i)
                        }
                    }
                }
            }
        }

        return i..<end
    }

    private func finalizeList(
        kind: AdocListKind,
        items: [AdocListItem],
        firstTok: Token?,
        lastTok: Token?
    ) -> AdocList? {
        guard !items.isEmpty,
              let f = firstTok,
              let l = lastTok
        else { return nil }

        let span = AdocRange(start: f.range.start, end: l.range.end)

        return AdocList(
            kind: kind,
            items: items,
            id: nil,
            title: nil,
            reftext: nil,
            meta: .init(),
            span: span
        )
    }


    /// Extract the list marker key + list kind from the first listItem token.
    func listDispatchInfo(from tok: Token) -> (key: ListMarkerKey, kind: AdocListKind)? {
        guard case let .listItem(kind, _, _, _, _) = tok.kind else {
            return nil
        }

        guard let key = markerKey(forListItem: tok) else {
            return nil
        }
        let listKind: AdocListKind
        switch kind {
        case .unordered(let markerChar):
            listKind = .unordered(marker: String(markerChar))
        case .ordered:
            listKind = .ordered(marker: ".")
        case .callout:
            listKind = .callout
        }

        return (key, listKind)
    }

    /// Extract the dlist marker string from the first dlistItem token.
    /// Uses the separator range (like "::", ";;", "::::") from your scanner.
    func dlistMarker(from tok: Token, in text: String) -> String? {
        guard case let .dlistItem(_, separatorRange, _) = tok.kind else {
            return nil
        }
        return String(text[separatorRange])
    }
}
