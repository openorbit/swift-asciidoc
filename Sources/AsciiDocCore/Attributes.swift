//
// Copyright (c) 2025 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

package struct AttrEnv {
    // name → optional value (nil means unset)
    private(set) var values: [String: String?]

    package init(initial: [String: String?] = [:]) {
        self.values = initial
    }

    mutating func set(_ name: String, to value: String?) {
        values[name] = value
    }

    func value(for name: String) -> String? {
        values[name] ?? nil
    }

    /// Expand {attr} in a string using the *current* environment.
    /// No re-parsing of markup is done; this is purely textual.
    package func expand(_ s: String) -> String {
        var result = ""
        var i = s.startIndex
        let end = s.endIndex

        while i < end {
            let c = s[i]
            if c == "{" {
                let braceStart = i
                var j = s.index(after: i)
                let nameStart = j
                while j < end, s[j] != "}" {
                    j = s.index(after: j)
                }
                if j < end, s[j] == "}" {
                    let name = String(s[nameStart..<j])
                    if let v = value(for: name) {
                        result += v
                    } else {
                        // Unknown attribute → keep literal {name}
                        result += String(s[braceStart...j])
                    }
                    i = s.index(after: j)
                    continue
                }
            }
            result.append(c)
            i = s.index(after: i)
        }

        return result
    }
}


package extension AdocInline {
    func applyingAttributes(using env: AttrEnv) -> AdocInline {
        switch self {
        case .text(let s, let span):
            let v = env.expand(s)
            return .text(v, span: span)

        case .strong(let inner, let span):
            let mapped = inner.map { $0.applyingAttributes(using: env) }
            return .strong(mapped, span: span)

        case .emphasis(let inner, let span):
            let mapped = inner.map { $0.applyingAttributes(using: env) }
            return .emphasis(mapped, span: span)

        case .mono(let inner, let span):
            let mapped = inner.map { $0.applyingAttributes(using: env) }
            return .mono(mapped, span: span)

        case .mark(let inner, let span):
            let mapped = inner.map { $0.applyingAttributes(using: env) }
            return .mark(mapped, span: span)
        case .superscript(let xs, let span):
            return .superscript(xs.map { $0.applyingAttributes(using: env) }, span: span)

        case .subscript(let xs, let span):
            return .subscript(xs.map { $0.applyingAttributes(using: env) }, span: span)

        case .link(let target, let text, let span):
            let newTarget = env.expand(target)
            let mapped = text.map { $0.applyingAttributes(using: env) }
            return .link(target: newTarget, text: mapped, span: span)

        case .xref(let target, let text, let span):
            let newTarget = target.rewriting(raw: env.expand(target.raw))
            let mapped = text.map { $0.applyingAttributes(using: env) }
            return .xref(target: newTarget, text: mapped, span: span)

        case .passthrough(let raw, let span):
            let v = env.expand(raw)
            return .passthrough(v, span: span)

        case .math(let kind, let body, let display, let span):
            return .math(kind: kind, body: env.expand(body), display: display, span: span)

        // Generic inline macro: attributes in the macro body
        case .inlineMacro(let name, let target, let body, let span):
            let expandedTarget = target.map { env.expand($0) }
            return .inlineMacro(
                name: name,
                target: expandedTarget,
                body: env.expand(body),
                span: span
            )

        case .indexTerm(let terms, let visible, let span):
            // Expand attributes inside index terms? Yes.
            let newTerms = terms.map { env.expand($0) }
            return .indexTerm(terms: newTerms, visible: visible, span: span)

        case .footnote(let content, let ref, let id, let span):
            // Expand attributes inside footnote content
            let mapped = content.map { $0.applyingAttributes(using: env) }
            // Expand ref? Yes
            let expandedRef = ref.map { env.expand($0) }
            return .footnote(content: mapped, ref: expandedRef, id: id, span: span)
        }
    }
}

package extension Array where Element == AdocInline {
    func applyingAttributes(using env: AttrEnv) -> [AdocInline] {
        self.map { $0.applyingAttributes(using: env) }
    }
}

