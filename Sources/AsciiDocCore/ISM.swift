//
// Copyright (c) 2025 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

import Foundation

public final class AdocFileStack: @unchecked Sendable, Equatable {
    public let frames: [String]

    public init(frames: [String]) {
        self.frames = frames
    }

    public static func == (lhs: AdocFileStack, rhs: AdocFileStack) -> Bool {
        lhs.frames == rhs.frames
    }
}

public struct AdocLocationBoundary: Sendable, Equatable {
    public var line: Int
    public var col: Int
    public var file: [String]? // optional file stack/source provenance
}

public struct AdocLocation: Sendable, Equatable {
    public var start: AdocLocationBoundary
    public var end: AdocLocationBoundary
}

public struct AdocPos: Sendable, Equatable {
    public let offset: String.Index   // Location in source
    public let line: Int     // 1-based
    public let column: Int   // 1-based
    public let fileStack: AdocFileStack?   // Include stack provenance (outermost → innermost)

    public init(
        offset: String.Index,
        line: Int,
        column: Int,
        fileStack: AdocFileStack? = nil
    ) {
        self.offset = offset
        self.line = line
        self.column = column
        self.fileStack = fileStack
    }
}

public struct AdocRange: Sendable, Equatable {
    public let start: AdocPos
    public let end: AdocPos

    public init(start: AdocPos, end: AdocPos) {
        self.start = start
        self.end = end
    }
}

public enum AdocInline: Sendable, Equatable {
    case text(String, span: AdocRange?)           // plain text leaf
    case strong([AdocInline], span: AdocRange?)   // ** ** or __ __
    case emphasis([AdocInline], span: AdocRange?) // * * or _ _
    case mono([AdocInline], span: AdocRange?)     // `code` (constrained/unconstrained left for later)
    case mark([AdocInline], span: AdocRange?)     // mark
    case link(target: String, text: [AdocInline], span: AdocRange?)
    case xref(target: AdocXrefTarget, text: [AdocInline], span: AdocRange?)
    case passthrough(String, span: AdocRange?)    // raw passthrough
    case superscript([AdocInline], span: AdocRange?) // ^x^
    case `subscript`([AdocInline], span: AdocRange?)   // ~x~
    case math(kind: AdocMathKind, body: String, display: Bool, span: AdocRange?)
    case inlineMacro(name: String, target: String?, body: String, span: AdocRange?)
    case footnote(content: [AdocInline], ref: String?, id: Int?, span: AdocRange?)
    case indexTerm(terms: [String], visible: Bool, span: AdocRange?)
}

public extension Array where Element == AdocInline {
    func plainText() -> String {
        var out = String()
        out.reserveCapacity(self.count * 8)

        func walk(_ n: AdocInline) {
            switch n {
            case .text(let s, _):
                out.append(s)

            case .strong(let xs, _),
                 .emphasis(let xs, _),
                 .mono(let xs, _),
                 .mark(let xs, _),
                 .superscript(let xs, _),
                 .`subscript`(let xs, _):
                xs.forEach(walk)

            case .link(_, let text, _),
                 .xref(_, let text, _):
                text.forEach(walk)

            case .passthrough(let s, _),
                 .math(_, let s, _, _):
                out.append(s)

            case .inlineMacro(_, let t, let b, _):
                // Approximation: if target exists, assume we want to render it?
                // Actually, for plain text, usually we just want the body or fallback.
                out.append(b)
                if let t = t { out.append(t) } // very naive plain text logic

            case .footnote(let content, _, _, _):
                content.forEach(walk)

            case .indexTerm(let terms, let visible, _):
                if visible, let first = terms.first {
                   out.append(first)
                }
            }
        }

        for n in self { walk(n) }
        return out
    }
}

public struct AdocBlockMeta: Sendable, Equatable {
    public var attributes: [String: String] = [:]
    public var options: Set<String> = []
    public var roles: [String] = []

    /// Block title from `.Title` line, if any.
    public var title: AdocText? = nil

    /// Block reference text from `[[id,reftext]]` or similar.
    public var reftext: AdocText? = nil

    /// Block ID from `[ #id ]` or `[[id]]`.
    public var id: String?

    /// Span of the *metadata lines* only (anchor, blockMeta, title).
    public var span: AdocRange?

