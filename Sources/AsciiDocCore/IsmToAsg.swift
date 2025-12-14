//
// Copyright (c) 2025 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

public protocol AdocToASG { associatedtype T; func toASG() -> T }

private extension Array where Element == AdocBlock {
    /// Convert an ISM non-section body into ASGNonSectionBlockBody using your existing `toASGItem()`.
    /// Any `.section(...)` is skipped (parent blocks can't contain sections).
    func toASGNonSectionBody_viaItems() -> ASGNonSectionBlockBody {
        self.compactMap { block in
            switch block.toASGItem() {
            case .block(let b):   return b
            case .section:        return nil
            }
        }
    }
}

extension AdocDocument: AdocToASG {
  public func toASG() -> ASGDocument {
    ASGDocument(
      attributes: (header != nil && attributes.isEmpty) ? [:] : attributes,
      header: header?.toASG(),
      blocks: blocks.compactMap { $0.toASGItem() },
      location: span?.toASG()
    )
  }
}

extension AdocBlock {
    func toASGItem() -> ASGSectionBodyItem {
        switch self {
        case .section(let s): return .section(s.toASG())
        case .paragraph(let p): return .block(p.toASG())
        case .listing(let l): return .block(l.toASG())
        case .list(let l): return .block(l.toASG())
        case .dlist(let dl): return .block(dl.toASG())
        case .discreteHeading(let h): return .block(h.toASG())
        case .sidebar(let s): return .block(s.toASG())
        case .example(let e): return .block(e.toASG())
        case .quote(let q): return .block(q.toASG())
        case .open(let o): return .block(o.toASG())
        case .admonition(let a): return .block(a.toASG())
        case .verse(let v): return .block(v.toASG())
        case .literalBlock(let l): return .block(l.toASG())
        case .table(let t): return .block(t.toASG())
        case .math(let m): return .block(m.toASG())
        case .blockMacro(let m): return .block(m.toASG())
        }
    }
}


private extension Optional where Wrapped == AdocRange {
    func toASG() -> ASGLocation? { self.map { $0.toASG() } }
}

extension AdocBlockMeta {
    func toASG() -> ASGBlockMetadata? {
        let attrs: [String:String]? = attributes.isEmpty ? nil : attributes
        let opts: [String]? = options.isEmpty ? nil : Array(options)
        let roles: [String]? = self.roles.isEmpty ? nil : self.roles
        if attrs == nil, opts == nil, roles == nil { return nil }
        return ASGBlockMetadata(attributes: attrs, options: opts, roles: roles, location: nil)
    }
}

private func mapAdmonitionKind(_ s: String?) -> ASGParentBlockVariant? {
    guard let s = s?.lowercased() else { return nil }
    switch s {
    case "note": return .note
    case "tip": return .tip
    case "warning": return .warning
    case "caution": return .caution
    case "important": return .important
    default: return nil
    }
}


extension AdocSection: AdocToASG {
    public func toASG() -> ASGSection {
        let asg = ASGSection(
            level: self.level,
            title: self.title.inlines.toASGInlines(),   // title inlines (content only) – OK
            blocks: blocks.map { $0.toASGItem() },     // children go here
            id: self.id,
            reftext: self.reftext?.inlines.toASGInlines(),
            metadata: self.meta.toASG(),
            location: self.span?.toASG()                // ← IMPORTANT: title-line only
        )
        return asg
    }
}


// Helper to convert ISM ranges/locations to ASG locations
public extension AdocRange {
    func toASG() -> ASGLocation {
        ASGLocation(
            start: .init(line: start.line, col: start.column, file: start.fileStack?.frames),
            end:   .init(line: end.line,   col: end.column,   file: end.fileStack?.frames)
        )
    }
}

public extension AdocLocation {
    func toASG() -> ASGLocation {
        ASGLocation(
            start: .init(line: start.line, col: start.col, file: start.file),
            end:   .init(line: end.line,   col: end.col,   file: end.file)
        )
    }
}

public extension AdocAuthor {
    func toASG() -> ASGAuthor {
        ASGAuthor(
            fullname: fullname,
            initials: initials,
            firstname: firstname,
            middlename: middlename,
            lastname: lastname,
            address: address
        )
    }
}

extension AdocHeader {
  public func toASG() -> ASGHeader {
    ASGHeader(
      title: title?.inlines.toASGInlines(),
      authors: authors?.map { $0.toASG() },
      location: location?.toASG()
    )
  }
}

