//
// Copyright (c) 2025 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

import Foundation
import AsciiDocCore

public struct RenderConfig {
    public var backend: Backend
    public var inlineBackend: AdocInlineBackend
    public var xrefResolver: XrefResolver?
    public var navigationTree: [String: Any]?

    public init(
        backend: Backend,
        inlineBackend: AdocInlineBackend? = nil,
        xrefResolver: XrefResolver? = nil,
        navigationTree: [String: Any]? = nil
    ) {
        self.backend = backend
        self.xrefResolver = xrefResolver
        self.navigationTree = navigationTree
        self.inlineBackend = inlineBackend ?? {
            switch backend {
            case .html5:    return .html5
            case .docbook5: return .docbook5
            case .latex:    return .latex
            }
        }()
    }
}

public final class DocumentRenderer {
    private let engine: TemplateEngine
    private let config: RenderConfig
    private let inlineRenderer: AdocInlineRenderer
    private var calloutSerial: Int = 0

    public init(engine: TemplateEngine, config: RenderConfig) {
        self.engine = engine
        self.config = config
        
        switch config.inlineBackend {
        case .html5:
            self.inlineRenderer = HtmlInlineRenderer(xrefResolver: config.xrefResolver)
        case .docbook5:
            self.inlineRenderer = DocBookInlineRenderer()
        case .latex:
            self.inlineRenderer = LatexInlineRenderer()
        }
    }

    public func render(document: AdocDocument) throws -> String {
        calloutSerial = 0

        // 1. Resolve footnotes
        let resolution = FootnoteResolver().resolve(document)
        let docToRender = resolution.document
        let footnotes = resolution.definitions

        let blocks = renderBlocks(docToRender.blocks)

        let indexResolver = IndexResolver()
        let indexCatalog = indexResolver.resolve(docToRender)

        let indexEntries = indexCatalog.sortedEntries.map { primary, secondary in
            return [
                "primary": primary,
                "secondary": secondary.map { secName, tertiary in
                    [
                        "name": secName,
                        "tertiary": tertiary
                    ]
                }
            ]
        }

        var context: [String: Any] = [
            "attributes": docToRender.attributes,
            "headerTitle": docToRender.header?.title?.plain ?? "",
            "blocks": blocks,
            "footnotes": footnotes.map(renderFootnoteDefinition),
            "indexCatalog": indexEntries
        ]
        
        if let nav = config.navigationTree {
            context["navigation"] = nav
        }
        
        let templateName: String
        switch config.backend {
        case .html5:    templateName = "html5/document.stencil"
        case .docbook5: templateName = "docbook5/document.stencil"
        case .latex:    templateName = "latex/document.stencil"
        }

        return try engine.render(templateNamed: templateName, context: context)
    }

    private func renderFootnoteDefinition(_ def: FootnoteDefinition) -> [String: Any] {
        return [
            "id": def.id,
            "content": renderInlines(def.content),
            "textPlain": def.content.plainText()
        ]
    }

    private func renderBlocks(_ blocks: [AdocBlock]) -> [[String: Any]] {
        var rendered: [[String: Any]] = []
        var idx = 0
        while idx < blocks.count {
            let block = blocks[idx]
            if case .listing(let listing) = block,
               idx + 1 < blocks.count,
               case .list(let candidate) = blocks[idx + 1],
               case .callout = candidate.kind,
               let bundle = makeCalloutBundle(for: candidate.items) {
                rendered.append(renderListingBlock(listing, calloutBundle: bundle))
                rendered.append(renderListBlock(candidate, calloutBundle: bundle))
                idx += 2
                continue
            }
            rendered.append(renderBlock(block))
            idx += 1
        }
        return rendered
    }

