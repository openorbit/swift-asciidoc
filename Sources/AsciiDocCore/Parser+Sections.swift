//
// Copyright (c) 2025 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

extension AdocParser {
    func parseSection(
        from tok: Token,
        level: Int,
        titleRange: Range<String.Index>,
        it: inout TokenIter,
        env: AttrEnv
    ) -> AdocSection? {
        // Consume the section title line
        it.consume()

        let internalLevel = max(1, level - 1)

        // Title text
        let titleSlice = tok.string[titleRange]
        let titleSpan  = spanForSlice(titleRange, in: tok)
        var titleText  = AdocText(plain: String(titleSlice), span: titleSpan)
        titleText      = titleText.applyingAttributes(using: env)

        // Body: everything until we see a section with level <= this one
        let bodyBlocks = parseBlocks(it: &it, env: env) { nextTok in
            if case .atxSection(let nextLevel, _) = nextTok.kind {
                return nextLevel <= level  // stop at same or higher ATX-level
            }
            return false
        }

        // Span from this section line to last block’s end (or just the title line if empty)
        let endRange: AdocRange = {
            if let lastBlock = bodyBlocks.last {
                switch lastBlock {
                case .section(let s): return s.span ?? tok.range
                case .paragraph(let p): return p.span ?? tok.range
                case .listing(let l): return l.span ?? tok.range
                case .list(let l): return l.span ?? tok.range
                case .discreteHeading(let h): return h.span ?? tok.range
                case .sidebar(let sb): return sb.span ?? tok.range
                case .example(let ex): return ex.span ?? tok.range
                case .quote(let q): return q.span ?? tok.range
                case .open(let o): return o.span ?? tok.range
                case .admonition(let a): return a.span ?? tok.range
                case .verse(let v): return v.span ?? tok.range
                case .literalBlock(let lb): return lb.span ?? tok.range
                case .dlist(let dl): return dl.span ?? tok.range
                case .table(let tab): return tab.span ?? tok.range
                case .math(let m): return m.span ?? tok.range
                case .blockMacro(let m): return m.span ?? tok.range
                }
            }
            return tok.range
        }()

        let sec = AdocSection(
            level: internalLevel,
            title: titleText,
            blocks: bodyBlocks,
            id: nil,
            reftext: nil,
            meta: .init(),
            span: AdocRange(start: tok.range.start, end: endRange.end)
        )

        return sec
    }
}
