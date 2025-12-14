//
// Copyright (c) 2025 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

import Foundation
/// Identity of a list marker, independent of the actual text content.
enum ListMarkerKey: Equatable {
    case unordered(symbol: Character, run: Int)   // "*", "**", "-", etc
    case orderedDot(depth: Int)                   // ".", "..", "..."
    case orderedExplicit(style: OrderedStyle)     // "1.", "A.", etc
    case callout
}

enum OrderedStyle: Equatable {
    case arabic        // 1., 2.
    case lowerAlpha    // a., b.
    case upperAlpha    // A., B.
    case lowerRoman    // i., ii.
    case upperRoman    // I., II.
}
private func markerKey(forListItem tok: Token) -> ListMarkerKey {
    // 'tok.string' is the substring for the entire line, as in your scanner
    let s = tok.string
    var start = s.startIndex
    while start < s.endIndex, s[start] == " " || s[start] == "\t" {
        start = s.index(after: start)
    }
    guard start < s.endIndex else { return .unordered(symbol: "-", run: 1) }

    let first = s[start]

    // Callout markers: "<1>"
    if first == "<" {
        var i = s.index(after: start)
        let digitsStart = i
        while i < s.endIndex, s[i].isNumber {
            i = s.index(after: i)
        }
        if digitsStart < i, i < s.endIndex, s[i] == ">" {
            return .callout
        }
    }

    // Unordered
    if first == "*" || first == "-" {
        var run = 1
        var i = s.index(after: start)
        while i < s.endIndex, s[i] == first {
            run += 1
            i = s.index(after: i)
        }
        // Scanner guarantees run == 1 for '-'; may be >1 for '*'
        return .unordered(symbol: first, run: run)
    }

    // Ordered dot lists ". foo", ".. foo", ...
    if s[start] == "." {
        var i = start
        var depth = 0
        while i < s.endIndex, s[i] == "." {
            depth += 1
            i = s.index(after: i)
        }
        return .orderedDot(depth: depth)
    }

    // Explicit enumerator: "1. ", "A. ", etc on the first level
    if let dotIndex = s[start...].firstIndex(of: ".") {
        let head = s[start..<dotIndex]
        if head.allSatisfy({ $0.isNumber }) {
            return .orderedExplicit(style: .arabic)
        }
        if head.allSatisfy({ $0.isLowercase }) {
            return .orderedExplicit(style: .lowerAlpha)
        }
        if head.allSatisfy({ $0.isUppercase }) {
            return .orderedExplicit(style: .upperAlpha)
        }
        // roman detection omitted for brevity; you can add it
    }

    // Fallback – should not normally happen if scanner is correct.
    return .unordered(symbol: "-", run: 1)
}


package struct PendingMeta {
    var id: String?
    var roles: [String] = []
    var options: Set<String> = []
    var attributes: [String: String] = [:]
    var title: AdocText? = nil

    var isEmpty: Bool {
        id == nil &&
        roles.isEmpty &&
        options.isEmpty &&
        attributes.isEmpty &&
        title == nil
    }
}

// Helper: convert an AdocRange (inclusive columns, exclusive offsets) into ISM AdocLocation
package func rangeToLocation(_ r: AdocRange?) -> AdocLocation? {
    guard let r else { return nil }
    let s = AdocLocationBoundary(line: r.start.line, col: r.start.column, file: r.start.fileStack?.frames)
    let e = AdocLocationBoundary(line: r.end.line,   col: r.end.column,   file: r.end.fileStack?.frames)
    return AdocLocation(start: s, end: e)
}

// Helper: multi-line span from the *start* token to the *end* token
func spanFromTokens(start sTok: Token, end eTok: Token, it: TokenIter) -> AdocRange {
    let startSpan = it.spanForLine(sTok)
    let endSpan   = it.spanForLine(eTok)
    return AdocRange(start: startSpan.start, end: endSpan.end)
}
private let _admonitionSet: Set<String> = ["NOTE","TIP","WARNING","CAUTION","IMPORTANT"]

