//
// Copyright (c) 2025 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

extension AdocParser {
    func parseLiteralBlock(
        it: inout TokenIter,
        env: AttrEnv
    ) -> AdocLiteralBlock? {
        guard let open = it.peek(),
              case .blockFence(let kind, let fenceLen) = open.kind,
              kind == .literal
        else { return nil }

        it.consume() // consume opening "...."

        var lines: [String] = []
        var firstBodyTok: Token? = nil
        var lastBodyTok: Token? = nil
        var closeTok: Token? = nil

        inner: while let tok = it.peek() {
            switch tok.kind {
            case .blockFence(let k, let len) where k == .literal && len == fenceLen:
                closeTok = tok
                it.consume()
                break inner

            case .blank:
                lines.append("")
                firstBodyTok = firstBodyTok ?? tok
                lastBodyTok = tok
                it.consume()

            default:
                lines.append(it.rawLineText(of: tok))
                firstBodyTok = firstBodyTok ?? tok
                lastBodyTok = tok
                it.consume()
            }
        }

        let bodyText = lines.joined(separator: "\n")

        // block span: fence → fence
        let blockSpan: AdocRange? = {
            if let close = closeTok {
                return spanFromTokens(start: open, end: close, it: it)
            } else {
                return it.spanForLine(open)
            }
        }()

        // body span: first/last content line
        let bodySpan: AdocRange? = {
            if let f = firstBodyTok, let l = lastBodyTok {
                return spanFromTokens(start: f, end: l, it: it)
            }
            return nil
        }()

        return AdocLiteralBlock(
            text: AdocText(plain: bodyText, span: bodySpan),
            delimiter: String(repeating: ".", count: fenceLen),
            id: nil,
            title: nil,
            reftext: nil,
            meta: .init(),
            span: blockSpan
        )
    }
}

extension AdocBlockMeta {
    var isLiteral: Bool {
        attributes["literal"] != nil ||
        attributes["style"] == "literal" ||
        roles.contains("literal")
    }
}
