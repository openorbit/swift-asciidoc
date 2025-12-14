//
// Copyright (c) 2025 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

package let knownAdmonitions: Set<String> = [
    "NOTE", "TIP", "WARNING", "CAUTION", "IMPORTANT"
]

package let knownBlockStyles: Set<String> = ["verse", "quote", "literal", "source",
                                             "sidebar", "example", "open", "bibliography"]

package extension AdocBlockMeta {
    mutating func mergeNonStructural(from other: AdocBlockMeta) {
        attributes.merge(other.attributes, uniquingKeysWith: { _, new in new })
        options.formUnion(other.options)
        roles.append(contentsOf: other.roles)
        if span == nil { span = other.span }
        if reftext == nil { reftext = other.reftext }
    }
}

extension AdocBlockMeta {
    var admonitionKind: String? {
        if let style = attributes["style"], knownAdmonitions.contains(style) {
            return style
        }
        return nil
    }

    mutating func extendSpan(with tok: Token) {
        if let s = span {
            span = AdocRange(start: s.start, end: tok.range.end)
        } else {
            span = tok.range
        }
    }

    mutating func mergeBlockMeta(from tok: Token) {
        guard case .blockMeta(let rawRange, let idRange, let roleRanges, let optRanges) = tok.kind else {
            return
        }
        let line = tok.string

        // ID via shorthand [#id]
        if let idRange {
            let id = String(line[idRange]).trimmingCharacters(in: .whitespaces)
            if !id.isEmpty { self.id = id }
        }

        // Roles via [.role1.role2] etc.
        for r in roleRanges {
            let role = String(line[r]).trimmingCharacters(in: .whitespaces)
            if !role.isEmpty { roles.append(role) }
        }

        // Options via [%optA%optB]
        for r in optRanges {
            let opt = String(line[r]).trimmingCharacters(in: .whitespaces)
            if !opt.isEmpty { options.insert(opt) }
        }

        // Named attributes (alt=, width=, role=, etc) from the raw payload
        let content = line[rawRange]
        mergeNamedAttributes(from: content)
    }

    mutating func mergeNamedAttributes(from content: Substring) {
        let fragments = splitAttributeFragments(in: content)
        var positionalIndex = 1

        for frag in fragments {
            let trimmed = frag.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            // Skip things that are clearly handled elsewhere
            if trimmed.first == "." || trimmed.first == "#" || trimmed.first == "%" {
                continue
            }

            // Case 1: key=value
            if let eq = trimmed.firstIndex(of: "=") {
                let key = trimmed[..<eq].trimmingCharacters(in: .whitespaces)
                var value = trimmed[trimmed.index(after: eq)...]

                if let first = value.first, (first == "\"" || first == "'"),
                   let last = value.last, last == first, value.count >= 2 {
                    value = value.dropFirst().dropLast()
                }

                if !key.isEmpty {
                    attributes[String(key)] = String(value)
                }
                continue
            }

            // Case 2: bare word – treat ALLCAPS known admonitions as style
            let word = String(trimmed)
            let positionalKey = String(positionalIndex)
            attributes[positionalKey] = word
            if positionalIndex == 2, attributes["target"] == nil {
                attributes["target"] = word
            }
            positionalIndex += 1

            if knownAdmonitions.contains(word) {
                attributes["style"] = word
            } else if knownBlockStyles.contains(word) {
                // This is a structural block style like [verse], [quote], [literal], ...
                attributes["style"] = word
            } else {
                // If no explicit style has been set yet, treat the first bare word as style.
                if attributes["style"] == nil {
                    attributes["style"] = word
                }
            }
        }
    }

