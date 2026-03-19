//
// Copyright (c) 2025 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

import Foundation
import AsciiDocCore
import AsciiDocPagedRendering

public struct RenderConfig {
    public var backend: Backend
    public var inlineBackend: AdocInlineBackend
    public var xrefResolver: XrefResolver?
    public var navigationTree: [String: Any]?
    public var customTemplateName: String?
    public var xadOptions: XADOptions
    public var xadLayoutProgram: LayoutProgram?
    public var blockMacroResolvers: [any BlockMacroResolver]

    public init(
        backend: Backend,
        inlineBackend: AdocInlineBackend? = nil,
        xrefResolver: XrefResolver? = nil,
        navigationTree: [String: Any]? = nil,
        customTemplateName: String? = nil,
        xadOptions: XADOptions = .init(),
        xadLayoutProgram: LayoutProgram? = nil,
        blockMacroResolvers: [any BlockMacroResolver] = []
    ) {
        self.backend = backend
        self.xrefResolver = xrefResolver
        self.navigationTree = navigationTree
        self.customTemplateName = customTemplateName
        self.xadOptions = xadOptions
        self.xadLayoutProgram = xadLayoutProgram
        self.blockMacroResolvers = blockMacroResolvers
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

    private enum SlotMode {
        case move
        case copy
    }

    private struct SlotItem {
        let block: AdocBlock
        let order: Double
        let index: Int
    }

    private struct SlotExtractionResult {
        var mainBlocks: [AdocBlock]
        var slots: [String: [SlotItem]]
        var collections: [String: [SlotItem]]
        var warnings: [AdocWarning]
    }

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
        
        // Context setup
        var sourceURL: URL? = nil
        if let fileStack = document.header?.location?.start.file,
           let last = fileStack.last {
            sourceURL = URL(fileURLWithPath: last)
        }
        
        let inlineContext = InlineContext(sourceURL: sourceURL)

        // 1. Resolve footnotes
        let resolution = FootnoteResolver().resolve(document)
        let docToRender = resolution.document
        let footnotes = resolution.definitions

        let slotExtraction: SlotExtractionResult
        let blocks: [[String: Any]]
        if config.xadOptions.enabled {
            slotExtraction = extractSlotsAndCollections(from: docToRender)
            blocks = renderBlocks(slotExtraction.mainBlocks, context: inlineContext)
        } else {
            slotExtraction = SlotExtractionResult(
                mainBlocks: docToRender.blocks,
                slots: [:],
                collections: [:],
                warnings: []
            )
            blocks = renderBlocks(docToRender.blocks, context: inlineContext)
        }

        var templateDocument: XADTemplateDocument?
        var templateWarnings: [AdocWarning] = []
        var layoutProgram = config.xadLayoutProgram
        if config.xadOptions.enabled, let templatePath = config.xadOptions.templatePath {
            let templateURL = resolveTemplateURL(
                templatePath,
                relativeTo: sourceURL?.deletingLastPathComponent()
            )
            let ingestor = XADTemplateIngestor()
            let (template, warnings) = ingestor.ingestTemplate(
                at: templateURL,
                xadOptions: config.xadOptions
            )
            templateDocument = template
            templateWarnings.append(contentsOf: warnings)
            if let program = template?.layoutProgram {
                layoutProgram = program
            }
        }

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

        let typedAttributes = docToRender.typedAttributes.mapValues { $0.toJSONCompatible() }
        let pagedEnabled = config.xadOptions.pagedJS || isPagedAttributeEnabled(document: docToRender)
        var xadContext: [String: Any] = [
            "enabled": config.xadOptions.enabled,
            "strict": config.xadOptions.strict,
            "pagedJS": pagedEnabled,
            "templatePath": config.xadOptions.templatePath ?? "",
            "layoutTemplate": config.xadOptions.layoutTemplate ?? "",
            "layoutTemplateBase": config.xadOptions.layoutTemplateBase ?? "",
            "layoutTemplateSearchPaths": config.xadOptions.layoutTemplateSearchPaths
        ]
        if config.xadOptions.enabled {
            var slotContexts = renderSlotGroups(slotExtraction.slots, context: inlineContext)
            slotContexts["main"] = blocks
            let collectionContexts = renderSlotGroups(slotExtraction.collections, context: inlineContext)
            xadContext["slots"] = slotContexts
            xadContext["collections"] = collectionContexts

            var warnings = slotExtraction.warnings
            warnings.append(contentsOf: templateWarnings)
            if let program = layoutProgram {
                let evaluator = XADLayoutEvaluator()
                let evaluation = evaluator.evaluate(
                    program: program,
                    slots: slotContexts,
                    collections: collectionContexts
                )
                xadContext["layoutTree"] = evaluation.tree
                warnings.append(contentsOf: evaluation.warnings)
            }

            if !warnings.isEmpty {
                xadContext["warnings"] = warnings.map { $0.message }
            }
        }
        if let program = layoutProgram {
            xadContext["layoutProgram"] = layoutProgramContext(program)
        }
        if let templateDocument {
            var templateContext: [String: Any] = [
                "path": templateDocument.url.path,
                "attributes": templateDocument.attributes,
                "typedAttributes": templateDocument.typedAttributes.mapValues { $0.toJSONCompatible() },
                "css": templateDocument.assets.css,
                "js": templateDocument.assets.js
            ]
            if let pageCSS = pageCSS(from: templateDocument) {
                templateContext["pageCSS"] = pageCSS
            }
            if let styleCSS = styleCSS(from: templateDocument) {
                templateContext["styleCSS"] = styleCSS
            }
            xadContext["template"] = templateContext
        }

        var context: [String: Any] = [
            "attributes": docToRender.attributes,
            "typedAttributes": typedAttributes,
            "headerTitle": docToRender.header?.title?.plain ?? "",
            "blocks": blocks,
            "footnotes": footnotes.map { renderFootnoteDefinition($0, context: inlineContext) },
            "indexCatalog": indexEntries,
            "xad": xadContext
        ]
        
        if let nav = config.navigationTree {
            context["navigation"] = nav
        }
        
        let templateName: String
        if let custom = config.customTemplateName {
            templateName = custom
        } else {
            switch config.backend {
            case .html5:    templateName = "html5/document.stencil"
            case .docbook5: templateName = "docbook5/document.stencil"
            case .latex:    templateName = "latex/document.stencil"
            }
        }

        return try engine.render(templateNamed: templateName, context: context)
    }

