//
// Copyright (c) 2025 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

import Foundation
import AsciiDocCore

/// Bridges the internal semantic model (ISM) to Swift's `AttributedString`
/// so UI clients can edit a document as rich text and persist that back
/// to `AdocDocument`.
public enum AttributedExport {
    /// Produce a Foundation `AttributedString` from the textual parts of the
    /// supplied document. Paragraphs are separated by blank lines. Non-textual
    /// blocks fall back to their rendered AsciiDoc representation.
    public static func make(from doc: AdocDocument) -> AttributedString {
        var builder = AttributedString()
        var needsSeparator = false

        if let title = doc.header?.title, !title.plain.isEmpty {
            append(text: title, into: &builder, needsSeparator: &needsSeparator)
        }

        for block in doc.blocks {
            append(block: block, into: &builder, needsSeparator: &needsSeparator)
        }

        return builder
    }

    /// Convert a single `AdocText` payload into an `AttributedString`.
    public static func make(from text: AdocText) -> AttributedString {
        buildAttributed(from: text.inlines)
    }

    private static func append(block: AdocBlock,
                               into out: inout AttributedString,
                               needsSeparator: inout Bool) {
        switch block {
        case .paragraph(let p):
            append(text: p.text, into: &out, needsSeparator: &needsSeparator)

        case .section(let section):
            append(text: section.title, into: &out, needsSeparator: &needsSeparator)
            for child in section.blocks {
                append(block: child, into: &out, needsSeparator: &needsSeparator)
            }

        default:
            var rendered = String()
            block.renderAsAsciiDoc(into: &rendered)
            let trimmed = rendered.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            if needsSeparator {
                out.append(AttributedString("\n\n"))
            }
            out.append(AttributedString(trimmed))
            needsSeparator = true
        }
    }

    private static func append(text: AdocText,
                               into out: inout AttributedString,
                               needsSeparator: inout Bool) {
        let snippet = buildAttributed(from: text.inlines)
        guard !snippet.characters.isEmpty else { return }
        if needsSeparator {
            out.append(AttributedString("\n\n"))
        }
        out += snippet
        needsSeparator = true
    }

    private static func buildAttributed(from inlines: [AdocInline]) -> AttributedString {
        var builder = AttributedString()
        for inline in inlines {
            append(inline: inline, traits: [], link: nil, xref: nil, into: &builder)
        }
        return builder
    }

    private static func append(inline: AdocInline,
                               traits: InlineTraits,
                               link: String?,
                               xref: String?,
                               into out: inout AttributedString) {
        switch inline {
        case .text(let string, _):
            append(text: string, traits: traits, link: link, xref: xref, into: &out)

        case .strong(let children, _):
            children.forEach { append(inline: $0, traits: traits.union(.strong), link: link, xref: xref, into: &out) }

        case .emphasis(let children, _):
            children.forEach { append(inline: $0, traits: traits.union(.emphasis), link: link, xref: xref, into: &out) }

        case .mono(let children, _):
            children.forEach { append(inline: $0, traits: traits.union(.mono), link: link, xref: xref, into: &out) }

        case .mark(let children, _):
            children.forEach { append(inline: $0, traits: traits.union(.mark), link: link, xref: xref, into: &out) }

        case .superscript(let children, _):
            children.forEach { append(inline: $0, traits: traits.union(.superscript), link: link, xref: xref, into: &out) }

        case .subscript(let children, _):
            children.forEach { append(inline: $0, traits: traits.union(.subscript), link: link, xref: xref, into: &out) }

        case .link(let target, let children, _):
            children.forEach { append(inline: $0, traits: traits, link: target, xref: nil, into: &out) }

        case .xref(let target, let children, _):
            children.forEach { append(inline: $0, traits: traits, link: nil, xref: target.raw, into: &out) }

        case .passthrough(let raw, _):
            append(text: raw, traits: traits, link: link, xref: xref, into: &out)

        case .math(_, let body, _, _):
            append(text: body, traits: traits.union(.mono), link: link, xref: xref, into: &out)

        case .inlineMacro(_, let target, let body, _):
            // TODO: If we want to render the macro name/target, adjust here. 
            // For now, mirroring existing behavior of just appending body.
            // Avoid unused variable warning for target
            _ = target
            append(text: body, traits: traits, link: link, xref: xref, into: &out)

        case .footnote(let content, _, _, _):
            // Footnotes in AttributedString?
            // Usually we just render their content or a marker.
            // For now, render content.
            content.forEach { append(inline: $0, traits: traits, link: link, xref: xref, into: &out) }
            
        case .indexTerm(let terms, let visible, _):
            if visible, let t = terms.first {
                out.append(AttributedString(t))
            }
        }
    }