    private func splitAttributeFragments(in content: Substring) -> [Substring] {
        var result: [Substring] = []
        var start = content.startIndex
        var idx = content.startIndex
        var quote: Character?

        while idx < content.endIndex {
            let ch = content[idx]
            if ch == "\"" || ch == "'" {
                if quote == ch {
                    quote = nil
                } else if quote == nil {
                    quote = ch
                }
            } else if ch == "," && quote == nil {
                result.append(content[start..<idx])
                idx = content.index(after: idx)
                start = idx
                continue
            }
            idx = content.index(after: idx)
        }

        if start <= content.endIndex {
            result.append(content[start..<content.endIndex])
        }

        return result
    }
}

extension AdocParser {
    /// Detect `[[id]]` or `[[id,reftext]]` as a block anchor line.
    private func parseBlockAnchor(_ line: Substring) -> (id: String, reftext: String?)? {
        guard line.hasPrefix("[["), let close = line.range(of: "]]") else { return nil }

        let inner = line[line.index(line.startIndex, offsetBy: 2)..<close.lowerBound]
        let trimmed = inner.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        if let comma = trimmed.firstIndex(of: ",") {
            let idPart = trimmed[..<comma].trimmingCharacters(in: .whitespaces)
            let refPart = trimmed[trimmed.index(after: comma)...].trimmingCharacters(in: .whitespaces)
            guard !idPart.isEmpty else { return nil }
            return (id: String(idPart), reftext: refPart.isEmpty ? nil : String(refPart))
        } else {
            return (id: String(trimmed), reftext: nil)
        }
    }

    /// Detect `.Title` block-title lines; returns the range *within `tok.string`* of the title.
    private func detectBlockTitle(in tok: Token) -> Range<Substring.Index>? {
        guard case .text = tok.kind else { return nil }
        let s = tok.string
        guard let first = s.first, first == "." else { return nil }

        var i = s.index(after: s.startIndex)
        // optional single space after '.'
        if i < s.endIndex, s[i] == " " {
            i = s.index(after: i)
        }
        guard i < s.endIndex else { return nil } // line was just "." or ". "
        return i..<s.endIndex
    }

    /// Consume consecutive metadata tokens (blockMeta, anchor, title) and
    /// accumulate them into `pendingMeta`. Stops at the first non-meta token.
    /// Does not consume that non-meta token.
    /// Consume consecutive metadata tokens (blockMeta, anchor, title) and
    /// return an `AdocBlockMeta` snapshot for the *next* block.
    /// Stops at the first non-meta token and does not consume that token.
    func consumeBlockMeta(
        it: inout TokenIter,
        env: AttrEnv  // kept for future attribute interpolation if needed
    ) -> AdocBlockMeta {
        var meta = AdocBlockMeta()

        metaLoop: while let tok = it.peek() {
            switch tok.kind {
            case .blockMeta:
                meta.mergeBlockMeta(from: tok)
                meta.extendSpan(with: tok)
                it.consume()

            case .text:
                let line = tok.string

                // Anchor line: [[id]] / [[id,reftext]]
                if let (id, reftext) = parseBlockAnchor(line) {
                    meta.id = id
                    if let reftext, !reftext.isEmpty {
                        var refText = AdocText(plain: reftext, span: nil)
                        refText = refText.applyingAttributes(using: env)
                        meta.reftext = refText
                    }
                    meta.extendSpan(with: tok)
                    it.consume()
                    continue metaLoop
                }

                // Block title line: .Title
                if let titleRange = detectBlockTitle(in: tok) {
                    let titlePlain = String(line[titleRange])
                    let titleSpan  = spanForSlice(titleRange, in: tok)
                    let titleText  = AdocText(plain: titlePlain, span: titleSpan)
                    meta.title = titleText
                    meta.extendSpan(with: tok)
                    it.consume()
                    continue metaLoop
                }

                // Plain text but not anchor/title → not metadata
                break metaLoop

            case .blank:
                // A blank terminates metadata but belongs to the block, so don’t consume.
                break metaLoop

            default:
                // Any structural token ends metadata
                break metaLoop
            }
        }

        return meta
    }
}