    private func renderBlock(_ block: AdocBlock) -> [String: Any] {
        switch block {
        case .paragraph(let p):
            let title = titlePair(p.title)
            return [
                "kind": "paragraph",
                "html": renderInlines(p.text.inlines),
                "plain": p.text.plain,
                "titleHTML": title.html,
                "titlePlain": title.plain,
                "id": blockIdentifier(p.id, meta: p.meta),
                "meta": metaContext(p.meta)
            ]

        case .section(let s):
            return [
                "kind": "section",
                "level": s.level,
                "titleHTML": renderInlines(s.title.inlines),
                "titlePlain": s.title.plain,
                "blocks": renderBlocks(s.blocks),
                "id": blockIdentifier(s.id, meta: s.meta),
                "meta": metaContext(s.meta)
            ]

        case .discreteHeading(let h):
            return [
                "kind": "discreteHeading",
                "level": h.level,
                "titleHTML": renderInlines(h.title.inlines),
                "titlePlain": h.title.plain,
                "id": blockIdentifier(h.id, meta: h.meta),
                "meta": metaContext(h.meta)
            ]

        case .listing(let l):
            return renderListingBlock(l, calloutBundle: nil)

        case .list(let l):
            return renderListBlock(l, calloutBundle: nil)

        case .dlist(let d):
            let title = titlePair(d.title)
            return [
                "kind": "dlist",
                "marker": d.marker,
                "items": d.items.map(renderDListItem(_:)),
                "titleHTML": title.html,
                "titlePlain": title.plain,
                "id": blockIdentifier(d.id, meta: d.meta),
                "meta": metaContext(d.meta)
            ]

        case .table(let t):
            let title = titlePair(t.title)
            let rows = t.cells
            let structuredRows = t.parsedRows
            let headerCount = min(t.headerRowCount, structuredRows.count)
            let headerRows = Array(structuredRows.prefix(headerCount))
            let bodyRows = Array(structuredRows.dropFirst(headerCount))
            let headerRowCtx = renderTableRows(headerRows, defaultHeader: true)
            let bodyRowCtx = renderTableRows(bodyRows, defaultHeader: false)

            let widestRow = rows.reduce(0) { max($0, $1.count) }
            let inferredColumnCount = max(widestRow, 1)
            let alignmentColumnCount = t.columnAlignments?.count ?? 0
            let columnCount = max(inferredColumnCount, max(alignmentColumnCount, 1))

            let columnSpec: String = {
                if let alignments = t.columnAlignments, !alignments.isEmpty {
                    return alignments.map(\.latexSpec).joined()
                }
                return Array(repeating: "l", count: columnCount).joined()
            }()

            let paddedRows = rows.map { row -> [String] in
                if row.count >= columnCount {
                    return row
                }
                var padded = row
                padded.append(contentsOf: Array(repeating: "", count: columnCount - row.count))
                return padded
            }

            var ctx: [String: Any] = [
                "kind": "table",
                "format": tableFormatString(t.format),
                "rows": rows, // [[String]]
                "rowsPadded": paddedRows,
                "columnCount": columnCount,
                "columnSpec": columnSpec,
                "headerRowCount": headerCount,
                "headerRows": headerRowCtx,
                "bodyRows": bodyRowCtx,
                "titleHTML": title.html,
                "titlePlain": title.plain,
                "id": blockIdentifier(t.id, meta: t.meta),
                "meta": metaContext(t.meta)
            ]
            ctx["columnAlignments"] = t.columnAlignments?.map(\.rawValue) ?? []
            return ctx

        case .sidebar(let s):
            let title = titlePair(s.title)
            return [
                "kind": "sidebar",
                "blocks": renderBlocks(s.blocks),
                "titleHTML": title.html,
                "titlePlain": title.plain,
                "id": blockIdentifier(s.id, meta: s.meta),
                "meta": metaContext(s.meta)
            ]

        case .example(let e):
            let title = titlePair(e.title)
            return [
                "kind": "example",
                "blocks": renderBlocks(e.blocks),
                "titleHTML": title.html,
                "titlePlain": title.plain,
                "id": blockIdentifier(e.id, meta: e.meta),
                "meta": metaContext(e.meta)
            ]

        case .quote(let q):
            let title = titlePair(q.title)
            return [
                "kind": "quote",
                "blocks": renderBlocks(q.blocks),
                "titleHTML": title.html,
                "titlePlain": title.plain,
                "attribution": q.attribution?.plain ?? "",
                "citetitle": q.citetitle?.plain ?? "",
                "id": blockIdentifier(q.id, meta: q.meta),
                "meta": metaContext(q.meta)
            ]

        case .open(let o):
            let title = titlePair(o.title)
            return [
                "kind": "open",
                "blocks": renderBlocks(o.blocks),
                "titleHTML": title.html,
                "titlePlain": title.plain,
                "id": blockIdentifier(o.id, meta: o.meta),
                "meta": metaContext(o.meta)
            ]

        case .admonition(let a):
            return [
                "kind": "admonition",
                "admonitionKind": a.kind ?? "",
                "blocks": renderBlocks(a.blocks),
                "titleHTML": a.title.map { renderInlines($0.inlines) } ?? "",
                "titlePlain": a.title?.plain ?? "",
                "id": blockIdentifier(a.id, meta: a.meta),
                "meta": metaContext(a.meta)
            ]

        case .verse(let v):
            let title = titlePair(v.title)
            return [
                "kind": "verse",
                "textHTML": v.text.map { renderInlines($0.inlines) } ?? "",
                "textPlain": v.text?.plain ?? "",
                "titleHTML": title.html,
                "titlePlain": title.plain,
                "attribution": v.attribution?.plain ?? "",
                "citetitle": v.citetitle?.plain ?? "",
                "id": blockIdentifier(v.id, meta: v.meta),
                "meta": metaContext(v.meta)
            ]

        case .literalBlock(let l):
            let title = titlePair(l.title)
            return [
                "kind": "literal",
                "textPlain": l.text.plain,
                "titleHTML": title.html,
                "titlePlain": title.plain,
                "id": blockIdentifier(l.id, meta: l.meta),
                "meta": metaContext(l.meta)
            ]

        case .math(let m):
            let mathML = MathMLRenderer.render(kind: m.kind, body: m.body, display: m.display)
            let latexBody = (m.kind == .latex) ? m.body : AsciiMathTranslator.convert(m.body)
            return [
                "kind": "math",
                "mathML": mathML,
                "display": m.display,
                "raw": m.body,
                 "latex": latexBody,
                "mathKind": m.kind == .latex ? "latex" : "asciimath",
                "titleHTML": m.title.map { renderInlines($0.inlines) } ?? "",
                "titlePlain": m.title?.plain ?? "",
                "id": blockIdentifier(m.id, meta: m.meta),
                "meta": metaContext(m.meta)
            ]

        case .blockMacro(let m):
            let altText = m.meta.attributes["alt"] ?? m.meta.attributes["1"] ?? m.title?.plain ?? ""
            return [
                "kind": "blockMacro",
                "name": m.name,
                "target": m.target ?? "",
                "titleHTML": m.title.map { renderInlines($0.inlines) } ?? "",
                "titlePlain": m.title?.plain ?? "",
                "altText": altText,
                "attributes": m.meta.attributes,
                "options": Array(m.meta.options),
                "roles": m.meta.roles,
                "roleClass": m.meta.roles.joined(separator: " "),
                "id": blockIdentifier(m.id, meta: m.meta),
                "meta": metaContext(m.meta)
            ]
        }
    }