extension AdocParagraph {
    func toASG() -> ASGBlock {
        .leaf(.init(
            name: .paragraph,
            form: nil,
            delimiter: nil,
            inlines: text.inlines.toASGInlines(),
            id: id,
            title: title?.inlines.toASGInlines(),
            reftext: reftext?.inlines.toASGInlines(),
            metadata: meta.toASG(),
            location: span?.toASG()
        ))
    }
}

extension AdocListing {
    func toASG() -> ASGBlock {
        // Force the inline literal to use the fence-to-fence location
        let inlineLoc = text.span?.toASG()
        let lit = ASGInlineLiteral(name: .text, value: text.plain, location: inlineLoc)

        return .leaf(.init(
            name: .listing,
            form: .delimited,
            delimiter: delimiter,
            inlines: [.literal(lit)],             // <- don’t pipeline through toASGInlines here
            id: id,
            title: title?.inlines.toASGInlines(),
            reftext: reftext?.inlines.toASGInlines(),
            metadata: meta.toASG(),
            location: span?.toASG()               // block location remains fence-to-fence
        ))
    }
}

extension AdocList {
    func toASG() -> ASGBlock {
        switch kind {
        case .unordered(let marker):
            return .list(.init(
                marker: marker,
                variant: .unordered,
                items: items.map { $0.toASG() },
                id: id,
                title: title?.inlines.toASGInlines(),
                reftext: reftext?.inlines.toASGInlines(),
                metadata: meta.toASG(),
                location: span?.toASG()
            ))
        case .ordered(let marker):
            return .list(.init(
                marker: marker,
                variant: .ordered,
                items: items.map { $0.toASG() },
                id: id,
                title: title?.inlines.toASGInlines(),
                reftext: reftext?.inlines.toASGInlines(),
                metadata: meta.toASG(),
                location: span?.toASG()
            ))
        case .callout:
            return .list(.init(
                marker: "<",
                variant: .callout,
                items: items.map { $0.toASG() },
                id: id,
                title: title?.inlines.toASGInlines(),
                reftext: reftext?.inlines.toASGInlines(),
                metadata: meta.toASG(),
                location: span?.toASG()
            ))
        }
    }
}

extension AdocListItem: AdocToASG {
    public func toASG() -> ASGListItem {
        ASGListItem(
            marker: marker,
            principal: principal.inlines.toASGInlines(),
            blocks: blocks.isEmpty ? nil : blocks.compactMap { $0.toASGBlockForList() },
            id: id,
            title: title?.inlines.toASGInlines(),
            reftext: reftext?.inlines.toASGInlines(),
            metadata: meta.toASG(),
            location: span?.toASG()
        )
    }
}

extension AdocDiscreteHeading {
    func toASG() -> ASGBlock {
        .discreteHeading(.init(
            level: level,
            title: title.inlines.toASGInlines(),
            id: id,
            reftext: reftext?.inlines.toASGInlines(),
            metadata: meta.toASG(),
            location: span?.toASG()
        ))
    }
}

// Helper: convert only non-section AdocBlock cases into ASGBlock (for list item block bodies)
extension AdocBlock {
    func toASGBlockForList() -> ASGBlock? {
        switch self {
        case .section:
            return nil // sections are not part of ASGNonSectionBlockBody
        case .paragraph(let p):
            return p.toASG()
        case .listing(let l):
            return l.toASG()
        case .list(let l):
            return l.toASG()
        case .dlist(let dl):
            return dl.toASG()
        case .discreteHeading(let h):
            return h.toASG()
        case .sidebar(let s):
            return s.toASG()
        case .example(let e):
            return e.toASG()
        case .quote(let q):
            return q.toASG()
        case .open(let o):
            return o.toASG()
        case .admonition(let a):
            return a.toASG()
        case .verse(let v):
            return v.toASG()
        case .literalBlock(let l):
            return l.toASG()
        case .table(let t):
            return t.toASG()
        case .math(let m):
            return m.toASG()
        case .blockMacro(let m):
            return m.toASG()
        }
    }
}

public extension Array where Element == AdocInline {
    func toASGInlines() -> ASGInlines {
        map { $0.toASG() }
    }
}

