//
// Copyright (c) 2025 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

import AsciiDocCore

public struct LatexEnvironmentExtension: AsciiDocExtension {
    public let name = "latex"

    private let supportedStyles: Set<String>

    public init(
        styles: [String] = [
            "theorem",
            "conjecture",
            "lemma",
            "definition",
            "proposition",
            "corollary",
            "criterion",
            "algorithm",
            "condition",
            "problem",
            "claim",
            "conclusion",
            "case"
        ]
    ) {
        self.supportedStyles = Set(styles.map { $0.lowercased() })
    }

    public func didParse(document: AdocDocument) -> AdocDocument {
        var copy = document
        copy.blocks = transform(blocks: copy.blocks)
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
            if let environment = convertParagraph(paragraph) {
                return environment
            }
            return .paragraph(paragraph)

        default:
            return block
        }
    }

    private func convertParagraph(_ paragraph: AdocParagraph) -> AdocBlock? {
        guard let style = paragraph.meta.attributes["style"]?.lowercased(),
              supportedStyles.contains(style) else {
            return nil
        }

        var environmentParagraph = paragraph
        environmentParagraph.meta.attributes["latex-environment"] = style
        environmentParagraph.meta.attributes.removeValue(forKey: "style")
        environmentParagraph.meta.attributes.removeValue(forKey: "1")

        return .paragraph(environmentParagraph)
    }
}
