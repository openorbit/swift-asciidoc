//
// Copyright (c) 2025 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

extension AdocParser {
    func parseParagraph(
        it: inout TokenIter,
        env: AttrEnv
    ) -> AdocParagraph? {
        guard let first = it.peek() else { return nil }

        // Paragraphs start only on plain text / directive lines.
        switch first.kind {
        case .text, .directive:
            break
        default:
            return nil
        }

        var lines: [String] = []
        var lastTok: Token = first

        while let t = it.peek() {
            switch t.kind {
            case .text, .directive:
                lines.append(it.contentText(of: t))
                lastTok = t
                it.consume()

            default:
                // Hit a structural boundary (blank, list item, fence, etc.)
                if lines.isEmpty { return nil }
                let paraSpan = spanFromTokens(start: first, end: lastTok, it: it)

                var text = AdocText(
                    plain: lines.joined(separator: "\n"),
                    span: paraSpan
                )
                text = text.applyingAttributes(using: env)

                return AdocParagraph(
                    text: text,
                    id: nil,
                    title: nil,
                    reftext: nil,
                    meta: .init(),
                    span: paraSpan
                )
            }
        }

        // EOF while still in paragraph
        if lines.isEmpty { return nil }
        let paraSpan = spanFromTokens(start: first, end: lastTok, it: it)

        var text = AdocText(
            plain: lines.joined(separator: "\n"),
            span: paraSpan
        )
        text = text.applyingAttributes(using: env)

        return AdocParagraph(
            text: text,
            id: nil,
            title: nil,
            reftext: nil,
            meta: .init(),
            span: paraSpan
        )
    }
}
