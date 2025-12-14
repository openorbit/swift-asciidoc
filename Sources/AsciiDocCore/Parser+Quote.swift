//
// Copyright (c) 2025 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

extension AdocParser {
    // Quote (____) parsing with attribution
    func parseQuote(it: inout TokenIter, env: AttrEnv) -> AdocQuote? {
        guard let open = it.peek(),
              case .blockFence(let kind, let fenceLen) = open.kind,
              kind == .quote
        else { return nil }

        it.consume() // consume opening fence

        var blocks: [AdocBlock] = []
        var closeTok: Token? = nil

        // parse inner blocks...
        inner: while let tok = it.peek() {
            switch tok.kind {
            case .blockFence(let k, let len) where k == .quote && len == fenceLen:
                closeTok = tok
                it.consume()
                break inner

            case .blank:
                it.consume()

            default:
                if let b = parseBlock(it: &it, env: env) {
                    blocks.append(b)
                } else {
                    it.consume()
                }
            }
        }

        let baseSpan: AdocRange? = {
            if let close = closeTok {
                return spanFromTokens(start: open, end: close, it: it)
            } else {
                return it.spanForLine(open)
            }
        }()

        var quote = AdocQuote(
            blocks: blocks,
            delimiter: String(repeating: "_", count: fenceLen),
            id: nil,
            title: nil,
            reftext: nil,
            attribution: nil,
            citetitle: nil,
            meta: .init(),
            span: baseSpan
        )

        // --- Attribution line: `-- Author` ---
        if let next = it.peek(), case .text = next.kind {
            let raw = next.string.trimmingCharacters(in: .whitespaces)

            if raw.hasPrefix("--") {
                it.consume() // consume attribution line

                var rest = raw.dropFirst(2)        // drop "--"
                if rest.first == " " { rest = rest.dropFirst() }

                let attributionText = String(rest)
                if !attributionText.isEmpty {
                    quote.attribution = AdocText(plain: attributionText, span: next.range)
                }

                quote.span = combinedSpan(metaSpan: quote.span, innerSpan: next.range)

                // Optional citetitle line just after attribution
                if let ctTok = it.peek(), case .text = ctTok.kind {
                    let ctRaw = ctTok.string.trimmingCharacters(in: .whitespaces)
                    if !ctRaw.isEmpty && !ctRaw.hasPrefix("--") {
                        quote.citetitle = AdocText(plain: ctRaw, span: ctTok.range)
                        quote.span = combinedSpan(metaSpan: quote.span, innerSpan: ctTok.range)
                        it.consume()
                    }
                }
            }
        }

        return quote
    }
}
