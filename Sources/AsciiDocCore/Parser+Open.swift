//
// Copyright (c) 2025 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

extension AdocParser {
    func parseOpen(
        it: inout TokenIter,
        env: AttrEnv
    ) -> AdocOpen? {
        guard let open = it.peek(),
              case .blockFence(let kind, let fenceLen) = open.kind,
              kind == .open
        else { return nil }

        it.consume() // consume `--`

        var blocks: [AdocBlock] = []
        var closeTok: Token? = nil

        inner: while let tok = it.peek() {
            switch tok.kind {
            case .blockFence(let k, let len) where k == .open && len == fenceLen:
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

        let span: AdocRange? = {
            if let close = closeTok {
                return spanFromTokens(start: open, end: close, it: it)
            } else {
                return it.spanForLine(open)
            }
        }()

        return AdocOpen(
            blocks: blocks,
            delimiter: String(repeating: "-", count: fenceLen),
            id: nil,
            title: nil,
            reftext: nil,
            meta: .init(),
            span: span
        )
    }
}