package extension AdocText {
    func applyingAttributes(using env: AttrEnv) -> AdocText {
        let newInlines = inlines.applyingAttributes(using: env)
        // This initializer recomputes `plain` from inlines.
        return AdocText(inlines: newInlines, span: span)
    }
}

package extension AdocParagraph {
    func applyingAttributes(using env: AttrEnv) -> AdocParagraph {
        var copy = self
        copy.text = copy.text.applyingAttributes(using: env)
        if let t = copy.title { copy.title = t.applyingAttributes(using: env) }
        if let r = copy.reftext { copy.reftext = r.applyingAttributes(using: env) }
        // meta: for now we leave meta.attributes as parsed; structural attrs handled in parser.
        return copy
    }
}

package extension AdocListing {
    func applyingAttributes(using env: AttrEnv) -> AdocListing {
        var copy = self
        copy.text = copy.text.applyingAttributes(using: env)
        if let t = copy.title { copy.title = t.applyingAttributes(using: env) }
        if let r = copy.reftext { copy.reftext = r.applyingAttributes(using: env) }
        return copy
    }
}

package extension AdocListItem {
    func applyingAttributes(using env: AttrEnv) -> AdocListItem {
        var copy = self
        copy.principal = copy.principal.applyingAttributes(using: env)
        if let t = copy.title { copy.title = t.applyingAttributes(using: env) }
        if let r = copy.reftext { copy.reftext = r.applyingAttributes(using: env) }
        copy.blocks = copy.blocks.map { $0.applyingAttributes(using: env) }
        return copy
    }
}

package extension AdocList {
    func applyingAttributes(using env: AttrEnv) -> AdocList {
        var copy = self
        if let t = copy.title { copy.title = t.applyingAttributes(using: env) }
        if let r = copy.reftext { copy.reftext = r.applyingAttributes(using: env) }
        copy.items = copy.items.map { $0.applyingAttributes(using: env) }
        return copy
    }
}

package extension AdocSection {
    func applyingAttributes(using env: AttrEnv) -> AdocSection {
        var copy = self
        copy.title = copy.title.applyingAttributes(using: env)
        if let r = copy.reftext { copy.reftext = r.applyingAttributes(using: env) }
        copy.blocks = copy.blocks.map { $0.applyingAttributes(using: env) }
        return copy
    }
}

package extension AdocSidebar {
    func applyingAttributes(using env: AttrEnv) -> AdocSidebar {
        var copy = self
        if let t = copy.title { copy.title = t.applyingAttributes(using: env) }
        if let r = copy.reftext { copy.reftext = r.applyingAttributes(using: env) }
        copy.blocks = copy.blocks.map { $0.applyingAttributes(using: env) }
        return copy
    }
}