public extension AdocInline {
    func toASG() -> ASGInline {
        switch self {
        case .text(let s, let span):
            return .literal(.init(
                name: .text,
                value: s,
                location: span?.toASG()
            ))

        case .strong(let xs, let span):
            return .span(.init(
                variant: .strong,
                form: .constrained,
                inlines: xs.toASGInlines(),
                location: span?.toASG()
            ))

        case .emphasis(let xs, let span):
            return .span(.init(
                variant: .emphasis,
                form: .constrained,
                inlines: xs.toASGInlines(),
                location: span?.toASG()
            ))

        case .mono(let xs, let span):
            return .span(.init(
                variant: .code,
                form: .constrained,
                inlines: xs.toASGInlines(),
                location: span?.toASG()
            ))

        case .mark(let xs, let span):
            return .span(.init(
                variant: .mark,
                form: .constrained,
                inlines: xs.toASGInlines(),
                location: span?.toASG()
            ))

        case .link(let target, let text, let span):
            return .ref(.init(
                variant: .link,
                target: target,
                inlines: text.toASGInlines(),
                location: span?.toASG()
            ))

        case .xref(let target, let text, let span):
            return .ref(.init(
                variant: .xref,
                target: target.raw,
                inlines: text.toASGInlines(),
                location: span?.toASG()
            ))

        case .passthrough(let raw, let span):
            return .literal(.init(
                name: .raw,
                value: raw,
                location: span?.toASG()
            ))

        // NEW: superscript / subscript – collapse to plain text literal for ASG
        case .superscript(let xs, let span):
            return .literal(.init(
                name: .text,
                value: xs.plainText(),
                location: span?.toASG()
            ))

        case .subscript(let xs, let span):
            return .literal(.init(
                name: .text,
                value: xs.plainText(),
                location: span?.toASG()
            ))

        case .math(_, let body, _, let span):
            return .literal(.init(
                name: .raw,
                value: body,
                location: span?.toASG()
            ))

        // NEW: inline macro – encode as raw "name:[body]" or "name:target[body]"
        case .inlineMacro(let name, let target, let body, let span):
            let rendered: String
            if let t = target {
                rendered = "\(name):\(t)[\(body)]"
            } else {
                rendered = "\(name):[\(body)]"
            }
            return .literal(.init(
                name: .raw,
                value: rendered,
                location: span?.toASG()
            ))

        case .footnote(let content, let ref, _, let span):
            // Fallback: render contents as raw text inside footnote macro syntax for ASG
            let body = content.toASGInlines().map { inline -> String in
                if case .literal(let l) = inline { return l.value }
                return ""
            }.joined()
            let rendered: String
            if let r = ref {
                rendered = "footnote:\(r)[\(body)]"
            } else {
                rendered = "footnote:[\(body)]"
            }
            return .literal(.init(
                name: .raw,
                value: rendered,
                location: span?.toASG()
            ))

        case .indexTerm(let terms, let visible, let span):
            let joined = terms.joined(separator: ", ")
            let val = visible ? "((\(joined)))" : "(((\(joined))))"
            return .literal(.init(
                name: .raw,
                value: val,
                location: span?.toASG()
            ))
        }
    }
}

extension AdocSidebar {
    func toASG() -> ASGBlock {
        let inner = blocks.toASGNonSectionBody_viaItems()
        let pb = ASGParentBlock(
            type: ASGConstBlockType.block,
            name: ASGParentBlockName.sidebar,
            form: "delimited",
            delimiter: delimiter ?? "****",
            blocks: inner,
            variant: nil,
            id: id,
            title: title?.inlines.toASGInlines(),
            reftext: reftext?.inlines.toASGInlines(),
            metadata: meta.toASG(),
            location: span.toASG(),
        )
        return .parent(pb)
    }
}

extension AdocExample {
    func toASG() -> ASGBlock {
        let inner = blocks.toASGNonSectionBody_viaItems()

        let pb = ASGParentBlock(
            type: ASGConstBlockType.block,
            name: ASGParentBlockName.example,
            form: "delimited",
            delimiter: delimiter ?? "====",
            blocks: inner,
            variant: nil,
            id: id,
            title: title?.inlines.toASGInlines(),
            reftext: reftext?.inlines.toASGInlines(),
            metadata: meta.toASG(),
            location: span.toASG(),
        )

        return .parent(pb)
    }
}

extension AdocQuote {
    func toASG() -> ASGBlock {
        let inner = blocks.toASGNonSectionBody_viaItems()

        let pb = ASGParentBlock(
            type: ASGConstBlockType.block,
            name: ASGParentBlockName.quote,
            form: "delimited",
            delimiter: delimiter ?? "____",
            blocks: inner,
            variant: nil,
            id: id,
            title: title?.inlines.toASGInlines(),
            reftext: reftext?.inlines.toASGInlines(),
            metadata: meta.toASG(),
            location: span.toASG(),
        )

        return .parent(pb)
    }
}

