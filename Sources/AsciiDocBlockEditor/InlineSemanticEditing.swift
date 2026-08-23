//
// Copyright (c) 2025 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

import AsciiDocCore
import Foundation

extension AdocText {
    var visibleText: String {
        inlines.map(\.visibleText).joined()
    }

    /// Replaces a range in the semantic (marker-free) text.
    ///
    /// Edits contained by one text leaf retain all surrounding inline nodes.
    /// A cross-node edit currently falls back to reparsing the resulting plain
    /// semantic text; callers can use the return value to detect that the
    /// original inline structure could not be retained exactly.
    @discardableResult
    mutating func replaceVisibleText(in range: NSRange, with replacement: String) -> Bool {
        let visible = visibleText
        guard NSMaxRange(range) <= (visible as NSString).length else { return false }

        var cursor = 0
        if let updated = Self.replacing(in: inlines, range: range, replacement: replacement, cursor: &cursor) {
            inlines = updated
            plain = updated.map(\.asciiDocSource).joined()
            span = nil
            return true
        }

        let flattened = (visible as NSString).replacingCharacters(in: range, with: replacement)
        self = AdocText(plain: flattened, span: nil)
        return false
    }

    mutating func wrapVisibleText(in range: NSRange, with markup: AsciiDocInlineMarkup) -> Bool {
        guard range.length > 0, NSMaxRange(range) <= (visibleText as NSString).length else { return false }
        var cursor = 0
        guard let updated = Self.wrapping(in: inlines, range: range, markup: markup, cursor: &cursor) else {
            return false
        }
        inlines = updated
        plain = updated.map(\.asciiDocSource).joined()
        span = nil
        return true
    }

    fileprivate static func replacing(
        in nodes: [AdocInline],
        range: NSRange,
        replacement: String,
        cursor: inout Int
    ) -> [AdocInline]? {
        var result = nodes
        for index in result.indices {
            let nodeStart = cursor
            let nodeLength = (result[index].visibleText as NSString).length
            let nodeEnd = nodeStart + nodeLength
            let contains = range.location >= nodeStart && NSMaxRange(range) <= nodeEnd

            if contains, let replaced = result[index].replacingVisibleText(
                in: NSRange(location: range.location - nodeStart, length: range.length),
                with: replacement
            ) {
                result[index] = replaced
                return result
            }
            cursor = nodeEnd
        }
        return nil
    }

    fileprivate static func wrapping(
        in nodes: [AdocInline],
        range: NSRange,
        markup: AsciiDocInlineMarkup,
        cursor: inout Int
    ) -> [AdocInline]? {
        var result = nodes
        for index in result.indices {
            let nodeStart = cursor
            let nodeLength = (result[index].visibleText as NSString).length
            let nodeEnd = nodeStart + nodeLength
            if range.location >= nodeStart, NSMaxRange(range) <= nodeEnd,
               let replacement = result[index].wrappingVisibleText(
                   in: NSRange(location: range.location - nodeStart, length: range.length),
                   with: markup
               ) {
                result.replaceSubrange(index...index, with: replacement)
                return result
            }
            cursor = nodeEnd
        }
        return nil
    }
}

extension AdocInline {
    var visibleText: String {
        switch self {
        case .text(let value, _), .passthrough(let value, _): return value
        case .strong(let children, _), .emphasis(let children, _), .mono(let children, _),
             .mark(let children, _), .superscript(let children, _), .subscript(let children, _):
            return children.map(\.visibleText).joined()
        case .link(_, let children, _), .xref(_, let children, _):
            return children.map(\.visibleText).joined()
        case .math(_, let body, _, _): return body
        case .inlineMacro(let name, let target, let body, _):
            if !body.isEmpty { return body }
            return target ?? name
        case .footnote(let content, _, _, _): return content.map(\.visibleText).joined()
        case .indexTerm(let terms, let visible, _): return visible ? (terms.first ?? "") : ""
        }
    }

    var asciiDocSource: String {
        switch self {
        case .text(let value, _): return value
        case .strong(let children, _): return "*\(children.map(\.asciiDocSource).joined())*"
        case .emphasis(let children, _): return "_\(children.map(\.asciiDocSource).joined())_"
        case .mono(let children, _): return "`\(children.map(\.asciiDocSource).joined())`"
        case .mark(let children, _): return "#\(children.map(\.asciiDocSource).joined())#"
        case .link(let target, let children, _): return "link:\(target)[\(children.map(\.asciiDocSource).joined())]"
        case .xref(let target, let children, _): return "xref:\(target.raw)[\(children.map(\.asciiDocSource).joined())]"
        case .passthrough(let value, _): return "+\(value)+"
        case .superscript(let children, _): return "^\(children.map(\.asciiDocSource).joined())^"
        case .subscript(let children, _): return "~\(children.map(\.asciiDocSource).joined())~"
        case .math(let kind, let body, _, _):
            return "\(kind == .asciimath ? "asciimath" : "stem"):[\(body)]"
        case .inlineMacro(let name, let target, let body, _):
            return "\(name):\(target ?? "")[\(body)]"
        case .footnote(let content, let ref, _, _):
            return "footnote:\(ref ?? "")[\(content.map(\.asciiDocSource).joined())]"
        case .indexTerm(let terms, let visible, _):
            let body = terms.joined(separator: ",")
            return visible ? "((\(body)))" : "(((\(body))))"
        }
    }

