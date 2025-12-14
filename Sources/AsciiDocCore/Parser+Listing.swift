//
// Copyright (c) 2025 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

//
//  Parser+Listing.swift
//  AsciiDoc-Swift
//
//  Created by Mattias Holm on 2025-11-19.
//

extension AdocParser {
    func parseListing(it: inout TokenIter, env: AttrEnv) -> AdocListing? {
        guard let open = it.peek(), case .blockFence(let kind, let len) = open.kind, kind == .listing else { return nil }
        it.consume() // consume opener

        var bodyLines: [String] = []
        var firstBodyTok: Token? = nil
        var lastBodyTok: Token? = nil
        var closeTok: Token? = nil

        while let t = it.peek() {
            switch t.kind {
            case .blockFence(let k, _) where k == .listing:
                closeTok = t
                it.consume() // consume closer
                let text = bodyLines.joined(separator: "\n")
                // Listing block span: fence → fence
                let blockSpan: AdocRange = spanFromTokens(start: open, end: closeTok!, it: it)
                // Body-only span: from first body token to last body token (may be nil if empty)
                let bodySpan: AdocRange? = {
                    if let f = firstBodyTok, let l = lastBodyTok { return spanFromTokens(start: f, end: l, it: it) }
                    return nil
                }()
                var listing = AdocListing(
                    text: AdocText(plain: text, span: bodySpan),   // <-- body-only span for inline content
                    delimiter: String(repeating: "-", count: len),
                    id: nil, title: nil, reftext: nil, meta: .init(),
                    span: blockSpan                                 // <-- fence-to-fence for the block
                )
                listing = listing.applyingAttributes(using: env)
                return listing
            case .blank:
                // Preserve blank line inside listing
                bodyLines.append("")
                firstBodyTok = firstBodyTok ?? t
                lastBodyTok = t
                it.consume()
            default:
                // Treat any other line kind as verbatim content within the listing (preserve indentation)
                bodyLines.append(it.rawLineText(of: t))
                firstBodyTok = firstBodyTok ?? t
                lastBodyTok = t
                it.consume()
            }
        }
        // Unterminated: still create listing with what we have
        let text = bodyLines.joined(separator: "\n")
        let blockSpan = it.spanForLine(open)
        let bodySpan: AdocRange? = {
            if let f = firstBodyTok, let l = lastBodyTok { return spanFromTokens(start: f, end: l, it: it) }
            return nil
        }()
        var listing = AdocListing(text: AdocText(plain: text, span: bodySpan),
                           delimiter: String(repeating: "-", count: len),
                           id: nil, title: nil, reftext: nil, meta: .init(),
                           span: blockSpan)
        listing = listing.applyingAttributes(using: env)
        return listing
    }
}