    public init(attributes: [String: String] = [:],
        options: Set<String> = [],
        roles: [String] = [],
        title: AdocText? = nil,
        reftext: AdocText? = nil,
        id: String? = nil,
        span: AdocRange? = nil) {
        self.attributes = attributes
        self.options = options
        self.roles = roles
        self.title = title
        self.reftext = reftext
        self.id = id
        self.span = span

    }
}

/// Holds both parsed inlines and a precomputed plain text view.
public struct AdocText: Sendable, Equatable {
    public var inlines: [AdocInline]
    public var plain: String
    public var span: AdocRange?

    public init(inlines: [AdocInline], span: AdocRange? = nil) {
        self.inlines = inlines
        self.plain = inlines.plainText()
        self.span = span
    }

    public init(plain: String, span: AdocRange? = nil) {
        self.inlines = parseInlines(plain, baseSpan: span)
        self.plain = plain
        self.span = span
    }
}

public indirect enum AdocBlock: Sendable, Equatable {
    case section(AdocSection)
    case paragraph(AdocParagraph)
    case listing(AdocListing)
    case list(AdocList)
    case dlist(AdocDList)
    case discreteHeading(AdocDiscreteHeading)
    case sidebar(AdocSidebar)
    case example(AdocExample)
    case quote(AdocQuote)
    case open(AdocOpen)
    case admonition(AdocAdmonition)
    case verse(AdocVerse)
    case literalBlock(AdocLiteralBlock)
    case table(AdocTable)
    case math(AdocMathBlock)
    case blockMacro(AdocBlockMacro)
}

public struct AdocSection: Sendable, Equatable {
    public var level: Int
    public var title: AdocText
    public var blocks: [AdocBlock]
    public var id: String?
    public var reftext: AdocText?
    public var meta: AdocBlockMeta = .init()
    public var span: AdocRange?
}

public struct AdocParagraph: Sendable, Equatable {
    public var text: AdocText // paragraph body
    public var id: String?
    public var title: AdocText?
    public var reftext: AdocText?
    public var meta: AdocBlockMeta = .init()
    public var span: AdocRange?

    public init(
        text: AdocText,
        id: String? = nil,
        title: AdocText? = nil,
        reftext: AdocText? = nil,
        meta: AdocBlockMeta = .init(),
        span: AdocRange? = nil
    ) {
        self.text = text
        self.id = id
        self.title = title
        self.reftext = reftext
        self.meta = meta
        self.span = span
    }
}

public struct AdocListing: Sendable, Equatable {
    public var text: AdocText // verbatim; inlines usually unparsed by substitutions
    public var delimiter: String? // captured fence like "----"
    public var id: String?
    public var title: AdocText?
    public var reftext: AdocText?
    public var meta: AdocBlockMeta = .init()
    public var span: AdocRange?
}

public enum AdocListKind: Sendable, Equatable {
    case unordered(marker: String)
    case ordered(marker: String)
    case callout
}

public struct AdocListItem: Sendable, Equatable {
    public var marker: String // "*", "-", "1.", etc.
    public var principal: AdocText // the item’s first line / principal text
    public var blocks: [AdocBlock] = [] // follow-on blocks via continuations
    public var id: String?
    public var title: AdocText?
    public var reftext: AdocText?
    public var meta: AdocBlockMeta = .init()
    public var span: AdocRange?
}

public struct AdocList: Sendable, Equatable {
    public var kind: AdocListKind
    public var items: [AdocListItem]
    public var id: String?
    public var title: AdocText?
    public var reftext: AdocText?
    public var meta: AdocBlockMeta = .init()
    public var span: AdocRange?
}

public struct AdocDListItem: Sendable, Equatable {
    /// Terms on the left: `term::` or `term1:: term2::`
    public var term: AdocText

    /// Optional principal description on the same line (after the last `::`)
    public var principal: AdocText?

    /// Nested blocks following the item (via continuations)
    public var blocks: [AdocBlock] = []

    public var id: String?
    public var title: AdocText?
    public var reftext: AdocText?
    public var meta: AdocBlockMeta = .init()
    public var span: AdocRange?
}

public struct AdocDList: Sendable, Equatable {
    public var marker: String              // "::", ";;", ":::", "::::".
    public var items: [AdocDListItem]
    public var id: String?
    public var title: AdocText?
    public var reftext: AdocText?
    public var meta: AdocBlockMeta = .init()
    public var span: AdocRange?
}