    private func renderListingBlock(_ listing: AdocListing, calloutBundle: CalloutBundle?) -> [String: Any] {
        let title = titlePair(listing.title)
        var textPlain = listing.text.plain
        var calloutMarkup: String? = nil

        if let bundle = calloutBundle,
           let annotated = annotateListingText(listing.text.plain, bundle: bundle) {
            switch config.backend {
            case .latex:
                textPlain = annotated
            case .html5, .docbook5:
                calloutMarkup = annotated
            }
        }

        let isSourceBlock = (listing.meta.attributes["style"]?.lowercased() == "source")
        let language = listingLanguage(for: listing)

        var context: [String: Any] = [
            "kind": "listing",
            "textHTML": renderInlines(listing.text.inlines),
            "textPlain": textPlain,
            "delimiter": listing.delimiter ?? "----",
            "titleHTML": title.html,
            "titlePlain": title.plain,
            "id": blockIdentifier(listing.id, meta: listing.meta),
            "meta": metaContext(listing.meta)
        ]
        if let calloutMarkup {
            context["calloutMarkup"] = calloutMarkup
        }
        if isSourceBlock {
            context["isSource"] = true
        }
        if let language {
            context["language"] = language
        }
        return context
    }

    private func renderListBlock(_ list: AdocList, calloutBundle: CalloutBundle?) -> [String: Any] {
        let title = titlePair(list.title)
        var items: [[String: Any]]
        var bundle = calloutBundle

        if case .callout = list.kind {
            if bundle == nil {
                bundle = makeCalloutBundle(for: list.items)
            }
            if let bundle {
                items = zip(list.items, bundle.itemMarkers).map { item, marker in
                    renderListItem(item, callout: marker)
                }
            } else {
                items = list.items.map(renderListItem(_:))
            }
        } else {
            items = list.items.map(renderListItem(_:))
        }

        return [
            "kind": "list",
            "listType": listTypeString(list.kind),
            "items": items,
            "titleHTML": title.html,
            "titlePlain": title.plain,
            "id": blockIdentifier(list.id, meta: list.meta),
            "meta": metaContext(list.meta)
        ]
    }