    fileprivate func replacingVisibleText(in range: NSRange, with replacement: String) -> AdocInline? {
        switch self {
        case .text(let value, _):
            guard NSMaxRange(range) <= (value as NSString).length else { return nil }
            return .text((value as NSString).replacingCharacters(in: range, with: replacement), span: nil)

        case .strong(let children, _):
            return replacingChildren(children, range: range, replacement: replacement) { .strong($0, span: nil) }
        case .emphasis(let children, _):
            return replacingChildren(children, range: range, replacement: replacement) { .emphasis($0, span: nil) }
        case .mono(let children, _):
            return replacingChildren(children, range: range, replacement: replacement) { .mono($0, span: nil) }
        case .mark(let children, _):
            return replacingChildren(children, range: range, replacement: replacement) { .mark($0, span: nil) }
        case .superscript(let children, _):
            return replacingChildren(children, range: range, replacement: replacement) { .superscript($0, span: nil) }
        case .subscript(let children, _):
            return replacingChildren(children, range: range, replacement: replacement) { .subscript($0, span: nil) }
        case .link(let target, let children, _):
            return replacingChildren(children, range: range, replacement: replacement) {
                .link(target: target, text: $0, span: nil)
            }
        case .xref(let target, let children, _):
            return replacingChildren(children, range: range, replacement: replacement) {
                .xref(target: target, text: $0, span: nil)
            }
        case .footnote(let children, let ref, let id, _):
            return replacingChildren(children, range: range, replacement: replacement) {
                .footnote(content: $0, ref: ref, id: id, span: nil)
            }
        default:
            return nil
        }
    }

    fileprivate func wrappingVisibleText(
        in range: NSRange,
        with markup: AsciiDocInlineMarkup
    ) -> [AdocInline]? {
        switch self {
        case .text(let value, _):
            let nsValue = value as NSString
            guard range.length > 0, NSMaxRange(range) <= nsValue.length else { return nil }
            var result: [AdocInline] = []
            if range.location > 0 {
                result.append(.text(nsValue.substring(to: range.location), span: nil))
            }
            result.append(markup.wrapping([.text(nsValue.substring(with: range), span: nil)]))
            if NSMaxRange(range) < nsValue.length {
                result.append(.text(nsValue.substring(from: NSMaxRange(range)), span: nil))
            }
            return result

        case .strong(let children, _):
            return wrappingChildren(children, range: range, markup: markup) { [.strong($0, span: nil)] }
        case .emphasis(let children, _):
            return wrappingChildren(children, range: range, markup: markup) { [.emphasis($0, span: nil)] }
        case .mono(let children, _):
            return wrappingChildren(children, range: range, markup: markup) { [.mono($0, span: nil)] }
        case .mark(let children, _):
            return wrappingChildren(children, range: range, markup: markup) { [.mark($0, span: nil)] }
        case .superscript(let children, _):
            return wrappingChildren(children, range: range, markup: markup) { [.superscript($0, span: nil)] }
        case .subscript(let children, _):
            return wrappingChildren(children, range: range, markup: markup) { [.subscript($0, span: nil)] }
        case .link(let target, let children, _):
            return wrappingChildren(children, range: range, markup: markup) {
                [.link(target: target, text: $0, span: nil)]
            }
        case .xref(let target, let children, _):
            return wrappingChildren(children, range: range, markup: markup) {
                [.xref(target: target, text: $0, span: nil)]
            }
        default:
            return nil
        }
    }

    private func replacingChildren(
        _ children: [AdocInline],
        range: NSRange,
        replacement: String,
        wrap: ([AdocInline]) -> AdocInline
    ) -> AdocInline? {
        var cursor = 0
        guard let updated = AdocText.replacing(in: children, range: range, replacement: replacement, cursor: &cursor) else {
            return nil
        }
        return wrap(updated)
    }

    private func wrappingChildren(
        _ children: [AdocInline],
        range: NSRange,
        markup: AsciiDocInlineMarkup,
        wrap: ([AdocInline]) -> [AdocInline]
    ) -> [AdocInline]? {
        var cursor = 0
        guard let updated = AdocText.wrapping(in: children, range: range, markup: markup, cursor: &cursor) else {
            return nil
        }
        return wrap(updated)
    }
}