    private func renderFootnoteDefinition(_ def: FootnoteDefinition, context: InlineContext) -> [String: Any] {
        return [
            "id": def.id,
            "content": renderInlines(def.content, context: context),
            "textPlain": def.content.plainText()
        ]
    }

    private func layoutProgramContext(_ program: LayoutProgram) -> [String: Any] {
        return [
            "expressions": program.expressions.map { layoutExprContext($0) }
        ]
    }

    private func layoutExprContext(_ expr: LayoutExpr) -> [String: Any] {
        switch expr {
        case .node(let node):
            return [
                "type": "node",
                "name": node.name,
                "args": node.args.map { layoutArgContext($0) },
                "children": node.children.map { layoutExprContext($0) }
            ]
        case .value(let value):
            return [
                "type": "value",
                "value": layoutValueContext(value)
            ]
        }
    }

    private func layoutArgContext(_ arg: LayoutArg) -> [String: Any] {
        return [
            "name": arg.name ?? "",
            "named": arg.name != nil,
            "value": layoutExprContext(arg.value)
        ]
    }

    private func layoutValueContext(_ value: LayoutValue) -> Any {
        switch value {
        case .string(let string):
            return string
        case .number(let number):
            return number
        case .boolean(let boolean):
            return boolean
        case .null:
            return NSNull()
        case .array(let values):
            return values.map { layoutValueContext($0) }
        case .dict(let dict):
            var out: [String: Any] = [:]
            for (key, entry) in dict {
                out[key] = layoutValueContext(entry)
            }
            return out
        case .ref(let ref):
            var payload: [String: Any] = [
                "type": "ref",
                "parts": ref.parts
            ]
            if let index = ref.index {
                payload["index"] = layoutIndexContext(index)
            }
            return payload
        }
    }

    private func layoutIndexContext(_ index: LayoutIndex) -> Any {
        switch index {
        case .number(let number):
            return ["type": "number", "value": number]
        case .string(let string):
            return ["type": "string", "value": string]
        case .identifier(let ident):
            return ["type": "identifier", "value": ident]
        }
    }

