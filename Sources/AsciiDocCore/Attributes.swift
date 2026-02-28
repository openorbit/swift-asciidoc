//
// Copyright (c) 2025 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

import Foundation

public enum XADAttributeValue: Sendable, Equatable {
    case dictionary([String: XADAttributeValue])
    case array([XADAttributeValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    static func parse(from raw: String, xadOptions: XADOptions) -> XADAttributeValue? {
        guard xadOptions.enabled else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first, first == "{" || first == "[" else { return nil }
        guard let data = trimmed.data(using: .utf8) else { return nil }

        var options: JSONSerialization.ReadingOptions = []
        if #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *) {
            options.insert(.json5Allowed)
        }

        do {
            let obj = try JSONSerialization.jsonObject(with: data, options: options)
            return XADAttributeValue.fromJSON(obj)
        } catch {
            return nil
        }
    }

    static func fromJSON(_ value: Any) -> XADAttributeValue? {
        switch value {
        case let dict as [String: Any]:
            var mapped: [String: XADAttributeValue] = [:]
            for (key, val) in dict {
                if let converted = fromJSON(val) {
                    mapped[key] = converted
                } else {
                    return nil
                }
            }
            return .dictionary(mapped)
        case let array as [Any]:
            var mapped: [XADAttributeValue] = []
            mapped.reserveCapacity(array.count)
            for val in array {
                guard let converted = fromJSON(val) else { return nil }
                mapped.append(converted)
            }
            return .array(mapped)
        case let str as String:
            return .string(str)
        case let num as NSNumber:
            if CFGetTypeID(num) == CFBooleanGetTypeID() {
                return .bool(num.boolValue)
            }
            return .number(num.doubleValue)
        case _ as NSNull:
            return .null
        default:
            return nil
        }
    }

    public func toJSONCompatible() -> Any {
        switch self {
        case .dictionary(let dict):
            var out: [String: Any] = [:]
            for (key, value) in dict {
                out[key] = value.toJSONCompatible()
            }
            return out
        case .array(let array):
            return array.map { $0.toJSONCompatible() }
        case .string(let value):
            return value
        case .number(let value):
            return value
        case .bool(let value):
            return value
        case .null:
            return NSNull()
        }
    }
}

package struct AttrEnv {
    // name → optional value (nil means unset)
    private(set) var values: [String: String?]
    private(set) var typedValues: [String: XADAttributeValue]
    private var scopeStack: [ScopeSnapshot]
    let xadOptions: XADOptions

    private struct ScopeSnapshot {
        let values: [String: String?]
        let typedValues: [String: XADAttributeValue]
    }

    package init(
        initial: [String: String?] = [:],
        typedAttributes: [String: XADAttributeValue] = [:],
        xadOptions: XADOptions = .init(enabled: false)
    ) {
        self.values = initial
        self.typedValues = typedAttributes
        self.scopeStack = []
        self.xadOptions = xadOptions
    }

    mutating func set(_ name: String, to value: String?) {
        values[name] = value
    }

    mutating func pushScope() {
        let snapshot = ScopeSnapshot(values: values, typedValues: typedValues)
        scopeStack.append(snapshot)
    }

    @discardableResult
    mutating func popScope() -> Bool {
        guard let snapshot = scopeStack.popLast() else { return false }
        values = snapshot.values
        typedValues = snapshot.typedValues
        return true
    }

    mutating func applyAttributeSet(name: String, value: String?) {
        values[name] = value
        guard xadOptions.enabled else { return }
        let rawValue = value ?? ""
        if isXADPathName(name) {
            let normalizedScalar = stripSurroundingQuotes(rawValue)
            let typed = XADAttributeValue.parse(from: normalizedScalar, xadOptions: xadOptions) ?? .string(normalizedScalar)
            setTypedPath(name, value: typed)
            return
        }
        if let value, let typed = XADAttributeValue.parse(from: value, xadOptions: xadOptions) {
            typedValues[name] = typed
        } else {
            typedValues.removeValue(forKey: name)
        }
    }

    mutating func applyAttributeUnset(name: String) {
        values[name] = nil
        guard xadOptions.enabled else { return }
        if isXADPathName(name) {
            setTypedPath(name, value: .null)
        } else {
            typedValues.removeValue(forKey: name)
        }
    }

    func value(for name: String) -> String? {
        values[name] ?? nil
    }

    func resolveAttribute(_ name: String, join: String? = nil) -> String? {
        if xadOptions.enabled, isXADPathName(name), let typed = resolveTypedPath(name) {
            return stringify(typed, join: join)
        }
        if let raw = value(for: name) {
            return raw
        }
        if xadOptions.enabled, let typed = typedValues[name] {
            return stringify(typed, join: join)
        }
        return nil
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
                    if let v = resolveAttribute(name) {
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


private enum XADPathSegment {
    case key(String)
    case index(Int)
}

private func isXADPathName(_ name: String) -> Bool {
    name.contains(".") || name.contains("[")
}

private func parseXADPathSegments(_ path: String, env: AttrEnv) -> [XADPathSegment]? {
    var segments: [XADPathSegment] = []
    var token = ""
    var index = path.startIndex

    func appendToken() -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        token.removeAll(keepingCapacity: true)
        guard !trimmed.isEmpty else { return true }
        if trimmed.allSatisfy({ $0.isNumber }), let value = Int(trimmed) {
            segments.append(.index(value))
        } else {
            segments.append(.key(trimmed))
        }
        return true
    }

    while index < path.endIndex {
        let ch = path[index]
        if ch == "." {
            _ = appendToken()
            index = path.index(after: index)
            continue
        }
        if ch == "[" {
            _ = appendToken()
            let close = path[index...].firstIndex(of: "]")
            guard let close else { return nil }
            let content = path[path.index(after: index)..<close]
            let resolved = resolveBracketIndex(content, env: env)
            guard let resolved, let intValue = Int(resolved) else { return nil }
            segments.append(.index(intValue))
            index = path.index(after: close)
            continue
        }
        token.append(ch)
        index = path.index(after: index)
    }
    _ = appendToken()
    return segments.isEmpty ? nil : segments
}

private func resolveBracketIndex(_ content: Substring, env: AttrEnv) -> String? {
    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if trimmed.hasPrefix("{") && trimmed.hasSuffix("}") {
        let start = trimmed.index(after: trimmed.startIndex)
        let end = trimmed.index(before: trimmed.endIndex)
        let name = String(trimmed[start..<end])
        return env.resolveAttribute(name)
    }
    if let resolved = env.resolveAttribute(String(trimmed)) {
        return resolved
    }
    return String(trimmed)
}

private func stripSurroundingQuotes(_ value: String) -> String {
    guard value.count >= 2 else { return value }
    let first = value.first
    let last = value.last
    guard let first, let last, first == last, (first == "\"" || first == "'") else {
        return value
    }
    return String(value.dropFirst().dropLast())
}

private extension AttrEnv {
    func resolveTypedPath(_ path: String) -> XADAttributeValue? {
        guard let segments = parseXADPathSegments(path, env: self), !segments.isEmpty else {
            return nil
        }
        guard case .key(let root) = segments[0], let rootValue = typedValues[root] else {
            return nil
        }
        var current: XADAttributeValue? = rootValue
        for segment in segments.dropFirst() {
            guard let value = current else { return nil }
            switch (value, segment) {
            case (.dictionary(let dict), .key(let key)):
                current = dict[key]
            case (.array(let array), .index(let idx)):
                guard idx >= 0, idx < array.count else { return nil }
                current = array[idx]
            default:
                return nil
            }
        }
        return current
    }

    func stringify(_ value: XADAttributeValue, join: String?) -> String {
        switch value {
        case .string(let s):
            return s
        case .number(let n):
            return String(n)
        case .bool(let b):
            return b ? "true" : "false"
        case .null:
            return "null"
        case .array(let array):
            if let join {
                return array.map { stringify($0, join: nil) }.joined(separator: join)
            }
            return jsonString(from: value)
        case .dictionary:
            return jsonString(from: value)
        }
    }

    func jsonString(from value: XADAttributeValue) -> String {
        let obj = value.toJSONCompatible()
        guard JSONSerialization.isValidJSONObject(obj),
              let data = try? JSONSerialization.data(withJSONObject: obj, options: []) else {
            return ""
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    mutating func setTypedPath(_ path: String, value: XADAttributeValue) {
        guard let segments = parseXADPathSegments(path, env: self), !segments.isEmpty else { return }
        guard case .key(let root) = segments[0] else { return }
        let updated = setTypedValue(
            current: typedValues[root],
            segments: segments.dropFirst(),
            value: value
        )
        typedValues[root] = updated
    }

    func setTypedValue(
        current: XADAttributeValue?,
        segments: ArraySlice<XADPathSegment>,
        value: XADAttributeValue
    ) -> XADAttributeValue {
        guard let first = segments.first else { return value }
        let rest = segments.dropFirst()

        switch first {
        case .key(let key):
            var dict: [String: XADAttributeValue]
            if case .dictionary(let existing)? = current {
                dict = existing
            } else {
                dict = [:]
            }
            let updated = setTypedValue(current: dict[key], segments: rest, value: value)
            dict[key] = updated
            return .dictionary(dict)
        case .index(let idx):
            var array: [XADAttributeValue]
            if case .array(let existing)? = current {
                array = existing
            } else {
                array = []
            }
            if idx >= array.count {
                array.append(contentsOf: repeatElement(.null, count: idx - array.count + 1))
            }
            let updated = setTypedValue(current: array[idx], segments: rest, value: value)
            array[idx] = updated
            return .array(array)
        }
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