public struct AdocDiscreteHeading: Sendable, Equatable {
    public var level: Int
    public var title: AdocText
    public var id: String?
    public var reftext: AdocText?
    public var meta: AdocBlockMeta = .init()
    public var span: AdocRange?
}

public struct AdocSidebar: Sendable, Equatable {
    public var blocks: [AdocBlock]
    public var delimiter: String?
    public var id: String?
    public var title: AdocText?
    public var reftext: AdocText?
    public var meta: AdocBlockMeta = .init()
    public var span: AdocRange?
}

public struct AdocExample: Sendable, Equatable {
    public var blocks: [AdocBlock]
    public var delimiter: String?
    public var id: String?
    public var title: AdocText?
    public var reftext: AdocText?
    public var meta: AdocBlockMeta = .init()
    public var span: AdocRange?
}

public struct AdocQuote: Sendable, Equatable {
    public var blocks: [AdocBlock]
    public var delimiter: String?
    public var id: String?
    public var title: AdocText?
    public var reftext: AdocText?
    public var attribution: AdocText?    // "-- Author")
    public var citetitle: AdocText?      // Optional work title line
    public var meta: AdocBlockMeta = .init()
    public var span: AdocRange?
}

public struct AdocOpen: Sendable, Equatable {
    public var blocks: [AdocBlock]
    public var delimiter: String?
    public var id: String?
    public var title: AdocText?
    public var reftext: AdocText?
    public var meta: AdocBlockMeta = .init()
    public var span: AdocRange?
}

public struct AdocAdmonition: Sendable, Equatable {
    public var kind: String? // note, tip, warning, caution, important
    public var blocks: [AdocBlock]
    public var delimiter: String?
    public var id: String?
    public var title: AdocText?
    public var reftext: AdocText?
    public var meta: AdocBlockMeta = .init()
    public var span: AdocRange?
}

public struct AdocVerse: Sendable, Equatable {
    public var text: AdocText?           // verse can be text-only
    public var blocks: [AdocBlock] = []  // or nested blocks if delimited
    public var delimiter: String?
    public var id: String?
    public var title: AdocText?
    public var reftext: AdocText?
    public var attribution: AdocText?    // "-- Author")
    public var citetitle: AdocText?      // Optional work title line
    public var meta: AdocBlockMeta = .init()
    public var span: AdocRange?
}

public struct AdocLiteralBlock: Sendable, Equatable {
    public var text: AdocText
    public var delimiter: String?
    public var id: String?
    public var title: AdocText?
    public var reftext: AdocText?
    public var meta: AdocBlockMeta = .init()
    public var span: AdocRange?
}

public struct AdocAuthor: Sendable, Equatable {
    public var fullname: String?
    public var initials: String?
    public var firstname: String?
    public var middlename: String?
    public var lastname: String?
    public var address: String?
}


public struct AdocHeader: Sendable, Equatable {
    public var title: AdocText?
    public var authors: [AdocAuthor]? // ISM-native author model
    public var location: AdocLocation? // ISM-native location

}



public struct AdocDocument: Sendable, Equatable {
    public var attributes: [String: String?] = [:]
    public var header: AdocHeader? = nil
    public var blocks: [AdocBlock] = []
    public var span: AdocRange?

    public init(
        attributes: [String: String?] = [:],
        header: AdocHeader? = nil,
        blocks: [AdocBlock] = [],
        span: AdocRange? = nil
    ) {
        self.attributes = attributes
        self.header = header
        self.blocks = blocks
        self.span = span
    }
}

public enum AdocMathKind: Sendable, Equatable {
    case latex
    case asciimath
}

public extension AdocMathKind {
    init?(macroName: String) {
        switch macroName.lowercased() {
        case "stem", "latexmath":
            self = .latex
        case "asciimath":
            self = .asciimath
        default:
            return nil
        }
    }
}

public struct AdocMathBlock: Sendable, Equatable {
    public var kind: AdocMathKind
    public var body: String
    public var display: Bool
    public var id: String?
    public var title: AdocText?
    public var reftext: AdocText?
    public var meta: AdocBlockMeta = .init()
    public var span: AdocRange?
}

public protocol AdocRenderable {
    /// Append AsciiDoc to the provided buffer.
    func renderAsAsciiDoc(into out: inout String)
}