private extension AdocParagraph {
    mutating func apply(meta m: AdocBlockMeta) {
        if let id = m.id { self.id = self.id ?? id }
        if let t  = m.title { self.title = self.title ?? t }
        if let r  = m.reftext { self.reftext = self.reftext ?? r }
        self.meta.mergeNonStructural(from: m)
    }
}

private extension AdocListing {
    mutating func apply(meta m: AdocBlockMeta) {
        if let id = m.id { self.id = self.id ?? id }
        if let t  = m.title { self.title = self.title ?? t }
        if let r  = m.reftext { self.reftext = self.reftext ?? r }
        self.meta.mergeNonStructural(from: m)
    }
}

private extension AdocList {
    mutating func apply(meta m: AdocBlockMeta) {
        if let id = m.id { self.id = self.id ?? id }
        if let t  = m.title { self.title = self.title ?? t }
        if let r  = m.reftext { self.reftext = self.reftext ?? r }
        self.meta.mergeNonStructural(from: m)
    }
}

private extension AdocDList {
    mutating func apply(meta m: AdocBlockMeta) {
        if let id = m.id { self.id = self.id ?? id }
        if let t  = m.title { self.title = self.title ?? t }
        if let r  = m.reftext { self.reftext = self.reftext ?? r }
        self.meta.mergeNonStructural(from: m)
    }
}

private extension AdocSection {
    mutating func apply(meta m: AdocBlockMeta) {
        if let id = m.id { self.id = self.id ?? id }
        // Treat block title from meta as reftext / caption, not as heading text.
        if let t = m.title, self.reftext == nil {
            self.reftext = t
        }
        if let r = m.reftext, self.reftext == nil {
            self.reftext = r
        }
        self.meta.mergeNonStructural(from: m)
    }
}

private extension AdocDiscreteHeading {
    mutating func apply(meta m: AdocBlockMeta) {
        if let id = m.id { self.id = self.id ?? id }
        if let r  = m.reftext { self.reftext = self.reftext ?? r }
        self.meta.mergeNonStructural(from: m)
    }
}

private extension AdocSidebar {
    mutating func apply(meta m: AdocBlockMeta) {
        if let id = m.id { self.id = self.id ?? id }
        if let t  = m.title { self.title = self.title ?? t }
        if let r  = m.reftext { self.reftext = self.reftext ?? r }
        self.meta.mergeNonStructural(from: m)
    }
}

private extension AdocMathBlock {
    mutating func apply(meta m: AdocBlockMeta) {
        if let id = m.id { self.id = self.id ?? id }
        if let t  = m.title { self.title = self.title ?? t }
        if let r  = m.reftext { self.reftext = self.reftext ?? r }
        self.meta.mergeNonStructural(from: m)
    }
}

private extension AdocExample {
    mutating func apply(meta m: AdocBlockMeta) {
        if let id = m.id { self.id = self.id ?? id }
        if let t  = m.title { self.title = self.title ?? t }
        if let r  = m.reftext { self.reftext = self.reftext ?? r }
        self.meta.mergeNonStructural(from: m)
    }
}

private extension AdocQuote {
    mutating func apply(meta m: AdocBlockMeta) {
        if let id = m.id { self.id = self.id ?? id }
        if let t  = m.title { self.title = self.title ?? t }
        if let r  = m.reftext { self.reftext = self.reftext ?? r }
        self.meta.mergeNonStructural(from: m)
    }
}

private extension AdocOpen {
    mutating func apply(meta m: AdocBlockMeta) {
        if let id = m.id { self.id = self.id ?? id }
        if let t  = m.title { self.title = self.title ?? t }
        if let r  = m.reftext { self.reftext = self.reftext ?? r }
        self.meta.mergeNonStructural(from: m)
    }
}

private extension AdocAdmonition {
    mutating func apply(meta m: AdocBlockMeta) {
        if let id = m.id { self.id = self.id ?? id }
        if let t  = m.title { self.title = self.title ?? t }
        if let r  = m.reftext { self.reftext = self.reftext ?? r }
        self.meta.mergeNonStructural(from: m)
    }
}

