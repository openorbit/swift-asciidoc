//
// Copyright (c) 2025 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//


extension AdocParser {
    /// Build a single description-list item from the current `.dlistItem` token.
    /// IMPORTANT: this function CONSUMES the `.dlistItem` token.
    private func makeDListItem(
        it: inout TokenIter,
        env: AttrEnv
    ) -> AdocDListItem {
        guard let tok = it.peek(),
              case .dlistItem(let termRange, _, let descRange) = tok.kind
        else {
            // Shouldn't happen — return an empty stub if it does
            return AdocDListItem(
                term: AdocText(plain: "", span: nil),
                principal: nil,
                blocks: [],
                id: nil,
                title: nil,
                reftext: nil,
                meta: .init(),
                span: nil
            )
        }

        let line = tok.string

        // Term
        let termSlice = line[termRange]
        var termText  = AdocText(
            plain: String(termSlice),
            span: spanForSlice(termRange, in: tok)
        )
        termText = termText.applyingAttributes(using: env)

        // Optional principal (inline description on same line)
        var principalText: AdocText? = nil
        if let dRange = descRange {
            let descSlice = line[dRange]
            var descText  = AdocText(
                plain: String(descSlice),
                span: spanForSlice(dRange, in: tok)
            )
            descText = descText.applyingAttributes(using: env)
            principalText = descText
        }

        let itemSpan = tok.range

        // CONSUME token
        it.consume()

        return AdocDListItem(
            term: termText,
            principal: principalText,
            blocks: [],
            id: nil,
            title: nil,
            reftext: nil,
            meta: .init(),
            span: itemSpan
        )
    }

    private func finalizeDList(
        marker: String,
        items: [AdocDListItem],
        firstTok: Token?,
        lastTok: Token?
    ) -> AdocDList? {
        guard !items.isEmpty,
              let f = firstTok,
              let l = lastTok
        else { return nil }

        let span = AdocRange(start: f.range.start, end: l.range.end)

        return AdocDList(
            marker: marker,
            items: items,
            id: nil,
            title: nil,
            reftext: nil,
            meta: .init(),
            span: span
        )
    }

    /// Parse a description list starting at the current `.dlistItem`,
    /// using `marker` as the current level's marker string (e.g. "::", ";;").
    /// `stack` tracks markers for *outer* levels (e.g. ["::"] when parsing ";;").
    func parseDList(
        for marker: String,
        it: inout TokenIter,
        env: AttrEnv,
        stack: inout [String]
    ) -> AdocDList? {
        stack.append(marker)
        defer { _ = stack.popLast() }

        var items: [AdocDListItem] = []
        var firstTok: Token?
        var lastTok: Token?

        outer: while let tok = it.peek() {
            switch tok.kind {

            case .blank:
                // Blank lines between items are allowed
                it.consume()
                continue outer

            case .dlistItem(_, let sepRange, _):
                let line       = tok.string
                let thisMarker = String(line[sepRange])   // "::", ":::","::::", ";;"

                if firstTok == nil { firstTok = tok }
                lastTok = tok

                if thisMarker == marker {
                    // Same marker → sibling item at this level
                    let item = makeDListItem(it: &it, env: env)   // consumes token
                    items.append(item)
                    continue outer
                }

                // Marker that belongs to an *outer* level?
                if stack.dropLast().contains(thisMarker) {
                    // Do NOT consume; let caller handle this token
                    return finalizeDList(marker: marker,
                                         items: items,
                                         firstTok: firstTok,
                                         lastTok: lastTok)
                }

                // New marker not in any outer level → nested dlist under last item
                if var lastItem = items.popLast() {
                    if let nested = parseDList(for: thisMarker, it: &it, env: env, stack: &stack) {
                        lastItem.blocks.append(.dlist(nested))
                    }
                    items.append(lastItem)
                    continue outer
                } else {
                    // No items yet; this should be a separate dlist handled by caller
                    return finalizeDList(marker: marker,
                                         items: items,
                                         firstTok: firstTok,
                                         lastTok: lastTok)
                }

            case .continuation:
                // Attach one or more following blocks to the last item.
                // IMPORTANT: if the next token is a `.dlistItem`, we must use
                // `parseDList` with the *current* stack, not `parseBlock`, so the
                // nested dlist sees the outer markers (e.g. "::").
                it.consume() // consume '+'

                guard var lastItem = items.popLast() else { continue outer }

                if let nextTok = it.peek() {
                    switch nextTok.kind {
                    case .dlistItem(_, let sepRange, _):
                        let line       = nextTok.string
                        let thisMarker = String(line[sepRange])

                        if let nested = parseDList(for: thisMarker, it: &it, env: env, stack: &stack) {
                            lastItem.blocks.append(.dlist(nested))
                        }

                    default:
                        if let nestedBlock = parseBlock(it: &it, env: env) {
                            lastItem.blocks.append(nestedBlock)
                        }
                    }
                }

                items.append(lastItem)
                continue outer

            default:
                // Any other structural token ends this dlist level
                break outer
            }
        }

        return finalizeDList(marker: marker,
                             items: items,
                             firstTok: firstTok,
                             lastTok: lastTok)
    }}