public extension AdocRenderable {
    /// Convenience: return a String directly (so callers can just do `x.renderAsAsciiDoc()`).
    func renderAsAsciiDoc() -> String {
        var s = String()
        renderAsAsciiDoc(into: &s)
        return s
    }
}

extension AdocDocument: AdocRenderable {
    public func renderAsAsciiDoc(into out: inout String) {
        if let t = header?.title?.plain, !t.isEmpty {
            out += "= \(t)\n\n"
        }
        for b in blocks { b.renderAsAsciiDoc(into: &out) }
    }
}

extension AdocBlock: AdocRenderable {
    public func renderAsAsciiDoc(into out: inout String) {
        switch self {
        case .section(let s): s.renderAsAsciiDoc(into: &out)
        case .paragraph(let p): p.renderAsAsciiDoc(into: &out)
        case .listing(let l): l.renderAsAsciiDoc(into: &out)
        case .list(let l): l.renderAsAsciiDoc(into: &out)
        case .dlist(let d): d.renderAsAsciiDoc(into: &out)
        case .discreteHeading(let h): h.renderAsAsciiDoc(into: &out)

        case .sidebar(let s): s.renderAsAsciiDoc(into: &out)
        case .example(let e): e.renderAsAsciiDoc(into: &out)
        case .quote(let q): q.renderAsAsciiDoc(into: &out)
        case .open(let o): o.renderAsAsciiDoc(into: &out)
        case .admonition(let a): a.renderAsAsciiDoc(into: &out)
        case .verse(let v): v.renderAsAsciiDoc(into: &out)
        case .literalBlock(let l): l.renderAsAsciiDoc(into: &out)
        case .table(let t): t.renderAsAsciiDoc(into: &out)
        case .math(let m):
            let macro = (m.kind == .asciimath) ? "asciimath" : "stem"
            if m.display {
                out += "\(macro)::[\(m.body)]\n\n"
            } else {
                out += "\(macro):[\(m.body)]\n\n"
            }
        case .blockMacro(let m): m.renderAsAsciiDoc(into: &out)
        }
    }
}

extension AdocSection: AdocRenderable {
    public func renderAsAsciiDoc(into out: inout String) {
        out += String(repeating: "=", count: max(1, level)) + " " + title.plain + "\n\n"
        for b in blocks { b.renderAsAsciiDoc(into: &out) }
    }
}

extension AdocParagraph: AdocRenderable {
    public func renderAsAsciiDoc(into out: inout String) {
        if let t = title?.plain, !t.isEmpty { out += ".\(t)\n" }
        out += text.plain + "\n\n"
    }
}

extension AdocListing: AdocRenderable {
    public func renderAsAsciiDoc(into out: inout String) {
        let fence = delimiter ?? "----"
        if let t = title?.plain, !t.isEmpty { out += ".\(t)\n" }
        out += fence + "\n" + text.plain + "\n" + fence + "\n\n"
    }
}

extension AdocList: AdocRenderable {
    public func renderAsAsciiDoc(into out: inout String) {
        if let t = title?.plain, !t.isEmpty { out += ".\(t)\n" }
        for item in items { item.renderAsAsciiDoc(into: &out, kind: kind) }
        out += "\n"
    }
}

extension AdocDList: AdocRenderable {
    public func renderAsAsciiDoc(into out: inout String) {
        if let t = title?.plain, !t.isEmpty { out += ".\(t)\n" }
        let markerText = marker.isEmpty ? "::" : marker
        for item in items { item.renderAsAsciiDoc(into: &out, marker: markerText) }
        out += "\n"
    }
}


extension AdocListItem {
    public func renderAsAsciiDoc(into out: inout String, kind: AdocListKind) {
        let markerText: String
        switch kind {
        case .unordered(let m), .ordered(let m): markerText = m
        case .callout:
            markerText = marker.isEmpty ? "<1>" : marker
        }
        out += markerText + " " + principal.plain + "\n"
        for b in blocks { b.renderAsAsciiDoc(into: &out) }
    }
}
extension AdocDListItem {
    public func renderAsAsciiDoc(into out: inout String, marker: String) {
        out += term.plain
        out += marker
        if let principalText = principal?.plain, !principalText.isEmpty {
            out += " "
            out += principalText
        }
        out += "\n"
        for b in blocks { b.renderAsAsciiDoc(into: &out) }
    }
}