    private func renderListItem(_ item: AdocListItem) -> [String: Any] {
        return renderListItem(item, callout: nil)
    }

    private func renderListItem(_ item: AdocListItem, callout: CalloutMarker?) -> [String: Any] {
        let title = titlePair(item.title)
        var context: [String: Any] = [
            "id": blockIdentifier(item.id, meta: item.meta),
            "marker": item.marker,
            "principalHTML": renderInlines(item.principal.inlines),
            "principalPlain": item.principal.plain,
            "titleHTML": title.html,
            "titlePlain": title.plain,
            "blocks": renderBlocks(item.blocks),
            "meta": metaContext(item.meta)
        ]
        if let callout {
            context["callout"] = [
                "number": callout.ordinal,
                "id": callout.id
            ]
        }
        return context
    }

    private func renderDListItem(_ item: AdocDListItem) -> [String: Any] {
        let title = titlePair(item.title)
        return [
            "termHTML": renderInlines(item.term.inlines),
            "termPlain": item.term.plain,
            "principalHTML": item.principal.map { renderInlines($0.inlines) } ?? "",
            "principalPlain": item.principal?.plain ?? "",
            "titleHTML": title.html,
            "titlePlain": title.plain,
            "blocks": renderBlocks(item.blocks),
            "id": blockIdentifier(item.id, meta: item.meta),
            "meta": metaContext(item.meta)
        ]
    }

    private func renderInlines(_ inlines: [AdocInline]) -> String {
        inlineRenderer.render(inlines)
    }

    // Helpers

    private func titlePair(_ text: AdocText?) -> (html: String, plain: String) {
        guard let text else {
            return ("", "")
        }
        return (renderInlines(text.inlines), text.plain)
    }

    private func blockIdentifier(_ id: String?, meta: AdocBlockMeta) -> String {
        id ?? meta.id ?? ""
    }

    private func listTypeString(_ kind: AdocListKind) -> String {
        switch kind {
        case .unordered: return "unordered"
        case .ordered:   return "ordered"
        case .callout:   return "callout"
        }
    }

    private func tableFormatString(_ f: AdocTableFormat) -> String {
        switch f {
        case .psv: return "psv"
        case .csv: return "csv"
        case .tsv: return "tsv"
        case .dsv: return "dsv"
        }
    }

    private func renderTableRows(_ rows: [[AdocTableCell]], defaultHeader: Bool) -> [[ [String: Any] ]] {
        rows.map { row in
            row.map { cell in
                let inlines = parseInlines(cell.text, baseSpan: nil)
                let renderedContent = renderInlines(inlines)
                
                var ctx: [String: Any] = [
                    "text": renderedContent, // Now contains rendered HTML/XML
                    "colSpan": cell.columnSpan,
                    "rowSpan": cell.rowSpan,
                    "style": renderTableCellStyle(cell.style),
                    "isHeader": defaultHeader || cell.style == .header
                ]
                if let align = cell.horizontalAlignment {
                    ctx["align"] = align.cssValue
                }
                if let valign = cell.verticalAlignment {
                    ctx["valign"] = valign.rawValue
                }
                return ctx
            }
        }
    }

    private func renderTableCellStyle(_ style: AdocTableCellStyle) -> String {
        switch style {
        case .data: return "data"
        case .header: return "header"
        case .literal: return "literal"
        case .monospace: return "monospace"
        case .emphasis: return "emphasis"
        case .strong: return "strong"
        case .asciidoc: return "asciidoc"
        case .passthrough: return "passthrough"
        case .unknown(let c): return String(c)
        }
    }

    private func metaContext(_ meta: AdocBlockMeta) -> [String: Any] {
        [
            "attributes": meta.attributes,
            "options": Array(meta.options),
            "roles": meta.roles,
            "roleClass": meta.roles.joined(separator: " "),
            "id": meta.id ?? ""
        ]
    }

    private func makeCalloutBundle(for items: [AdocListItem]) -> CalloutBundle? {
        var ordinals: [Int?] = []
        var hasOrdinal = false
        for item in items {
            let ordinal = parseCalloutOrdinal(from: item.marker)
            ordinals.append(ordinal)
            if ordinal != nil { hasOrdinal = true }
        }
        guard hasOrdinal else { return nil }

        let base = nextCalloutBase()
        var perItem: [CalloutMarker?] = []
        var lookup: [Int: CalloutMarker] = [:]

        for ordinal in ordinals {
            if let ordinal {
                let marker = CalloutMarker(ordinal: ordinal, id: "\(base)-\(ordinal)")
                perItem.append(marker)
                lookup[ordinal] = marker
            } else {
                perItem.append(nil)
            }
        }

        return CalloutBundle(baseId: base, itemMarkers: perItem, lookup: lookup)
    }

