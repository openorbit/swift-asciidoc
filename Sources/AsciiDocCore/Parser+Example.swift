//
// Copyright (c) 2025 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

extension AdocParser {
    func parseExample(
        it: inout TokenIter,
        env: AttrEnv
    ) -> AdocExample? {
        // We expect the current token to be an example fence
        guard let open = it.peek(),
              case .blockFence(let kind, let fenceLen) = open.kind,
              kind == .example
        else {
            return nil
        }

        // Consume the opening "====" line
        it.consume()

        // Parse inner blocks until we see a matching example fence
        let innerBlocks: [AdocBlock] = parseBlocks(it: &it, env: env) { tok in
            if case .blockFence(let k, let l) = tok.kind,
               k == .example, l == fenceLen {
                return true   // stop before this token
            }
            return false
        }

        // Consume closing fence if present
        var closeTok: Token? = nil
        if let tok = it.peek(),
           case .blockFence(let k, let l) = tok.kind,
           k == .example, l == fenceLen {
            closeTok = tok
            it.consume()
        }

        // Compute block span: from opening fence to closing fence (if any),
        // otherwise to the end of the last inner block or just the opening line.
        let span: AdocRange? = {
            if let close = closeTok {
                return AdocRange(start: open.range.start, end: close.range.end)
            }
            if let last = innerBlocks.last {
                switch last {
                case .section(let s):       return s.span.map { AdocRange(start: open.range.start, end: $0.end) }
                case .paragraph(let p):     return p.span.map { AdocRange(start: open.range.start, end: $0.end) }
                case .listing(let l):       return l.span.map { AdocRange(start: open.range.start, end: $0.end) }
                case .list(let l):          return l.span.map { AdocRange(start: open.range.start, end: $0.end) }
                case .discreteHeading(let h): return h.span.map { AdocRange(start: open.range.start, end: $0.end) }
                case .sidebar(let sb):      return sb.span.map { AdocRange(start: open.range.start, end: $0.end) }
                case .example(let ex):      return ex.span.map { AdocRange(start: open.range.start, end: $0.end) }
                case .quote(let q):         return q.span.map { AdocRange(start: open.range.start, end: $0.end) }
                case .blockMacro(let m):    return m.span.map { AdocRange(start: open.range.start, end: $0.end) }
                case .open(let o):          return o.span.map { AdocRange(start: open.range.start, end: $0.end) }
                case .admonition(let a):    return a.span.map { AdocRange(start: open.range.start, end: $0.end) }
                case .verse(let v):         return v.span.map { AdocRange(start: open.range.start, end: $0.end) }
                case .literalBlock(let lb): return lb.span.map { AdocRange(start: open.range.start, end: $0.end) }
                case .dlist(let dl): return dl.span.map { AdocRange(start: open.range.start, end: $0.end) }
                case .table(let tab): return tab.span.map { AdocRange(start: open.range.start, end: $0.end) }
                case .math(let m): return m.span.map { AdocRange(start: open.range.start, end: $0.end) }
                }
            }
            return open.range
        }()

        // NOTE:
        //  - id/title/reftext/meta should be filled by your PendingMeta machinery
        //    *before* calling parseExample. Here we just build the structural node.
        return AdocExample(
            blocks: innerBlocks,
            delimiter: String(repeating: "=", count: fenceLen),
            id: nil,
            title: nil,
            reftext: nil,
            meta: .init(),
            span: span
        )
    }}
