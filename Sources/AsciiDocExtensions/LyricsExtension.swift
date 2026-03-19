//
// Copyright (c) 2025 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

import Foundation
import AsciiDocCore

public struct LyricsExtension: AsciiDocExtension {
    public let name = "lyrics"

    public init() {}

    public func didParse(document: AdocDocument) -> AdocDocument {
        var copy = document
        copy.blocks = transform(blocks: document.blocks)
        return copy
    }

    private func transform(blocks: [AdocBlock]) -> [AdocBlock] {
        blocks.map(transform(block:))
    }

    private func transform(block: AdocBlock) -> AdocBlock {
        switch block {
        case .section(var section):
            section.blocks = transform(blocks: section.blocks)
            return .section(section)
        case .list(var list):
            list.items = list.items.map { item in
                var copy = item
                copy.blocks = transform(blocks: copy.blocks)
                return copy
            }
            return .list(list)
        case .dlist(var dlist):
            dlist.items = dlist.items.map { item in
                var copy = item
                copy.blocks = transform(blocks: copy.blocks)
                return copy
            }
            return .dlist(dlist)
        case .sidebar(var sidebar):
            sidebar.blocks = transform(blocks: sidebar.blocks)
            return .sidebar(sidebar)
        case .example(var example):
            example.blocks = transform(blocks: example.blocks)
            return .example(example)
        case .quote(var quote):
            quote.blocks = transform(blocks: quote.blocks)
            return .quote(quote)
        case .open(var open):
            open.blocks = transform(blocks: open.blocks)
            return .open(open)
        case .admonition(var admonition):
            admonition.blocks = transform(blocks: admonition.blocks)
            return .admonition(admonition)
        case .verse(var verse):
            verse.blocks = transform(blocks: verse.blocks)
            return .verse(verse)
        case .paragraph(let paragraph):
            if let converted = convertLyricsTextBlock(
                text: paragraph.text,
                title: paragraph.title,
                reftext: paragraph.reftext,
                meta: paragraph.meta,
                span: paragraph.span
            ) {
                return converted
            }
            return .paragraph(paragraph)
        case .listing(let listing):
            if let converted = convertLyricsTextBlock(
                text: listing.text,
                title: listing.title,
                reftext: listing.reftext,
                meta: listing.meta,
                span: listing.span
            ) {
                return converted
            }
            return .listing(listing)
        case .literalBlock(let literal):
            if let converted = convertLyricsTextBlock(
                text: literal.text,
                title: literal.title,
                reftext: literal.reftext,
                meta: literal.meta,
                span: literal.span
            ) {
                return converted
            }
            return .literalBlock(literal)
        case .math, .table, .discreteHeading, .blockMacro:
            return block
        }
    }

    private func convertLyricsTextBlock(
        text: AdocText,
        title: AdocText?,
        reftext: AdocText?,
        meta: AdocBlockMeta,
        span: AdocRange?
    ) -> AdocBlock? {
        guard meta.attributes["style"]?.lowercased() == "lyrics" else {
            return nil
        }

        var normalizedMeta = meta
        let positionalFlags = Set(
            normalizedMeta.attributes
                .filter { Int($0.key) != nil }
                .map { $0.value.lowercased() }
        )
        normalizedMeta.attributes.removeValue(forKey: "style")
        normalizedMeta.attributes.removeValue(forKey: "1")
        normalizedMeta.attributes.removeValue(forKey: "2")

        if normalizedMeta.options.contains("chords") || positionalFlags.contains("chords") {
            normalizedMeta.attributes["chords"] = "true"
        }

        let macro = AdocBlockMacro(
            name: "lyrics",
            target: text.plain,
            attributes: [:],
            id: meta.id,
            title: title,
            reftext: reftext,
            meta: normalizedMeta,
            span: span
        )
        return .blockMacro(macro)
    }
}