@inline(__always)
private func normalizeAdmonition(_ s: String) -> String? {
    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    return _admonitionSet.contains(t) ? t : nil
}

/// Parse kind from a BAL line like "[NOTE]" or "[  warning , role]".
private func admonitionKindFromBAL(_ bal: String) -> String? {
    // Quick scan for first token inside [ ... ] up to comma or end
    // Examples: "[NOTE]", "[ warning ]", "[tip,role]", "[caution#id.role]"
    guard bal.first == "[", bal.last == "]" else { return nil }
    let inner = bal.dropFirst().dropLast()
    let head = inner.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: true).first ?? ""
    // Head could still contain id/role shortcuts, split on # or .
    let token = head.split(whereSeparator: { $0 == "#" || $0 == "." }).first.map(String.init) ?? ""
    return normalizeAdmonition(token)
}

/// Parse kind + text from a shorthand paragraph like "NOTE: body"
private func admonitionFromParagraphLine(_ s: String) -> (kind: String, text: String)? {
    // Find first colon
    guard let idx = s.firstIndex(of: ":") else { return nil }
    let head = String(s[..<idx])
    guard let kind = normalizeAdmonition(head) else { return nil }
    let after = s[s.index(after: idx)...] // skip ':'
    // Strip a single leading space after colon if present
    let text = after.first == " " ? String(after.dropFirst()) : String(after)
    return (kind, text)
}

@inline(__always)
private func parseBlockTitleLine(_ s: String, env: AttrEnv) -> String? {
    guard s.first == "." else { return nil }
    let rest = s.dropFirst()
    // Accept ".Title" or ". Title"
    let trimmed = rest.first == " " ? rest.dropFirst() : rest[...]
    let out = String(trimmed)
    return out.isEmpty ? nil : out
}

/// Consume a block title line if present (e.g. ".Block title").
/// Returns an `AdocText` with the title and span, or `nil` if no title line.
private func consumeBlockTitleIfPresent(it: inout TokenIter) -> AdocText? {
    guard let tok = it.peek() else { return nil }

    // We only accept block titles on "text-like" lines.
    guard case .text(let contentRange) = tok.kind else { return nil }

    let line = tok.string
    let full = line[contentRange]  // the line's "content" area as the scanner defined it

    // Trim leading spaces/tabs
    var i = full.startIndex
    let end = full.endIndex
    while i < end, full[i] == " " || full[i] == "\t" {
        i = full.index(after: i)
    }
    guard i < end, full[i] == "." else {
        // First non-space char is not '.', so not a block title.
        return nil
    }

    // Move past the '.'
    i = full.index(after: i)
    // Require at least one non-space after the dot
    guard i < end, full[i] != " " && full[i] != "\t" else {
        // ". Foo" is allowed; ".   " alone is not a title.
        return nil
    }

    // Title start is here; now find title end by trimming trailing spaces.
    let titleStartInFull = i
    var j = end
    while j > titleStartInFull {
        let before = full.index(before: j)
        if full[before] == " " || full[before] == "\t" {
            j = before
        } else {
            break
        }
    }
    let titleRangeInFull = titleStartInFull..<j
    guard !titleRangeInFull.isEmpty else { return nil }

    // Map title range back into tok.string’s index space.
    let offsetToTitleStart = full.distance(from: full.startIndex, to: titleStartInFull)
    let offsetToTitleEnd   = full.distance(from: full.startIndex, to: j)

    let absStart = line.index(contentRange.lowerBound, offsetBy: offsetToTitleStart)
    let absEnd   = line.index(contentRange.lowerBound, offsetBy: offsetToTitleEnd)
    let titleRangeInTok = absStart..<absEnd

    // Build AdocText with proper span
    let titleText = String(line[titleRangeInTok])
    let span = it.spanForContent(range: titleRangeInTok, token: tok)

    // Consume the title token
    it.consume()

    return AdocText(plain: titleText, span: span)
}

@inline(__always)
func applyPendingTitle(_ title: inout AdocText?, pending: inout AdocText?) {
    if title == nil, let t = pending { title = t; pending = nil }
}
public struct AdocParser: Sendable {