    private static func append(text: String,
                               traits: InlineTraits,
                               link: String?,
                               xref: String?,
                               into out: inout AttributedString) {
        guard !text.isEmpty else { return }
        var container = AttributeContainer()
        if !traits.isEmpty {
            container[AsciiDocStyleAttribute.self] = traits
        }
        if let link {
            container[AsciiDocLinkAttribute.self] = link
            if let url = URL(string: link) {
                container.link = url
            }
        }
        if let xref {
            container[AsciiDocXrefAttribute.self] = xref
        }
        #if !os(Linux)
        if let intent = inlinePresentationIntent(for: traits) {
            container.inlinePresentationIntent = intent
        }
        #endif
        out += AttributedString(text, attributes: container)
    }

    #if !os(Linux)
    private static func inlinePresentationIntent(for traits: InlineTraits) -> InlinePresentationIntent? {
        var intent = InlinePresentationIntent()
        if traits.contains(.strong) {
            intent.insert(.stronglyEmphasized)
        }
        if traits.contains(.emphasis) {
            intent.insert(.emphasized)
        }
        if traits.contains(.mono) {
            intent.insert(.code)
        }
        return intent.isEmpty ? nil : intent
    }
    #endif

}

public enum AttributedImport {
    /// Convert a user-editable `AttributedString` into an `AdocDocument`
    /// consisting of paragraphs separated by blank lines.
    public static func makeDocument(from attributed: AttributedString) -> AdocDocument {
        let ranges = paragraphRanges(in: attributed)
        guard !ranges.isEmpty else { return AdocDocument(attributes: [:], header: nil, blocks: []) }

        var blocks: [AdocBlock] = []
        blocks.reserveCapacity(ranges.count)

        for range in ranges {
            let slice = attributed[range]
            let trimmed = trimWhitespace(slice)
            guard !trimmed.characters.isEmpty else { continue }
            let text = makeText(from: AttributedString(trimmed))
            blocks.append(.paragraph(AdocParagraph(text: text)))
        }

        return AdocDocument(attributes: [:], header: nil, blocks: blocks, span: nil)
    }

    /// Convert a rich `AttributedString` span into `AdocText` inlines.
    public static func makeText(from attributed: AttributedString) -> AdocText {
        let inlines = makeInlines(from: attributed)
        return AdocText(inlines: inlines)
    }

    private static func makeInlines(from attributed: AttributedString) -> [AdocInline] {
        var result: [AdocInline] = []
        for run in attributed.runs {
            let fragment = attributed[run.range]
            guard !fragment.characters.isEmpty else { continue }
            let text = String(fragment.characters)
            guard !text.isEmpty else { continue }
            let traits = InlineTraits(run: run)
            let link: String?
            if let stored = run[AsciiDocLinkAttribute.self] {
                link = stored
            } else if let url = run[AttributeScopes.FoundationAttributes.LinkAttribute.self] {
                link = url.absoluteString
            } else {
                link = nil
            }
            let xref = run[AsciiDocXrefAttribute.self]
            result.append(buildInline(from: text, traits: traits, link: link, xref: xref))
        }
        return result
    }

