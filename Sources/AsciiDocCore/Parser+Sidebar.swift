//
// Copyright (c) 2025 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

extension AdocParser {
    func parseSidebar(
        it: inout TokenIter,
        env: AttrEnv
    ) -> AdocSidebar? {
        guard let open = it.peek(),
              case .blockFence(let kind, let fenceLen) = open.kind,
              kind == .sidebar
        else { return nil }

        it.consume() // consume opening fence

        // Parse inner blocks until we see a *matching* sidebar fence
        let blocks = parseBlocks(it: &it, env: env) { tok in
            if case .blockFence(let k, let l) = tok.kind,
               k == .sidebar, l == fenceLen {
                return true
            }
            return false
        }

        // Now consume the closing fence if present
        var closeTok: Token? = nil
        if let tok = it.peek(),
           case .blockFence(let k, let l) = tok.kind,
           k == .sidebar, l == fenceLen {
            closeTok = tok
            it.consume()
        }

        let span: AdocRange? = {
            guard let endTok = closeTok ?? blocks.lastToken() ?? open as Token? else {
                return open.range
            }
            return AdocRange(start: open.range.start, end: endTok.range.end)
        }()

        return AdocSidebar(
            blocks: blocks,
            delimiter: String(repeating: "*", count: fenceLen),
            id: nil,
            title: nil,
            reftext: nil,
            meta: .init(),
            span: span
        )
    }


}
private extension Array where Element == AdocBlock {
    func lastToken() -> Token? { nil /* optional helper if you want better spans */ }
}