    private func renderBlocks(_ blocks: [AdocBlock], context: InlineContext) -> [[String: Any]] {
        var rendered: [[String: Any]] = []
        var idx = 0
        while idx < blocks.count {
            let block = blocks[idx]
            if case .listing(let listing) = block,
               idx + 1 < blocks.count,
               case .list(let candidate) = blocks[idx + 1],
               case .callout = candidate.kind,
               let bundle = makeCalloutBundle(for: candidate.items) {
                rendered.append(renderListingBlock(listing, calloutBundle: bundle, context: context))
                rendered.append(renderListBlock(candidate, calloutBundle: bundle, context: context))
                idx += 2
                continue
            }
            rendered.append(renderBlock(block, context: context))
            idx += 1
        }
        return rendered
    }
    
    private func renderBlock(_ block: AdocBlock, context: InlineContext) -> [String: Any] {
        switch block {
        case .paragraph(let p):
            let title = titlePair(p.title, context: context)
            return [
                "kind": "paragraph",
                "html": renderInlines(p.text.inlines, context: context),
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
                "titleHTML": renderInlines(s.title.inlines, context: context),
                "titlePlain": s.title.plain,
                "blocks": renderBlocks(s.blocks, context: context),
                "id": blockIdentifier(s.id, meta: s.meta),
                "meta": metaContext(s.meta)
            ]

        case .discreteHeading(let h):
            return [
                "kind": "discreteHeading",
                "level": h.level,
                "titleHTML": renderInlines(h.title.inlines, context: context),
                "titlePlain": h.title.plain,
                "id": blockIdentifier(h.id, meta: h.meta),
                "meta": metaContext(h.meta)
            ]

        case .listing(let l):
            return renderListingBlock(l, calloutBundle: nil, context: context)

        case .list(let l):
            return renderListBlock(l, calloutBundle: nil, context: context)

        case .dlist(let d):
            let title = titlePair(d.title, context: context)
            return [
                "kind": "dlist",
                "marker": d.marker,
                "items": d.items.map { renderDListItem($0, context: context) },
                "titleHTML": title.html,
                "titlePlain": title.plain,
                "id": blockIdentifier(d.id, meta: d.meta),
                "meta": metaContext(d.meta)
            ]

        case .table(let t):
            let title = titlePair(t.title, context: context)
            let rows = t.cells
            let structuredRows = t.parsedRows
            let headerCount = min(t.headerRowCount, structuredRows.count)
            let headerRows = Array(structuredRows.prefix(headerCount))
            let bodyRows = Array(structuredRows.dropFirst(headerCount))
            let headerRowCtx = renderTableRows(headerRows, defaultHeader: true, context: context)
            let bodyRowCtx = renderTableRows(bodyRows, defaultHeader: false, context: context)

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
            let title = titlePair(s.title, context: context)
            return [
                "kind": "sidebar",
                "blocks": renderBlocks(s.blocks, context: context),
                "titleHTML": title.html,
                "titlePlain": title.plain,
                "id": blockIdentifier(s.id, meta: s.meta),
                "meta": metaContext(s.meta)
            ]

        case .example(let e):
            let title = titlePair(e.title, context: context)
            return [
                "kind": "example",
                "blocks": renderBlocks(e.blocks, context: context),
                "titleHTML": title.html,
                "titlePlain": title.plain,
                "id": blockIdentifier(e.id, meta: e.meta),
                "meta": metaContext(e.meta)
            ]

        case .quote(let q):
            let title = titlePair(q.title, context: context)
            return [
                "kind": "quote",
                "blocks": renderBlocks(q.blocks, context: context),
                "titleHTML": title.html,
                "titlePlain": title.plain,
                "attribution": q.attribution?.plain ?? "",
                "citetitle": q.citetitle?.plain ?? "",
                "id": blockIdentifier(q.id, meta: q.meta),
                "meta": metaContext(q.meta)
            ]

        case .open(let o):
            let title = titlePair(o.title, context: context)
            return [
                "kind": "open",
                "blocks": renderBlocks(o.blocks, context: context),
                "titleHTML": title.html,
                "titlePlain": title.plain,
                "id": blockIdentifier(o.id, meta: o.meta),
                "meta": metaContext(o.meta)
            ]

        case .admonition(let a):
            return [
                "kind": "admonition",
                "admonitionKind": a.kind ?? "",
                "blocks": renderBlocks(a.blocks, context: context),
                "titleHTML": a.title.map { renderInlines($0.inlines, context: context) } ?? "",
                "titlePlain": a.title?.plain ?? "",
                "id": blockIdentifier(a.id, meta: a.meta),
                "meta": metaContext(a.meta)
            ]

        case .verse(let v):
            let title = titlePair(v.title, context: context)
            return [
                "kind": "verse",
                "textHTML": v.text.map { renderInlines($0.inlines, context: context) } ?? "",
                "textPlain": v.text?.plain ?? "",
                "titleHTML": title.html,
                "titlePlain": title.plain,
                "attribution": v.attribution?.plain ?? "",
                "citetitle": v.citetitle?.plain ?? "",
                "id": blockIdentifier(v.id, meta: v.meta),
                "meta": metaContext(v.meta)
            ]

        case .literalBlock(let l):
            let title = titlePair(l.title, context: context)
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
                "titleHTML": m.title.map { renderInlines($0.inlines, context: context) } ?? "",
                "titlePlain": m.title?.plain ?? "",
                "id": blockIdentifier(m.id, meta: m.meta),
                "meta": metaContext(m.meta)
            ]

        case .blockMacro(let m):
            var macroAttributes = m.attributes
            for (key, value) in m.meta.attributes {
                macroAttributes[key] = value
            }
            let resolverContext = resolveBlockMacroContext(m, attributes: macroAttributes)
            if let resolvedAttributes = resolverContext["attributes"] as? [String: String] {
                macroAttributes = resolvedAttributes
            }
            let altText = macroAttributes["alt"] ?? macroAttributes["1"] ?? m.title?.plain ?? ""
            if m.name == "lyrics" {
                let lyrics = parseLyrics(target: m.target ?? "", chordsEnabled: isTruthy(macroAttributes["chords"]))
                return [
                    "kind": "blockMacro",
                    "name": m.name,
                    "target": m.target ?? "",
                    "titleHTML": m.title.map { renderInlines($0.inlines, context: context) } ?? "",
                    "titlePlain": m.title?.plain ?? "",
                    "altText": altText,
                    "attributes": macroAttributes,
                    "options": Array(m.meta.options),
                    "roles": m.meta.roles,
                    "roleClass": m.meta.roles.joined(separator: " "),
                    "id": blockIdentifier(m.id, meta: m.meta),
                    "meta": metaContext(m.meta),
                    "lines": lyrics.lines,
                    "hasChords": lyrics.hasChords,
                    "part": macroAttributes["part"] ?? ""
                ].merging(resolverContext, uniquingKeysWith: { _, new in new })
            }
            return [
                "kind": "blockMacro",
                "name": m.name,
                "target": m.target ?? "",
                "titleHTML": m.title.map { renderInlines($0.inlines, context: context) } ?? "",
                "titlePlain": m.title?.plain ?? "",
                "altText": altText,
                "attributes": macroAttributes,
                "options": Array(m.meta.options),
                "roles": m.meta.roles,
                "roleClass": m.meta.roles.joined(separator: " "),
                "id": blockIdentifier(m.id, meta: m.meta),
                "meta": metaContext(m.meta)
            ].merging(resolverContext, uniquingKeysWith: { _, new in new })
        }
    }

    private func renderListingBlock(_ listing: AdocListing, calloutBundle: CalloutBundle?, context: InlineContext) -> [String: Any] {
        let title = titlePair(listing.title, context: context)
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

        var ctx: [String: Any] = [
            "kind": "listing",
            "textHTML": renderInlines(listing.text.inlines, context: context),
            "textPlain": textPlain,
            "delimiter": listing.delimiter ?? "----",
            "titleHTML": title.html,
            "titlePlain": title.plain,
            "id": blockIdentifier(listing.id, meta: listing.meta),
            "meta": metaContext(listing.meta)
        ]
        if let calloutMarkup {
            ctx["calloutMarkup"] = calloutMarkup
        }
        if isSourceBlock {
            ctx["isSource"] = true
        }
        if let language {
            ctx["language"] = language
        }
        return ctx
    }

    private func renderListBlock(_ list: AdocList, calloutBundle: CalloutBundle?, context: InlineContext) -> [String: Any] {
        let title = titlePair(list.title, context: context)
        var items: [[String: Any]]
        var bundle = calloutBundle

        if case .callout = list.kind {
            if bundle == nil {
                bundle = makeCalloutBundle(for: list.items)
            }
            if let bundle {
                items = zip(list.items, bundle.itemMarkers).map { item, marker in
                    renderListItem(item, callout: marker, context: context)
                }
            } else {
                items = list.items.map { renderListItem($0, context: context) }
            }
        } else {
            items = list.items.map { renderListItem($0, context: context) }
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

    private func renderListItem(_ item: AdocListItem, context: InlineContext) -> [String: Any] {
        return renderListItem(item, callout: nil, context: context)
    }

    private func renderListItem(_ item: AdocListItem, callout: CalloutMarker?, context: InlineContext) -> [String: Any] {
        let title = titlePair(item.title, context: context)
        var ctx: [String: Any] = [
            "id": blockIdentifier(item.id, meta: item.meta),
            "marker": item.marker,
            "principalHTML": renderInlines(item.principal.inlines, context: context),
            "principalPlain": item.principal.plain,
            "titleHTML": title.html,
            "titlePlain": title.plain,
            "blocks": renderBlocks(item.blocks, context: context),
            "meta": metaContext(item.meta)
        ]
        if let callout {
            ctx["callout"] = [
                "number": callout.ordinal,
                "id": callout.id
            ]
        }
        return ctx
    }

    private func renderDListItem(_ item: AdocDListItem, context: InlineContext) -> [String: Any] {
        let title = titlePair(item.title, context: context)
        return [
            "termHTML": renderInlines(item.term.inlines, context: context),
            "termPlain": item.term.plain,
            "principalHTML": item.principal.map { renderInlines($0.inlines, context: context) } ?? "",
            "principalPlain": item.principal?.plain ?? "",
            "titleHTML": title.html,
            "titlePlain": title.plain,
            "blocks": renderBlocks(item.blocks, context: context),
            "id": blockIdentifier(item.id, meta: item.meta),
            "meta": metaContext(item.meta)
        ]
    }

    private func renderSlotGroups(_ groups: [String: [SlotItem]], context: InlineContext) -> [String: [[String: Any]]] {
        var rendered: [String: [[String: Any]]] = [:]
        for (name, items) in groups {
            let sorted = items.sorted {
                if $0.order == $1.order { return $0.index < $1.index }
                return $0.order < $1.order
            }
            let slotBlocks = sorted.map { $0.block }
            rendered[name] = renderBlocks(slotBlocks, context: context)
        }
        return rendered
    }

    private func extractSlotsAndCollections(from document: AdocDocument) -> SlotExtractionResult {
        var slots: [String: [SlotItem]] = [:]
        var collections: [String: [SlotItem]] = [:]
        var warnings: [AdocWarning] = []
        var slotModeCache: [String: SlotMode] = [:]
        var index = 0

        func attributeValue(_ name: String) -> String? {
            guard let value = document.attributes[name] else { return nil }
            return value ?? ""
        }

        func slotMode(for slot: String) -> SlotMode {
            if let cached = slotModeCache[slot] { return cached }
            let raw = attributeValue("slot.mode.\(slot)") ?? attributeValue("slot.mode.default")
            let mode: SlotMode
            if let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
                switch raw.lowercased() {
                case "move":
                    mode = .move
                case "copy":
                    mode = .copy
                default:
                    warnings.append(AdocWarning(message: "Invalid slot.mode value '\(raw)' for '\(slot)'; defaulting to move."))
                    mode = .move
                }
            } else {
                mode = .move
            }
            slotModeCache[slot] = mode
            return mode
        }

        func parseOrder(_ raw: String?, context: String, span: AdocRange?) -> Double {
            guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
                return 0
            }
            if let value = Double(raw) {
                return value
            }
            warnings.append(AdocWarning(message: "Invalid order '\(raw)' for \(context); defaulting to 0.", span: span))
            return 0
        }

        func normalizedName(_ raw: String?) -> String? {
            guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
                return nil
            }
            return raw
        }

        func addSlot(_ name: String, block: AdocBlock, order: Double, index: Int) {
            slots[name, default: []].append(SlotItem(block: block, order: order, index: index))
        }

        func addCollection(_ name: String, block: AdocBlock, order: Double, index: Int) {
            collections[name, default: []].append(SlotItem(block: block, order: order, index: index))
        }

        func isAbstractBlock(_ meta: AdocBlockMeta) -> Bool {
            if let style = meta.attributes["style"], style.lowercased() == "abstract" {
                return true
            }
            return meta.roles.contains { $0.lowercased() == "abstract" }
        }

        func isBibliographyBlock(_ meta: AdocBlockMeta) -> Bool {
            if let style = meta.attributes["style"], style.lowercased() == "bibliography" {
                return true
            }
            return meta.roles.contains { $0.lowercased() == "bibliography" }
        }

        func inferredSlotName(for meta: AdocBlockMeta) -> String? {
            if isAbstractBlock(meta) { return "abstract" }
            if isBibliographyBlock(meta) { return "bibliography" }
            return nil
        }

        func extractBlocks(_ blocks: [AdocBlock]) -> [AdocBlock] {
            var out: [AdocBlock] = []
            for block in blocks {
                if let extracted = extractBlock(block) {
                    out.append(extracted)
                }
            }
            return out
        }

        func extractBlock(_ block: AdocBlock) -> AdocBlock? {
            let meta = blockMeta(block)
            let slotName = normalizedName(meta.attributes["slot"])
            let collectionName = normalizedName(meta.attributes["collect"])
            let inferredSlot = slotName == nil && collectionName == nil ? inferredSlotName(for: meta) : nil
            let orderContext = slotName ?? collectionName ?? inferredSlot ?? "main"
            let order = parseOrder(meta.attributes["order"], context: orderContext, span: meta.span)
            index += 1
            let currentIndex = index

            if let collectionName {
                addCollection(collectionName, block: block, order: order, index: currentIndex)
            }

            let effectiveSlot = slotName ?? inferredSlot ?? "main"
            if effectiveSlot != "main" {
                addSlot(effectiveSlot, block: block, order: order, index: currentIndex)
            }

            let shouldMove = effectiveSlot != "main" && slotMode(for: effectiveSlot) == .move
            if shouldMove {
                return nil
            }

            if slotName != nil || collectionName != nil || inferredSlot != nil {
                return block
            }

            switch block {
            case .section(var s):
                s.blocks = extractBlocks(s.blocks)
                return .section(s)
            case .sidebar(var s):
                s.blocks = extractBlocks(s.blocks)
                return .sidebar(s)
            case .example(var e):
                e.blocks = extractBlocks(e.blocks)
                return .example(e)
            case .quote(var q):
                q.blocks = extractBlocks(q.blocks)
                return .quote(q)
            case .open(var o):
                o.blocks = extractBlocks(o.blocks)
                return .open(o)
            case .admonition(var a):
                a.blocks = extractBlocks(a.blocks)
                return .admonition(a)
            case .verse(var v):
                v.blocks = extractBlocks(v.blocks)
                return .verse(v)
            case .list(var l):
                l.items = l.items.map { item in
                    var updated = item
                    updated.blocks = extractBlocks(item.blocks)
                    return updated
                }
                return .list(l)
            case .dlist(var d):
                d.items = d.items.map { item in
                    var updated = item
                    updated.blocks = extractBlocks(item.blocks)
                    return updated
                }
                return .dlist(d)
            default:
                return block
            }
        }

        func makeParagraph(_ text: String, roles: [String]) -> AdocParagraph {
            var meta = AdocBlockMeta()
            meta.roles = roles
            return AdocParagraph(text: AdocText(plain: text), meta: meta)
        }

        func addHeaderSlotsIfMissing() {
            if (slots["title"]?.isEmpty ?? true),
               let titleText = document.header?.title?.plain ?? attributeValue("doctitle"),
               !titleText.isEmpty {
                index += 1
                let titlePara = makeParagraph(titleText, roles: ["doc-title"])
                addSlot("title", block: .paragraph(titlePara), order: 0, index: index)
            }

            if (slots["authors"]?.isEmpty ?? true) {
                if let headerAuthors = document.header?.authors, !headerAuthors.isEmpty {
                    for author in headerAuthors {
                        let text = formatAuthor(author)
                        if text.isEmpty { continue }
                        index += 1
                        let authorPara = makeParagraph(text, roles: ["author"])
                        addSlot("authors", block: .paragraph(authorPara), order: 0, index: index)
                    }
                } else if let raw = attributeValue("author"), !raw.isEmpty {
                    index += 1
                    let authorPara = makeParagraph(raw, roles: ["author"])
                    addSlot("authors", block: .paragraph(authorPara), order: 0, index: index)
                }
            }
        }

        let mainBlocks = extractBlocks(document.blocks)
        addHeaderSlotsIfMissing()
        return SlotExtractionResult(
            mainBlocks: mainBlocks,
            slots: slots,
            collections: collections,
            warnings: warnings
        )
    }

    private func blockMeta(_ block: AdocBlock) -> AdocBlockMeta {
        switch block {
        case .section(let s): return s.meta
        case .paragraph(let p): return p.meta
        case .listing(let l): return l.meta
        case .list(let l): return l.meta
        case .dlist(let d): return d.meta
        case .discreteHeading(let h): return h.meta
        case .sidebar(let s): return s.meta
        case .example(let e): return e.meta
        case .quote(let q): return q.meta
        case .open(let o): return o.meta
        case .admonition(let a): return a.meta
        case .verse(let v): return v.meta
        case .literalBlock(let l): return l.meta
        case .table(let t): return t.meta
        case .math(let m): return m.meta
        case .blockMacro(let m): return m.meta
        }
    }

    private func resolveTemplateURL(_ raw: String, relativeTo baseURL: URL?) -> URL {
        let base = baseURL ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return URL(fileURLWithPath: raw, relativeTo: base).standardizedFileURL
    }

    private func isPagedAttributeEnabled(document: AdocDocument) -> Bool {
        if let typed = document.typedAttributes["paged"] {
            return isTruthy(typed)
        }
        if let raw = document.attributes["paged"] {
            return isTruthy(raw)
        }
        return false
    }

    private func pageCSS(from template: XADTemplateDocument) -> String? {
        guard let mastersValue = template.typedAttributes["page.masters"] else { return nil }
        guard case .dictionary(let masters) = mastersValue else { return nil }
        guard case .dictionary(let defaultMaster) = masters["default"] else { return nil }

        let size: String?
        if case .string(let rawSize)? = defaultMaster["size"] {
            size = rawSize
        } else {
            size = nil
        }

        var marginParts: [String] = []
        if case .dictionary(let margins)? = defaultMaster["margins"] {
            let top = stringValue(margins["top"])
            let right = stringValue(margins["right"]) ?? stringValue(margins["outer"])
            let bottom = stringValue(margins["bottom"])
            let left = stringValue(margins["left"]) ?? stringValue(margins["inner"])
            if let top, let right, let bottom, let left {
                marginParts = [top, right, bottom, left]
            }
        }

        guard size != nil || !marginParts.isEmpty else { return nil }
        var lines: [String] = ["@page {"]
        if let size {
            lines.append("  size: \(size);")
        }
        if !marginParts.isEmpty {
            lines.append("  margin: \(marginParts.joined(separator: " "));")
        }
        lines.append("}")
        return lines.joined(separator: "\n")
    }

    private func styleCSS(from template: XADTemplateDocument) -> String? {
        guard let styleValue = template.typedAttributes["style"] else { return nil }
        guard case .dictionary(let style) = styleValue else { return nil }

        var lines: [String] = [":root {"]

        if case .dictionary(let font)? = style["font"] {
            if let body = stringValue(font["body"]) { lines.append("  --xad-font-body: \"\(body)\";") }
            if let heading = stringValue(font["heading"]) { lines.append("  --xad-font-heading: \"\(heading)\";") }
            if let mono = stringValue(font["mono"]) { lines.append("  --xad-font-mono: \"\(mono)\";") }
        }

        if case .dictionary(let size)? = style["size"] {
            if let body = stringValue(size["body"]) { lines.append("  --xad-size-body: \(body);") }
            if let h1 = stringValue(size["h1"]) { lines.append("  --xad-size-h1: \(h1);") }
            if let h2 = stringValue(size["h2"]) { lines.append("  --xad-size-h2: \(h2);") }
        }

        if case .dictionary(let line)? = style["line"] {
            if let leading = stringValue(line["leading"]) { lines.append("  --xad-line-leading: \(leading);") }
        }

        if case .dictionary(let color)? = style["color"] {
            if let text = stringValue(color["text"]) { lines.append("  --xad-color-text: \(text);") }
            if let muted = stringValue(color["muted"]) { lines.append("  --xad-color-muted: \(muted);") }
        }

        guard lines.count > 1 else { return nil }
        lines.append("}")
        return lines.joined(separator: "\n")
    }

    private func formatAuthor(_ author: AdocAuthor) -> String {
        if let fullname = author.fullname, !fullname.isEmpty {
            return appendAddress(fullname, address: author.address)
        }
        let parts = [author.firstname, author.middlename, author.lastname].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if !parts.isEmpty {
            return appendAddress(parts.joined(separator: " "), address: author.address)
        }
        if let initials = author.initials, !initials.isEmpty {
            return appendAddress(initials, address: author.address)
        }
        return ""
    }

    private func appendAddress(_ name: String, address: String?) -> String {
        guard let address, !address.isEmpty else { return name }
        return "\(name) <\(address)>"
    }

    private func stringValue(_ value: XADAttributeValue?) -> String? {
        if case .string(let raw)? = value {
            return raw
        }
        return nil
    }

    private func isTruthy(_ value: XADAttributeValue) -> Bool {
        switch value {
        case .bool(let b):
            return b
        case .number(let n):
            return n != 0
        case .string(let s):
            return isTruthy(s)
        case .null:
            return false
        case .array(let arr):
            return !arr.isEmpty
        case .dictionary(let dict):
            return !dict.isEmpty
        }
    }

    private func isTruthy(_ value: String?) -> Bool {
        guard let value else { return false }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        switch trimmed.lowercased() {
        case "true", "yes", "on", "1":
            return true
        case "false", "no", "off", "0":
            return false
        default:
            return true
        }
    }

    private func renderInlines(_ inlines: [AdocInline], context: InlineContext) -> String {
        inlineRenderer.render(inlines, context: context)
    }

    // Helpers

    private func titlePair(_ text: AdocText?, context: InlineContext) -> (html: String, plain: String) {
        guard let text else {
            return ("", "")
        }
        return (renderInlines(text.inlines, context: context), text.plain)
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

    private func renderTableRows(_ rows: [[AdocTableCell]], defaultHeader: Bool, context: InlineContext) -> [[ [String: Any] ]] {
        rows.map { row in
            row.map { cell in
                let inlines = parseInlines(cell.text, baseSpan: nil)
                let renderedContent = renderInlines(inlines, context: context)
                
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

    private func resolveBlockMacroContext(_ blockMacro: AdocBlockMacro, attributes: [String: String]) -> [String: Any] {
        var context: [String: Any] = [:]
        for resolver in config.blockMacroResolvers {
            guard let resolved = resolver.resolve(blockMacro: blockMacro, attributes: attributes) else {
                continue
            }
            context.merge(resolved, uniquingKeysWith: { _, new in new })
        }
        return context
    }

    private func parseLyrics(target: String, chordsEnabled: Bool) -> (lines: [[String: Any]], hasChords: Bool) {
        let sourceLines = target.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var renderedLines: [[String: Any]] = []
        var hasChords = false

        for line in sourceLines {
            if !chordsEnabled {
                renderedLines.append([
                    "text": line,
                    "chordLine": ""
                ])
                continue
            }

            let parsedLine = parseLyricsLine(line)
            if let chordLine = parsedLine["chordLine"] as? String, !chordLine.trimmingCharacters(in: .whitespaces).isEmpty {
                hasChords = true
            }
            renderedLines.append(parsedLine)
        }

        return (renderedLines, hasChords)
    }

    private func parseLyricsLine(_ line: String) -> [String: Any] {
        var text = ""
        var chords: [[String: Any]] = []
        var index = line.startIndex

        while index < line.endIndex {
            if line[index] == "[" {
                let next = line.index(after: index)
                if let close = line[next...].firstIndex(of: "]") {
                    let chord = String(line[next..<close])
                    chords.append([
                        "name": chord,
                        "column": text.count
                    ])
                    index = line.index(after: close)
                    continue
                }
            }

            text.append(line[index])
            index = line.index(after: index)
        }

        return [
            "text": text,
            "chordLine": buildChordLine(chords: chords)
        ]
    }

    private func buildChordLine(chords: [[String: Any]]) -> String {
        guard !chords.isEmpty else {
            return ""
        }

        var characters: [Character] = []
        var nextFreeColumn = 0

        func ensureCapacity(_ count: Int) {
            if characters.count < count {
                characters.append(contentsOf: Array(repeating: " ", count: count - characters.count))
            }
        }

        for chord in chords {
            guard
                let name = chord["name"] as? String,
                let requestedColumn = chord["column"] as? Int
            else {
                continue
            }

            let startColumn = max(requestedColumn, nextFreeColumn)
            let chordCharacters = Array(name)
            ensureCapacity(startColumn + chordCharacters.count)

            for (offset, character) in chordCharacters.enumerated() {
                characters[startColumn + offset] = character
            }

            nextFreeColumn = startColumn + chordCharacters.count + 1
        }

        while let last = characters.last, last == " " {
            characters.removeLast()
        }

        return String(characters)
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