    private static func buildInline(from text: String,
                                    traits: InlineTraits,
                                    link: String?,
                                    xref: String?) -> AdocInline {
        var node: AdocInline = .text(text, span: nil)

        if traits.contains(.mono) { node = .mono([node], span: nil) }
        if traits.contains(.mark) { node = .mark([node], span: nil) }
        if traits.contains(.superscript) { node = .superscript([node], span: nil) }
        if traits.contains(.subscript) { node = .subscript([node], span: nil) }
        if traits.contains(.emphasis) { node = .emphasis([node], span: nil) }
        if traits.contains(.strong) { node = .strong([node], span: nil) }

        if let target = link {
            return .link(target: target, text: [node], span: nil)
        }
        if let target = xref {
            return .xref(target: AdocXrefTarget(raw: target), text: [node], span: nil)
        }
        return node
    }

    private static func paragraphRanges(in attributed: AttributedString) -> [Range<AttributedString.Index>] {
        let plain = Array(String(attributed.characters))
        var ranges: [Range<AttributedString.Index>] = []
        var startOffset = 0
        var idx = 0

        while idx < plain.count {
            if plain[idx] == "\n", idx + 1 < plain.count, plain[idx + 1] == "\n" {
                if startOffset < idx {
                    let start = attributed.index(attributed.startIndex, offsetByCharacters: startOffset)
                    let end = attributed.index(attributed.startIndex, offsetByCharacters: idx)
                    let slice = attributed[start..<end]
                    if !slice.characters.allSatisfy(\.isWhitespaceOrNewline) {
                        ranges.append(start..<end)
                    }
                }
                while idx < plain.count, plain[idx] == "\n" {
                    idx += 1
                }
                startOffset = idx
                continue
            }
            idx += 1
        }

        if startOffset < plain.count {
            let start = attributed.index(attributed.startIndex, offsetByCharacters: startOffset)
            let end = attributed.index(attributed.startIndex, offsetByCharacters: plain.count)
            ranges.append(start..<end)
        }

        return ranges
    }

    private static func trimWhitespace(_ attributed: AttributedSubstring) -> AttributedSubstring {
        let scalars = Array(String(attributed.characters))
        guard !scalars.isEmpty else { return attributed }

        var leading = 0
        var trailing = 0

        while leading < scalars.count, scalars[leading].isWhitespaceOrNewline {
            leading += 1
        }
        while trailing < scalars.count - leading, scalars[scalars.count - 1 - trailing].isWhitespaceOrNewline {
            trailing += 1
        }

        guard leading < scalars.count else {
            return attributed[attributed.startIndex..<attributed.startIndex]
        }

        let lower = attributed.index(attributed.startIndex, offsetByCharacters: leading)
        let upper = attributed.index(attributed.endIndex, offsetByCharacters: -trailing)
        return attributed[lower..<upper]
    }
}

struct InlineTraits: OptionSet, Sendable, Hashable {
    let rawValue: UInt8

    init(rawValue: UInt8) { self.rawValue = rawValue }

    init(run: AttributedString.Runs.Run) {
        if let stored = run[AsciiDocStyleAttribute.self] {
            self = stored
            return
        }
        var traits: InlineTraits = []
        #if !os(Linux)
        if let intent = run.inlinePresentationIntent {
            if intent.contains(.stronglyEmphasized) {
                traits.insert(.strong)
            }
            if intent.contains(.emphasized) {
                traits.insert(.emphasis)
            }
            if intent.contains(.code) {
                traits.insert(.mono)
            }
        }
        #endif
        self = traits
    }

    static let strong      = InlineTraits(rawValue: 1 << 0)
    static let emphasis    = InlineTraits(rawValue: 1 << 1)
    static let mono        = InlineTraits(rawValue: 1 << 2)
    static let mark        = InlineTraits(rawValue: 1 << 3)
    static let superscript = InlineTraits(rawValue: 1 << 4)
    static let `subscript` = InlineTraits(rawValue: 1 << 5)
}

struct AsciiDocStyleAttribute: AttributedStringKey {
    typealias Value = InlineTraits
    static let name = "org.asciidoc.swift.style"
}

struct AsciiDocLinkAttribute: AttributedStringKey {
    typealias Value = String
    static let name = "org.asciidoc.swift.link"
}

struct AsciiDocXrefAttribute: AttributedStringKey {
    typealias Value = String
    static let name = "org.asciidoc.swift.xref"
}

private extension Character {
    var isWhitespaceOrNewline: Bool {
        unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
    }
}