extension AdocDiscreteHeading: AdocRenderable {
    public func renderAsAsciiDoc(into out: inout String) {
        out += ".== \(title.plain)\n\n"
    }
}

extension AdocExample: AdocRenderable {
    public func renderAsAsciiDoc(into out: inout String) {
        out += "<<example>>\n\n"
    }
}

extension AdocSidebar: AdocRenderable {
    public func renderAsAsciiDoc(into out: inout String) {
        out += "<<sidebar>>\n\n"
    }
}
extension AdocQuote: AdocRenderable {
    public func renderAsAsciiDoc(into out: inout String) {
        out += "<<quote>>\n\n"
    }
}

extension AdocOpen: AdocRenderable {
    public func renderAsAsciiDoc(into out: inout String) {
        out += "<<open>>\n\n"
    }
}

extension AdocAdmonition: AdocRenderable {
    public func renderAsAsciiDoc(into out: inout String) {
        out += "<<admonition>>\n\n"
    }
}


extension AdocVerse: AdocRenderable {
    public func renderAsAsciiDoc(into out: inout String) {
        out += "<<verse>>\n\n"
    }
}

extension AdocLiteralBlock: AdocRenderable {
    public func renderAsAsciiDoc(into out: inout String) {
        out += "<<literal>>\n\n"
    }
}
extension AdocTable: AdocRenderable {
    public func renderAsAsciiDoc(into out: inout String) {
        // Basic rendering: delimiters + raw rows
        // TODO: Render ID/Title/Attributes if not handled by caller (currently ISM rendering is minimal)
        let delim = String(styleChar) + "===\n"
        out += delim
        for (idx, row) in rows.enumerated() {
             out += row + "\n"
             if headerRowCount > 0, idx + 1 == headerRowCount {
                 out += "\n"
             }
        }
        out += delim + "\n"
    }
}


public enum AdocTableFormat: Sendable, Equatable {
    case psv
    case csv
    case tsv
    case dsv
}

public enum AdocTableColumnAlignment: String, Sendable, Equatable {
    case left
    case center
    case right
}

public enum AdocTableCellStyle: Sendable, Equatable {
    case data
    case header
    case literal
    case monospace
    case emphasis
    case strong
    case asciidoc
    case passthrough
    case unknown(Character)
}

public enum AdocTableVerticalAlignment: String, Sendable, Equatable {
    case top
    case middle
    case bottom
}

public struct AdocTableCell: Sendable, Equatable {
    public var text: String
    public var columnSpan: Int
    public var rowSpan: Int
    public var horizontalAlignment: AdocTableColumnAlignment?
    public var verticalAlignment: AdocTableVerticalAlignment?
    public var style: AdocTableCellStyle
    public var rawSpecifier: String?
}

public struct AdocTable: Sendable, Equatable {
    public var format: AdocTableFormat
    public var separator: Character       // actual delimiter character
    public var styleChar: Character       // char used in the fence (| , : ;)
    public var rows: [String]             // raw table lines (blank separators removed)

    public var headerRowCount: Int = 0
    public var columnAlignments: [AdocTableColumnAlignment]? = nil

    public var id: String?
    public var title: AdocText?
    public var reftext: AdocText?
    public var meta: AdocBlockMeta = .init()
    public var span: AdocRange?
}



public extension AdocTable {
    /// Parsed cells per row, format-aware.
    /// For now:
    ///  - PSV: backslash escapes the separator (and backslash itself).
    ///         If the line starts with the separator (e.g. `|`), a leading
    ///         empty cell is dropped so `| A | B` → ["A", "B"].
    ///  - CSV / TSV / DSV: naive split on separator (no quoting yet).
    var cells: [[String]] {
        parsedRows.map { $0.map(\.text) }
    }

    /// Structured cell rows including span/style metadata.
    var parsedRows: [[AdocTableCell]] {
        groupedRowStrings().map { rowString in
            switch format {
            case .psv:
                return parsePSVRow(rowString, separator: separator)
            case .csv, .tsv, .dsv:
                return parseDelimitedRow(rowString, separator: separator)
            }
        }
    }

    private func groupedRowStrings() -> [String] {
        var grouped: [String] = []
        var buffer: [String] = []
        var rowCanSpanMultipleLines = false

        func flush() {
            guard !buffer.isEmpty else { return }
            grouped.append(buffer.joined(separator: "\n"))
            buffer.removeAll(keepingCapacity: true)
            rowCanSpanMultipleLines = false
        }

        for line in rows {
            if line.isEmpty {
                flush()
                rowCanSpanMultipleLines = true
                continue
            }
            buffer.append(line)
            if !rowCanSpanMultipleLines {
                flush()
            }
        }

        flush()
        return grouped
    }

