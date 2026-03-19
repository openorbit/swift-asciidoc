//
// Copyright (c) 2026 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

import Foundation
import AsciiDocCore

public struct XADTemplateAssets: Sendable, Equatable {
    public var css: [String]
    public var js: [String]

    public init(css: [String] = [], js: [String] = []) {
        self.css = css
        self.js = js
    }
}

public struct XADTemplateDocument: Sendable, Equatable {
    public var url: URL
    public var attributes: [String: String?]
    public var typedAttributes: [String: XADAttributeValue]
    public var layoutProgram: LayoutProgram?
    public var assets: XADTemplateAssets

    public init(
        url: URL,
        attributes: [String: String?],
        typedAttributes: [String: XADAttributeValue],
        layoutProgram: LayoutProgram?,
        assets: XADTemplateAssets
    ) {
        self.url = url
        self.attributes = attributes
        self.typedAttributes = typedAttributes
        self.layoutProgram = layoutProgram
        self.assets = assets
    }
}

public struct XADTemplateIngestor: Sendable {
    public init() {}

    public func ingestTemplate(
        at url: URL,
        xadOptions: XADOptions = .init(enabled: true)
    ) -> (XADTemplateDocument?, [AdocWarning]) {
        var warnings: [AdocWarning] = []
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            warnings.append(AdocWarning(message: "failed to read template: \(error.localizedDescription)", span: nil))
            return (nil, warnings)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            warnings.append(AdocWarning(message: "template must be UTF-8", span: nil))
            return (nil, warnings)
        }

        var options = xadOptions
        options.enabled = true

        let parser = AdocParser()
        let preprocessorOptions = Preprocessor.Options(sourceURL: url)
        let document = parser.parse(
            text: text,
            preprocessorOptions: preprocessorOptions,
            xadOptions: options
        )
        warnings.append(contentsOf: document.warnings)

        let assets = XADTemplateAssets(
            css: parseAssetList(document.attributes["template.css"] ?? nil),
            js: parseAssetList(document.attributes["template.js"] ?? nil)
        )

        let program = extractLayoutProgram(from: document.blocks, warnings: &warnings)
        let template = XADTemplateDocument(
            url: url,
            attributes: document.attributes,
            typedAttributes: document.typedAttributes,
            layoutProgram: program,
            assets: assets
        )
        return (template, warnings)
    }
}

private func parseAssetList(_ raw: String?) -> [String] {
    guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
        return []
    }
    if raw.contains(",") {
        return raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
    return raw
        .split(whereSeparator: { $0.isWhitespace })
        .map(String.init)
        .filter { !$0.isEmpty }
}

private func extractLayoutProgram(
    from blocks: [AdocBlock],
    warnings: inout [AdocWarning]
) -> LayoutProgram? {
    var programs: [LayoutProgram] = []

    func visit(_ blocks: [AdocBlock]) {
        for block in blocks {
            if let source = layoutSource(from: block) {
                let parser = LayoutDSLParser()
                let (program, parserWarnings) = parser.parse(text: source.text, span: source.span)
                warnings.append(contentsOf: parserWarnings)
                if let program {
                    programs.append(program)
                } else {
                    warnings.append(
                        AdocWarning(message: "layout block did not produce a layout program", span: source.span)
                    )
                }
            }

            switch block {
            case .section(let section):
                visit(section.blocks)
            case .sidebar(let sidebar):
                visit(sidebar.blocks)
            case .example(let example):
                visit(example.blocks)
            case .quote(let quote):
                visit(quote.blocks)
            case .open(let open):
                visit(open.blocks)
            case .admonition(let admonition):
                visit(admonition.blocks)
            case .verse(let verse):
                visit(verse.blocks)
            case .list(let list):
                for item in list.items {
                    visit(item.blocks)
                }
            case .dlist(let dlist):
                for item in dlist.items {
                    visit(item.blocks)
                }
            default:
                break
            }
        }
    }

    visit(blocks)

    if programs.isEmpty {
        warnings.append(AdocWarning(message: "template did not contain a [layout] block", span: nil))
        return nil
    }
    if programs.count > 1 {
        warnings.append(AdocWarning(message: "template contains multiple [layout] blocks; using the first one", span: nil))
    }
    return programs.first
}

private func layoutSource(from block: AdocBlock) -> (text: String, span: AdocRange?)? {
    switch block {
    case .listing(let listing):
        if isLayoutStyle(listing.meta) {
            return (listing.text.plain, listing.span)
        }
    case .literalBlock(let literal):
        if isLayoutStyle(literal.meta) {
            return (literal.text.plain, literal.span)
        }
    default:
        break
    }
    return nil
}

private func isLayoutStyle(_ meta: AdocBlockMeta) -> Bool {
    if let style = meta.attributes["style"]?.trimmingCharacters(in: .whitespacesAndNewlines),
       style.lowercased() == "layout" {
        return true
    }
    if let positional = meta.attributes["1"]?.trimmingCharacters(in: .whitespacesAndNewlines),
       positional.lowercased() == "layout" {
        return true
    }
    return false
}