extension AdocOpen {
    func toASG() -> ASGBlock {
        let inner = blocks.toASGNonSectionBody_viaItems()

        let pb = ASGParentBlock(
            type: ASGConstBlockType.block,
            name: ASGParentBlockName.open,
            form: "delimited",
            delimiter: delimiter ?? "--",
            blocks: inner,
            variant: nil,
            id: id,
            title: title?.inlines.toASGInlines(),
            reftext: reftext?.inlines.toASGInlines(),
            metadata: meta.toASG(),
            location: span.toASG(),
        )

        return .parent(pb)
    }
}

extension AdocAdmonition {
    func toASG() -> ASGBlock {
        let inner = blocks.toASGNonSectionBody_viaItems()

        let pb = ASGParentBlock(
            type: ASGConstBlockType.block,
            name: ASGParentBlockName.admonition,
            form: "delimited",
            delimiter: delimiter ?? "====",
            blocks: inner,
            variant: mapAdmonitionKind(kind),
            id: id,
            title: title?.inlines.toASGInlines(),
            reftext: reftext?.inlines.toASGInlines(),
            metadata: meta.toASG(),
            location: span.toASG(),
        )

        return .parent(pb)
    }
}

extension AdocVerse {
    func toASG() -> ASGBlock {
        // ASG models verse as a leaf; if you later support nested blocks for verse,
        // render them into text before conversion.
        let inlines = text?.inlines.toASGInlines() ?? []
        let form: ASGLeafBlockForm? = (delimiter != nil) ? .delimited : .paragraph

        let leaf = ASGLeafBlock(
            name: .verse,
            form: form,
            delimiter: delimiter,
            inlines: nil,
            id: id,
            title: inlines,
            reftext: reftext?.inlines.toASGInlines(),
            metadata: meta.toASG(),
            location: span.toASG(),
        )
        return .leaf(leaf)
    }
}

extension AdocLiteralBlock {
    func toASG() -> ASGBlock {
        let inlines = text.inlines.toASGInlines()

        let form: ASGLeafBlockForm? = (delimiter != nil) ? .delimited : .indented
        let leaf = ASGLeafBlock(
            name: .literal,
            form: form,
            delimiter: delimiter,
            inlines: nil,
            id: id,
            title: inlines,
            reftext: reftext?.inlines.toASGInlines(),
            metadata: meta.toASG(),
            location: span.toASG(),
        )
        return .leaf(leaf)
    }
}

extension AdocMathBlock {
    func toASG() -> ASGBlock {
        let literal = ASGInlineLiteral(name: .raw, value: body, location: span?.toASG())
        let form: ASGLeafBlockForm = display ? .delimited : .paragraph
        return .leaf(.init(
            name: .stem,
            form: form,
            delimiter: nil,
            inlines: [.literal(literal)],
            id: id,
            title: title?.inlines.toASGInlines(),
            reftext: reftext?.inlines.toASGInlines(),
            metadata: meta.toASG(),
            location: span?.toASG()
        ))
    }
}

extension AdocTable {
    func toASG() -> ASGBlock {
        return .leaf(ASGLeafBlock(
            name: .pass,
            form: .paragraph,
            delimiter: "|===",
            inlines: nil,
            id: id,
            title: title?.inlines.toASGInlines(),
            reftext: reftext?.inlines.toASGInlines(),
            metadata: meta.toASG(),
            location: span.toASG(),
        ))

    }
}

extension AdocDList {
    func toASG() -> ASGBlock {
        let itemsASG: [ASGDListItem] = self.items.map { $0.toASG() }
        let dlist = ASGDList(
            type: .block,
            id: self.id,
            title: self.title?.inlines.toASGInlines(),
            reftext: self.reftext?.inlines.toASGInlines(),
            metadata: self.meta.toASG(),
            location: self.span.toASG(),
            name: "dlist",
            marker: "::",   // Asciidoc marker; you could later pass through exactly
            items: itemsASG
        )

        return .dlist(dlist)
    }
}

private extension AdocDListItem {
    func toASG() -> ASGDListItem {
        // Convert terms → [ASGInlines]
        return ASGDListItem(
            type: .block,
            id: self.id,
            title: self.title?.inlines.toASGInlines(),
            reftext: self.reftext?.inlines.toASGInlines(),
            metadata: self.meta.toASG(),
            location: self.span.toASG(),
            name: "dlistItem",
            marker: "::",
            principal: self.principal?.inlines.toASGInlines(),
            blocks: self.blocks.toASGNonSectionBody_viaItems(),
            terms: [self.term.inlines.toASGInlines()]
        )
    }
}