private extension AdocVerse {
    mutating func apply(meta m: AdocBlockMeta) {
        if let id = m.id { self.id = self.id ?? id }
        if let t  = m.title { self.title = self.title ?? t }
        if let r  = m.reftext { self.reftext = self.reftext ?? r }
        self.meta.mergeNonStructural(from: m)
    }
}

private extension AdocLiteralBlock {
    mutating func apply(meta m: AdocBlockMeta) {
        if let id = m.id { self.id = self.id ?? id }
        if let t  = m.title { self.title = self.title ?? t }
        if let r  = m.reftext { self.reftext = self.reftext ?? r }
        self.meta.mergeNonStructural(from: m)
    }
}

private extension AdocTable {
    mutating func apply(meta m: AdocBlockMeta) {
        if let id = m.id { self.id = self.id ?? id }
        if let t  = m.title { self.title = self.title ?? t }
        if let r  = m.reftext { self.reftext = self.reftext ?? r }
        self.meta.mergeNonStructural(from: m)
    }
}

extension AdocBlockMeta {
    func applyMeta(
        to block: inout AdocBlock
    ) {
        guard !(attributes.isEmpty && options.isEmpty && roles.isEmpty
                && id == nil && title == nil && reftext == nil && span == nil)
        else { return } // nothing to do

        switch block {
        case .paragraph(var p):
            p.apply(meta: self)
            block = .paragraph(p)

        case .listing(var l):
            l.apply(meta: self)
            block = .listing(l)

        case .list(var l):
            l.apply(meta: self)
            block = .list(l)

        case .dlist(var d):
            d.apply(meta: self)
            block = .dlist(d)

        case .section(var s):
            s.apply(meta: self)
            block = .section(s)

        case .discreteHeading(var h):
            h.apply(meta: self)
            block = .discreteHeading(h)

        case .sidebar(var s):
            s.apply(meta: self)
            block = .sidebar(s)

        case .example(var e):
            e.apply(meta: self)
            block = .example(e)

        case .quote(var q):
            q.apply(meta: self)
            block = .quote(q)

        case .open(var o):
            o.apply(meta: self)
            block = .open(o)

        case .admonition(var a):
            a.apply(meta: self)
            block = .admonition(a)

        case .verse(var v):
            v.apply(meta: self)
            block = .verse(v)

        case .literalBlock(var l):
            l.apply(meta: self)
            block = .literalBlock(l)

        case .table(var t):
            t.apply(meta: self)
            block = .table(t)
        case .math(var m):
            m.apply(meta: self)
            block = .math(m)
        case .blockMacro(var m):
            m.apply(meta: self)
            block = .blockMacro(m)
        }
    }
}


extension AdocBlockMeta {
    /// Primary style, e.g. from [quote], [literal], [verse], [source,ruby]
    var primaryStyle: String? {
        // Explicit style attribute wins
        if let s = attributes["style"], !s.isEmpty {
            return s.lowercased()
        }

        // Positional first attribute: [verse], [quote,Author], [source,ruby]
        if let first = attributes["1"], !first.isEmpty {
            return first.lowercased()
        }

        // As a last resort, treat certain roles as styles
        let styleNames: Set<String> = ["verse", "quote", "literal", "source", "sidebar", "example", "open"]

        if let role = roles.first(where: { styleNames.contains($0.lowercased()) }) {
            return role.lowercased()
        }

        return nil
    }

    var isLiteralStyle: Bool {
        primaryStyle == "literal"
    }

    var isVerseStyle: Bool {
        primaryStyle == "verse"
    }

    var isQuoteStyle: Bool {
        primaryStyle == "quote"
    }

    var isSourceStyle: Bool {
        primaryStyle == "source"
    }

    var isSidebarStyle: Bool {
        primaryStyle == "sidebar"
    }

    var isExampleStyle: Bool {
        primaryStyle == "example"
    }

    var isOpenStyle: Bool {
        primaryStyle == "open"
    }
}