    private func nextCalloutBase() -> String {
        calloutSerial += 1
        return "co\(calloutSerial)"
    }

    private func parseCalloutOrdinal(from marker: String) -> Int? {
        let digits = marker.filter { $0.isNumber }
        return digits.isEmpty ? nil : Int(digits)
    }

    private func annotateListingText(_ text: String, bundle: CalloutBundle) -> String? {
        switch config.backend {
        case .html5:
            return transformCallouts(
                in: text,
                bundle: bundle,
                escape: escapeHTMLChar
            ) { marker in
                let label = "(\(marker.ordinal))"
                return "<b class=\"conum\" data-callout=\"\(marker.ordinal)\"><a href=\"#\(marker.id)\">\(label)</a></b>"
            }
        case .docbook5:
            return transformCallouts(
                in: text,
                bundle: bundle,
                escape: escapeHTMLChar
            ) { marker in
                "<co xml:id=\"\(marker.id)\"/>"
            }
        case .latex:
            return transformCallouts(
                in: text,
                bundle: bundle,
                escape: { String($0) }
            ) { marker in
                "(\(marker.ordinal))"
            }
        }
    }

    private func transformCallouts(
        in text: String,
        bundle: CalloutBundle,
        escape: (Character) -> String,
        replacement: (CalloutMarker) -> String
    ) -> String? {
        var output = ""
        var replaced = false
        var index = text.startIndex

        while index < text.endIndex {
            let ch = text[index]
            if ch == "<" {
                var j = text.index(after: index)
                var digits = ""
                while j < text.endIndex, text[j].isNumber {
                    digits.append(text[j])
                    j = text.index(after: j)
                }
                if !digits.isEmpty,
                   j < text.endIndex,
                   text[j] == ">",
                   let number = Int(digits),
                   let marker = bundle.lookup[number] {
                    output.append(replacement(marker))
                    replaced = true
                    index = text.index(after: j)
                    continue
                }
            }
            output.append(escape(ch))
            index = text.index(after: index)
        }

        return replaced ? output : nil
    }

    private func escapeHTMLChar(_ char: Character) -> String {
        switch char {
        case "&": return "&amp;"
        case "<": return "&lt;"
        case ">": return "&gt;"
        case "\"": return "&quot;"
        default: return String(char)
        }
    }

    private func listingLanguage(for listing: AdocListing) -> String? {
        func normalized(_ value: String?) -> String? {
            guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !trimmed.isEmpty
            else { return nil }
            return trimmed
        }

        var structuralStyles: Set<String> = []
        if let style = listing.meta.attributes["style"]?.lowercased() {
            structuralStyles.insert(style)
        }
        if let firstPositional = listing.meta.attributes["1"]?.lowercased() {
            structuralStyles.insert(firstPositional)
        }

        func scrub(_ candidate: String?) -> String? {
            guard let lang = normalized(candidate) else { return nil }
            let lowered = lang.lowercased()
            if structuralStyles.contains(lowered) {
                return nil
            }
            if reservedListingLanguageNames.contains(lowered) {
                return nil
            }
            return lang
        }

        if let lang = scrub(listing.meta.attributes["language"]) {
            return lang
        }
        if let lang = scrub(listing.meta.attributes["source-language"]) {
            return lang
        }
        if let lang = scrub(listing.meta.attributes["2"]) {
            return lang
        }
        if let lang = scrub(listing.meta.attributes["1"]) {
            return lang
        }
        return nil
    }



    private struct CalloutMarker {
        let ordinal: Int
        let id: String
    }

    private struct CalloutBundle {
        let baseId: String
        let itemMarkers: [CalloutMarker?]
        let lookup: [Int: CalloutMarker]
    }
}

private extension AdocTableColumnAlignment {
    var cssValue: String {
        switch self {
        case .left: return "left"
        case .center: return "center"
        case .right: return "right"
        }
    }

    var latexSpec: String {
        switch self {
        case .left: return "l"
        case .center: return "c"
        case .right: return "r"
        }
    }
}

private let reservedListingLanguageNames: Set<String> = [
    "source", "listing", "literal", "verse", "quote", "example", "sidebar", "open"
]