    /// PSV splitting with `\` escaping the separator and `\` itself.
    private func parsePSVRow(_ line: String, separator sep: Character) -> [AdocTableCell] {
        var result: [AdocTableCell] = []
        var specBuffer = ""
        var contentBuffer = ""
        var collectingContent = false
        var escaped = false
        var currentSpec: String?

        func flushCell() {
            guard collectingContent else { return }
            let text = contentBuffer.trimmedCell()
            let specInfo = parsePSVSpecifier(currentSpec)
            let cell = AdocTableCell(
                text: text,
                columnSpan: specInfo.columnSpan,
                rowSpan: specInfo.rowSpan,
                horizontalAlignment: specInfo.alignment,
                verticalAlignment: specInfo.verticalAlignment,
                style: specInfo.style,
                rawSpecifier: specInfo.raw
            )
            result.append(cell)
            contentBuffer.removeAll(keepingCapacity: false)
            collectingContent = false
            currentSpec = nil
        }

        for ch in line {
            if escaped {
                if collectingContent {
                    contentBuffer.append(ch)
                } else {
                    specBuffer.append(ch)
                }
                escaped = false
                continue
            }
            if ch == "\\" {
                escaped = true
                continue
            }

            if ch == sep {
                if collectingContent {
                    flushCell()
                }
                currentSpec = specBuffer.trimmedCell().isEmpty ? nil : specBuffer.trimmedCell()
                specBuffer.removeAll(keepingCapacity: false)
                collectingContent = true
                continue
            }

            if collectingContent {
                contentBuffer.append(ch)
            } else {
                specBuffer.append(ch)
            }
        }

        if collectingContent {
            flushCell()
        } else if result.isEmpty && !specBuffer.trimmingCharacters(in: .whitespaces).isEmpty {
            // Degenerate row missing separator — treat entire line as a single cell.
            result.append(AdocTableCell(
                text: specBuffer.trimmedCell(),
                columnSpan: 1,
                rowSpan: 1,
                horizontalAlignment: nil,
                verticalAlignment: nil,
                style: .data,
                rawSpecifier: nil
            ))
        }

        return result
    }

    /// Simple split on a separator, no escaping/quoting.
    private func parseDelimitedRow(_ line: String, separator sep: Character) -> [AdocTableCell] {
        let pieces = line.split(separator: sep, omittingEmptySubsequences: false)
        return pieces.map { piece in
            AdocTableCell(
                text: String(piece).trimmedCell(),
                columnSpan: 1,
                rowSpan: 1,
                horizontalAlignment: nil,
                verticalAlignment: nil,
                style: .data,
                rawSpecifier: nil
            )
        }
    }

    private struct ParsedPSVSpecifier {
        var columnSpan: Int = 1
        var rowSpan: Int = 1
        var alignment: AdocTableColumnAlignment?
        var verticalAlignment: AdocTableVerticalAlignment?
        var style: AdocTableCellStyle = .data
        var raw: String?
    }