    public init() {}

    public func parse(
        text: String,
        attributes initialAttributes: [String: String?] = [:],
        lockedAttributeNames: Set<String> = [],
        includeHeaderDerivedAttributes: Bool = true,
        preprocessorOptions: Preprocessor.Options = .init()
    ) -> AdocDocument {
        let preprocessor = Preprocessor(options: preprocessorOptions)
        let preprocessed = preprocessor.process(
            text: text,
            attributes: initialAttributes,
            lockedAttributes: lockedAttributeNames
        )

        let toks = LineScanner().scan(preprocessed.source)
        var it = TokenIter(tokens: toks, text: preprocessed.source.text)
        var header: AdocHeader? = nil
        var docAttrs: [String: String?] = preprocessed.attributes
        var env = AttrEnv(initial: docAttrs)

        // Header detection (keep your existing logic)
        detectHeader(
            into: &header,
            attrs: &docAttrs,
            it: &it,
            env: &env,
            lockedAttributes: lockedAttributeNames,
            includeDerivedAttributes: includeHeaderDerivedAttributes
        )

        // Body blocks via parseBlocks
        let bodyBlocks = parseBlocks(it: &it, env: env) { _ in false }

        // Document span can still be computed from first/last token
        let docSpan: AdocRange? = {
            guard let first = toks.first, let last = toks.last else { return nil }
            return AdocRange(start: first.range.start, end: last.range.end)
        }()

        return AdocDocument(attributes: docAttrs, header: header, blocks: bodyBlocks, span: docSpan)
    }


}




/// Parse a single block meta "chunk" (already split on commas).
/// Handles:
///   #id
///   .role1.role2
///   %opt1%opt2
///   role=rolename
///   role="role1 role2"
///   alt=Sunset
private func parseBlockMetaChunk(_ part: String, into pending: inout PendingMeta, env: AttrEnv) {
    var i = part.startIndex
    let end = part.endIndex

    // Helper to read until one of the separators or end
    func readName(from start: inout String.Index,
                  stopOn: Set<Character>) -> String {
        let s = start
        var j = start
        while j < end, !stopOn.contains(part[j]) {
            j = part.index(after: j)
        }
        start = j
        return String(part[s..<j])
    }

    // First pass: handle #id/.roles/%options sequences like "#rules.prominent%incremental"
    while i < end {
        let c = part[i]

        if c == "#" {
            // ID: from after '#' to next '.' or '%' or end
            i = part.index(after: i)
            var name = readName(from: &i, stopOn: [".", "%"])
            name = name.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty, pending.id == nil {
                pending.id = name
            }
            continue
        }

        if c == "." {
            // Role: from after '.' to next '.' or '%' or end
            i = part.index(after: i)
            var name = readName(from: &i, stopOn: [".", "%"])
            name = name.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty {
                pending.roles.append(name)
            }
            continue
        }

        if c == "%" {
            // Option: from after '%' to next '.' or '%' or end
            i = part.index(after: i)
            var name = readName(from: &i, stopOn: [".", "%"])
            name = name.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty {
                pending.options.insert(name)
            }
            continue
        }

        // Anything else → treat the *rest* of the chunk as an attribute expression.
        let attrExpr = part[i...].trimmingCharacters(in: .whitespaces)
        if attrExpr.isEmpty { break }

        if let eq = attrExpr.firstIndex(of: "=") {
            let name = attrExpr[..<eq].trimmingCharacters(in: .whitespaces)
            let valueStart = attrExpr.index(after: eq)
            var value = attrExpr[valueStart...].trimmingCharacters(in: .whitespaces)

            // Strip simple quotes "..." or '...'
            if value.count >= 2, let first = value.first, (first == "\"" || first == "'"), value.last == first {
                value = String(value.dropFirst().dropLast())
            }

            if !name.isEmpty {
                pending.attributes[String(name)] = String(value)
            }
        } else {
            // Boolean attribute: present without explicit value
            pending.attributes[String(attrExpr)] = ""
        }
        break // attribute consumes rest of chunk
    }
}