// Extend AdocBlock so we can map whole trees:
package extension AdocBlock {
    func applyingAttributes(using env: AttrEnv) -> AdocBlock {
        switch self {
        case .paragraph(let p):       return .paragraph(p.applyingAttributes(using: env))
        case .listing(let l):         return .listing(l.applyingAttributes(using: env))
        case .list(let lst):          return .list(lst.applyingAttributes(using: env))
        case .dlist(let dl):
            var copy = dl
            if let t = copy.title { copy.title = t.applyingAttributes(using: env) }
            if let r = copy.reftext { copy.reftext = r.applyingAttributes(using: env) }
            copy.items = copy.items.map { $0.applyingAttributes(using: env) }
            return .dlist(copy)
        case .section(let s):         return .section(s.applyingAttributes(using: env))
        case .sidebar(let sb):        return .sidebar(sb.applyingAttributes(using: env))
        case .discreteHeading(let h):
            var hh = h
            hh.title = hh.title.applyingAttributes(using: env)
            if let r = hh.reftext { hh.reftext = r.applyingAttributes(using: env) }
            return .discreteHeading(hh)
        case .example(let ex):
            var e = ex
            if let t = e.title { e.title = t.applyingAttributes(using: env) }
            if let r = e.reftext { e.reftext = r.applyingAttributes(using: env) }
            e.blocks = e.blocks.map { $0.applyingAttributes(using: env) }
            return .example(e)
        case .quote(let q):
            var qq = q
            if let t = qq.title { qq.title = t.applyingAttributes(using: env) }
            if let r = qq.reftext { qq.reftext = r.applyingAttributes(using: env) }
            qq.blocks = qq.blocks.map { $0.applyingAttributes(using: env) }
            return .quote(qq)
        case .open(let o):
            var oo = o
            if let t = oo.title { oo.title = t.applyingAttributes(using: env) }
            if let r = oo.reftext { oo.reftext = r.applyingAttributes(using: env) }
            oo.blocks = oo.blocks.map { $0.applyingAttributes(using: env) }
            return .open(oo)
        case .admonition(let a):
            var aa = a
            if let t = aa.title { aa.title = t.applyingAttributes(using: env) }
            if let r = aa.reftext { aa.reftext = r.applyingAttributes(using: env) }
            aa.blocks = aa.blocks.map { $0.applyingAttributes(using: env) }
            return .admonition(aa)
        case .verse(let v):
            var vv = v
            if let t = vv.text { vv.text = t.applyingAttributes(using: env) }
            if let t = vv.title { vv.title = t.applyingAttributes(using: env) }
            if let r = vv.reftext { vv.reftext = r.applyingAttributes(using: env) }
            vv.blocks = vv.blocks.map { $0.applyingAttributes(using: env) }
            return .verse(vv)
        case .literalBlock(let lb):
            var ll = lb
            ll.text = ll.text.applyingAttributes(using: env)
            if let t = ll.title { ll.title = t.applyingAttributes(using: env) }
            if let r = ll.reftext { ll.reftext = r.applyingAttributes(using: env) }
            return .literalBlock(ll)
        case .table(let tb):
            var tl = tb
            if let t = tl.title { tl.title = t.applyingAttributes(using: env) }
            if let r = tl.reftext { tl.reftext = r.applyingAttributes(using: env) }
            return .table(tl)
        case .math(let mb):
            var m = mb
            m.body = env.expand(m.body)
            if let t = m.title { m.title = t.applyingAttributes(using: env) }
            if let r = m.reftext { m.reftext = r.applyingAttributes(using: env) }
            return .math(m)
        case .blockMacro(let m):
            return .blockMacro(m)
        }
    }
}

package extension AdocBlockMeta {
    func applyingAttributes(using env: AttrEnv) -> AdocBlockMeta {
        var copy = self

        // Named attributes
        if !copy.attributes.isEmpty {
            var newAttrs: [String: String] = [:]
            for (k, v) in copy.attributes {
                newAttrs[k] = env.expand(v)
            }
            copy.attributes = newAttrs
        }

        // Roles & options are usually simple identifiers,
        // but expanding them doesn’t hurt.
        copy.roles = copy.roles.map { env.expand($0) }
        copy.options = Set(copy.options.map { env.expand($0) })

        return copy
    }
}

package extension PendingMeta {
    func attributesApplyingAttributes(using env: AttrEnv) -> [String: String]? {
        if attributes.isEmpty { return nil }
        var out: [String: String] = [:]
        for (k, v) in attributes {
            out[k] = env.expand(v)
        }
        return out
    }
}

private extension AdocDListItem {
    func applyingAttributes(using env: AttrEnv) -> AdocDListItem {
        var copy = self
        copy.term = copy.term.applyingAttributes(using: env)
        if let p = copy.principal { copy.principal = p.applyingAttributes(using: env) }
        if let t = copy.title { copy.title = t.applyingAttributes(using: env) }
        if let r = copy.reftext { copy.reftext = r.applyingAttributes(using: env) }
        copy.blocks = copy.blocks.map { $0.applyingAttributes(using: env) }
        return copy
    }
}