    private func parsePSVSpecifier(_ rawSpec: String?) -> ParsedPSVSpecifier {
        guard let spec = rawSpec?.trimmingCharacters(in: .whitespaces), !spec.isEmpty else {
            return ParsedPSVSpecifier()
        }

        var parsed = ParsedPSVSpecifier()
        parsed.raw = spec

        var idx = spec.startIndex
        while idx < spec.endIndex {
            let ch = spec[idx]
            switch ch {
            case ".":
                let afterDot = spec.index(after: idx)
                // Check if followed by digits (Row Span)
                let (number, advanced) = consumeDigits(in: spec, from: afterDot)
                if let number, advanced < spec.endIndex, spec[advanced] == "+" {
                    parsed.rowSpan = max(1, number)
                    idx = spec.index(after: advanced)
                } else {
                    // Check for vertical alignment indicators
                    if afterDot < spec.endIndex {
                        let nextChar = spec[afterDot]
                        switch nextChar {
                        case "<":
                            parsed.verticalAlignment = .top
                            idx = spec.index(after: afterDot)
                        case ">":
                            parsed.verticalAlignment = .bottom
                            idx = spec.index(after: afterDot)
                        case "^":
                            parsed.verticalAlignment = .middle
                            idx = spec.index(after: afterDot)
                        default:
                            idx = afterDot // Just a dot, maybe part of something else or invalid
                        }
                    } else {
                        idx = afterDot
                    }
                }
            case "0"..."9":
                let (number, advanced) = consumeDigits(in: spec, from: idx)
                if let number, advanced < spec.endIndex, spec[advanced] == "+" {
                    parsed.columnSpan = max(1, number)
                    idx = spec.index(after: advanced)
                } else if let number, advanced < spec.endIndex, spec[advanced] == "*" {
                     // 2* is sometimes used for span in older docs, or repetition.
                     // Here mapping to span for simplicity if + is standard.
                     // But strictly 2*|A generates |A|A. Repetition is harder to handle in *Parser* returning 1 cell.
                     // We will treat 2* as 2+ for span support if user intends span.
                     parsed.columnSpan = max(1, number)
                     idx = spec.index(after: advanced)
                } else {
                    idx = advanced
                }
            case "<":
                parsed.alignment = .left
            case ">":
                parsed.alignment = .right
                idx = spec.index(after: idx)
            case "^":
                parsed.alignment = .center
                idx = spec.index(after: idx)
            default:
                if ch.isLetter {
                    parsed.style = styleFromIndicator(ch)
                }
                idx = spec.index(after: idx)
            }
        }

        return parsed
    }

    private func consumeDigits(in text: String, from start: String.Index) -> (Int?, String.Index) {
        var idx = start
        while idx < text.endIndex, text[idx].isNumber {
            idx = text.index(after: idx)
        }
        let digits = text[start..<idx]
        let value = Int(digits)
        return (value, idx)
    }

    private func styleFromIndicator(_ indicator: Character) -> AdocTableCellStyle {
        let lower = Character(String(indicator).lowercased())
        switch lower {
        case "h": return .header
        case "a": return .asciidoc
        case "l": return .literal
        case "m": return .monospace
        case "e": return .emphasis
        case "s": return .strong
        case "p": return .passthrough
        case "d": return .data
        default:  return .unknown(indicator)
        }
    }
}

private extension String {
    func trimmedCell() -> String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}


extension AdocBlock {
    /// Unified access to the block’s span (getter + setter).
    public var span: AdocRange? {
        get {
            switch self {
            case .section(let x):          return x.span
            case .paragraph(let x):        return x.span
            case .listing(let x):          return x.span
            case .list(let x):             return x.span
            case .dlist(let x):            return x.span
            case .discreteHeading(let x):  return x.span
            case .sidebar(let x):          return x.span
            case .example(let x):          return x.span
            case .quote(let x):            return x.span
            case .open(let x):             return x.span
            case .admonition(let x):       return x.span
        case .verse(let x):            return x.span
        case .literalBlock(let x):     return x.span
        case .table(let x):            return x.span
        case .math(let x):             return x.span
        case .blockMacro(let x):       return x.span
        }
    }
    set {
        switch self {
            case .section(var x):
                x.span = newValue
                self = .section(x)
            case .paragraph(var x):
                x.span = newValue
                self = .paragraph(x)
            case .listing(var x):
                x.span = newValue
                self = .listing(x)
            case .list(var x):
                x.span = newValue
                self = .list(x)
            case .dlist(var x):
                x.span = newValue
                self = .dlist(x)
            case .discreteHeading(var x):
                x.span = newValue
                self = .discreteHeading(x)
            case .sidebar(var x):
                x.span = newValue
                self = .sidebar(x)
            case .example(var x):
                x.span = newValue
                self = .example(x)
            case .quote(var x):
                x.span = newValue
                self = .quote(x)
            case .open(var x):
                x.span = newValue
                self = .open(x)
            case .admonition(var x):
                x.span = newValue
                self = .admonition(x)
        case .verse(var x):
            x.span = newValue
            self = .verse(x)
        case .literalBlock(var x):
            x.span = newValue
            self = .literalBlock(x)
        case .table(var x):
            x.span = newValue
            self = .table(x)
        case .math(var x):
            x.span = newValue
            self = .math(x)
        case .blockMacro(var x):
            x.span = newValue
            self = .blockMacro(x)
        }
    }
    }
}
