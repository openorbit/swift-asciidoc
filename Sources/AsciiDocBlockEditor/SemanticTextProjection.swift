//
// Copyright (c) 2025 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

import AsciiDocCore
import Foundation

struct AdocProjectedField: Equatable, Sendable {
    var key: AsciiDocEditorFieldKey
    var range: NSRange
}

struct AdocSemanticTextProjection {
    var attributedString: NSAttributedString
    var fields: [AdocProjectedField]

    func field(containing range: NSRange) -> AdocProjectedField? {
        fields.first { field in
            range.location >= field.range.location && NSMaxRange(range) <= NSMaxRange(field.range)
        }
    }

    func range(for key: AsciiDocEditorFieldKey) -> NSRange? {
        fields.first(where: { $0.key == key })?.range
    }

    func firstRange(inBlock blockIndex: Int) -> NSRange? {
        fields.first(where: { $0.key.blockIndex == blockIndex })?.range
    }
}

enum AdocSemanticProjectionBuilder {
    static func make(document: AsciiDocEditorDocument) -> AdocSemanticTextProjection {
        let result = NSMutableAttributedString(string: "")
        var fields: [AdocProjectedField] = []

        if !document.title.isEmpty {
            appendSemanticField(
                document: document,
                key: .init(blockIndex: -1, path: "title"),
                style: .title,
                to: result,
                fields: &fields
            )
            appendSeparator(to: result, count: 2)
        }

        for blockIndex in document.blocks.indices {
            appendBlock(
                document: document,
                blockIndex: blockIndex,
                to: result,
                fields: &fields
            )
            if blockIndex != document.blocks.indices.last {
                appendSeparator(to: result, count: 2)
            }
        }

        if result.length == 0 {
            result.append(NSAttributedString(string: ""))
        }

        return AdocSemanticTextProjection(attributedString: result, fields: fields)
    }

    private static func appendBlock(
        document: AsciiDocEditorDocument,
        blockIndex: Int,
        to result: NSMutableAttributedString,
        fields: inout [AdocProjectedField]
    ) {
        let kind = document.blockKind(at: blockIndex)
        switch kind {
        case .heading:
            let level = document.headingLevel(at: blockIndex) ?? 1
            let key = AsciiDocEditorFieldKey(blockIndex: blockIndex, path: "text")
            appendSemanticField(document: document, key: key, style: .heading(level), to: result, fields: &fields)

        case .paragraph:
            appendPrimaryText(document: document, blockIndex: blockIndex, style: .body, to: result, fields: &fields)

        case .listing:
            appendPrimaryText(document: document, blockIndex: blockIndex, style: .code, to: result, fields: &fields)

        case .verse:
            appendPrimaryText(document: document, blockIndex: blockIndex, style: .verse, to: result, fields: &fields)

        case .equation:
            appendGenerated("Equation\n", style: .label, to: result)
            appendPrimaryText(document: document, blockIndex: blockIndex, style: .code, to: result, fields: &fields)

        case .admonition:
            let label = document.admonitionKind(at: blockIndex)?.title.uppercased() ?? "NOTE"
            appendGenerated("\(label)  ", style: .label, to: result)
            appendPrimaryText(document: document, blockIndex: blockIndex, style: .body, to: result, fields: &fields)

        case .unorderedList, .orderedList:
            for itemIndex in 0..<document.itemCount(at: blockIndex) {
                if itemIndex > 0 { appendSeparator(to: result, count: 1) }
                let marker = kind == .orderedList ? "\(itemIndex + 1).\t" : "•\t"
                appendGenerated(marker, style: .listMarker, to: result)
                let key = AsciiDocEditorFieldKey(blockIndex: blockIndex, path: "item:\(itemIndex)")
                appendSemanticField(document: document, key: key, style: .body, to: result, fields: &fields)
            }

        case .descriptionList:
            for itemIndex in 0..<document.itemCount(at: blockIndex) {
                if itemIndex > 0 { appendSeparator(to: result, count: 1) }
                let term = AsciiDocEditorFieldKey(blockIndex: blockIndex, path: "term:\(itemIndex):value")
                let definition = AsciiDocEditorFieldKey(blockIndex: blockIndex, path: "definition:\(itemIndex):value")
                appendSemanticField(document: document, key: term, style: .term, to: result, fields: &fields)
                appendGenerated("\t", style: .body, to: result)
                appendSemanticField(document: document, key: definition, style: .body, to: result, fields: &fields)
            }

        case .table:
            appendTable(document: document, blockIndex: blockIndex, to: result, fields: &fields)

        case .none:
            appendGenerated("Unsupported block", style: .label, to: result)
        }
    }

    private static func appendPrimaryText(
        document: AsciiDocEditorDocument,
        blockIndex: Int,
        style: ProjectionStyle,
        to result: NSMutableAttributedString,
        fields: inout [AdocProjectedField]
    ) {
        let key = AsciiDocEditorFieldKey(blockIndex: blockIndex, path: "text")
        if document.semanticText(for: key) != nil {
            appendSemanticField(document: document, key: key, style: style, to: result, fields: &fields)
        } else {
            appendField(document.text(for: key) ?? "", key: key, style: style, to: result, fields: &fields)
        }
    }

    private static func appendSemanticField(
        document: AsciiDocEditorDocument,
        key: AsciiDocEditorFieldKey,
        style: ProjectionStyle,
        to result: NSMutableAttributedString,
        fields: inout [AdocProjectedField]
    ) {
        guard let semanticText = document.semanticText(for: key) else {
            appendField(document.text(for: key) ?? "", key: key, style: style, to: result, fields: &fields)
            return
        }

        let location = result.length
        let projected = NSMutableAttributedString(string: "")
        appendInlineNodes(semanticText.inlines, baseStyle: style, to: projected)
        result.append(projected)
        fields.append(AdocProjectedField(key: key, range: NSRange(location: location, length: projected.length)))
    }

    private static func appendInlineNodes(
        _ nodes: [AdocInline],
        baseStyle: ProjectionStyle,
        to result: NSMutableAttributedString
    ) {
        for node in nodes {
            let start = result.length
            switch node {
            case .text(let value, _), .passthrough(let value, _):
                result.append(NSAttributedString(string: value, attributes: baseStyle.attributes))
            case .strong(let children, _), .emphasis(let children, _), .mono(let children, _),
                 .mark(let children, _), .superscript(let children, _), .subscript(let children, _):
                appendInlineNodes(children, baseStyle: baseStyle, to: result)
            case .link(_, let children, _), .xref(_, let children, _):
                appendInlineNodes(children, baseStyle: baseStyle, to: result)
            case .math(_, let body, _, _):
                result.append(NSAttributedString(string: body, attributes: ProjectionStyle.code.attributes))
            case .inlineMacro(let name, let target, let body, _):
                let visible = !body.isEmpty ? body : (target ?? name)
                result.append(NSAttributedString(string: visible, attributes: baseStyle.attributes))
            case .footnote(let children, _, _, _):
                appendInlineNodes(children, baseStyle: baseStyle, to: result)
            case .indexTerm(let terms, let visible, _):
                if visible { result.append(NSAttributedString(string: terms.first ?? "", attributes: baseStyle.attributes)) }
            }

            let range = NSRange(location: start, length: result.length - start)
            applyInlineDecoration(for: node, range: range, to: result)
        }
    }

    private static func applyInlineDecoration(
        for node: AdocInline,
        range: NSRange,
        to result: NSMutableAttributedString
    ) {
        guard range.length > 0 else { return }
        switch node {
        case .strong:
            applyFontTrait(.bold, range: range, to: result)
        case .emphasis:
            applyFontTrait(.italic, range: range, to: result)
        case .mono:
            applyMonospacedFont(range: range, to: result)
        case .mark:
            #if canImport(AppKit)
            result.addAttribute(.backgroundColor, value: NSColor.systemYellow.withAlphaComponent(0.35), range: range)
            #elseif canImport(UIKit)
            result.addAttribute(.backgroundColor, value: UIColor.systemYellow.withAlphaComponent(0.35), range: range)
            #endif
        case .link(let target, _, _):
            result.addAttribute(.link, value: target, range: range)
        case .xref(let target, _, _):
            result.addAttribute(.link, value: target.raw, range: range)
        case .superscript:
            result.addAttribute(.baselineOffset, value: 4, range: range)
        case .subscript:
            result.addAttribute(.baselineOffset, value: -3, range: range)
        default:
            break
        }
    }

    private enum FontTrait { case bold, italic }

    private static func applyFontTrait(_ trait: FontTrait, range: NSRange, to result: NSMutableAttributedString) {
        result.enumerateAttribute(.font, in: range) { value, subrange, _ in
            #if canImport(AppKit)
            guard let font = value as? NSFont else { return }
            let mask: NSFontTraitMask = trait == .bold ? .boldFontMask : .italicFontMask
            result.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: mask), range: subrange)
            #elseif canImport(UIKit)
            guard let font = value as? UIFont else { return }
            let symbolic: UIFontDescriptor.SymbolicTraits = trait == .bold ? .traitBold : .traitItalic
            guard let descriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(symbolic)) else { return }
            result.addAttribute(.font, value: UIFont(descriptor: descriptor, size: font.pointSize), range: subrange)
            #endif
        }
    }

    private static func applyMonospacedFont(range: NSRange, to result: NSMutableAttributedString) {
        result.enumerateAttribute(.font, in: range) { value, subrange, _ in
            #if canImport(AppKit)
            let size = (value as? NSFont)?.pointSize ?? NSFont.systemFontSize
            result.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: size, weight: .regular), range: subrange)
            #elseif canImport(UIKit)
            let size = (value as? UIFont)?.pointSize ?? UIFont.preferredFont(forTextStyle: .body).pointSize
            result.addAttribute(.font, value: UIFont.monospacedSystemFont(ofSize: size, weight: .regular), range: subrange)
            #endif
        }
    }

    private static func appendTable(
        document: AsciiDocEditorDocument,
        blockIndex: Int,
        to result: NSMutableAttributedString,
        fields: inout [AdocProjectedField]
    ) {
        guard case .table(let table) = document.blocks[blockIndex] else { return }

        #if canImport(AppKit)
        appendAppKitTable(table, blockIndex: blockIndex, to: result, fields: &fields)
        #else
        for rowIndex in table.rows.indices {
            if rowIndex > 0 { appendSeparator(to: result, count: 1) }
            for columnIndex in table.rows[rowIndex].cells.indices {
                if columnIndex > 0 { appendGenerated("\t", style: .table, to: result) }
                let key = AsciiDocEditorFieldKey(blockIndex: blockIndex, path: "cell:\(rowIndex):\(columnIndex)")
                appendField(
                    table.rows[rowIndex].cells[columnIndex].text,
                    key: key,
                    style: .table,
                    to: result,
                    fields: &fields
                )
            }
        }
        #endif
    }

    #if canImport(AppKit)
    private static func appendAppKitTable(
        _ model: AdocTable,
        blockIndex: Int,
        to result: NSMutableAttributedString,
        fields: inout [AdocProjectedField]
    ) {
        let nativeTable = NSTextTable()
        nativeTable.numberOfColumns = max(1, model.rows.map { row in
            row.cells.reduce(0) { $0 + max(1, $1.columnSpan) }
        }.max() ?? 1)
        nativeTable.layoutAlgorithm = .automaticLayoutAlgorithm
        nativeTable.collapsesBorders = true
        nativeTable.hidesEmptyCells = false

        for rowIndex in model.rows.indices {
            var startingColumn = 0
            for columnIndex in model.rows[rowIndex].cells.indices {
                let cell = model.rows[rowIndex].cells[columnIndex]
                let block = NSTextTableBlock(
                    table: nativeTable,
                    startingRow: rowIndex,
                    rowSpan: max(1, cell.rowSpan),
                    startingColumn: startingColumn,
                    columnSpan: max(1, cell.columnSpan)
                )
                block.setWidth(6, type: .absoluteValueType, for: .padding)
                block.setWidth(0.5, type: .absoluteValueType, for: .border)
                block.setBorderColor(.separatorColor)
                if model.rows[rowIndex].isHeader || cell.style == .header {
                    block.backgroundColor = NSColor.controlBackgroundColor
                }

                let paragraph = NSMutableParagraphStyle()
                paragraph.textBlocks = [block]
                paragraph.paragraphSpacing = 0
                let attributes = ProjectionStyle.table.attributes.merging([.paragraphStyle: paragraph]) { _, new in new }
                let key = AsciiDocEditorFieldKey(blockIndex: blockIndex, path: "cell:\(rowIndex):\(columnIndex)")
                appendField(
                    cell.text,
                    key: key,
                    style: .table,
                    attributes: attributes,
                    to: result,
                    fields: &fields
                )
                appendGenerated("\n", attributes: attributes, to: result)
                startingColumn += max(1, cell.columnSpan)
            }
        }
    }
    #endif

    private static func appendField(
        _ text: String,
        key: AsciiDocEditorFieldKey,
        style: ProjectionStyle,
        attributes: [NSAttributedString.Key: Any]? = nil,
        to result: NSMutableAttributedString,
        fields: inout [AdocProjectedField]
    ) {
        let location = result.length
        result.append(NSAttributedString(string: text, attributes: attributes ?? style.attributes))
        fields.append(AdocProjectedField(key: key, range: NSRange(location: location, length: (text as NSString).length)))
    }

    private static func appendGenerated(_ text: String, style: ProjectionStyle, to result: NSMutableAttributedString) {
        result.append(NSAttributedString(string: text, attributes: style.attributes))
    }

    private static func appendGenerated(
        _ text: String,
        attributes: [NSAttributedString.Key: Any],
        to result: NSMutableAttributedString
    ) {
        result.append(NSAttributedString(string: text, attributes: attributes))
    }

    private static func appendSeparator(to result: NSMutableAttributedString, count: Int) {
        appendGenerated(String(repeating: "\n", count: count), style: .body, to: result)
    }
}

private enum ProjectionStyle {
    case title
    case heading(Int)
    case body
    case code
    case verse
    case label
    case listMarker
    case term
    case table

    var attributes: [NSAttributedString.Key: Any] {
        #if canImport(AppKit)
        importAttributes(
            font: appKitFont,
            foreground: NSColor.labelColor,
            paragraph: paragraphStyle
        )
        #elseif canImport(UIKit)
        importAttributes(
            font: uiKitFont,
            foreground: UIColor.label,
            paragraph: paragraphStyle
        )
        #else
        [:]
        #endif
    }

    private var paragraphStyle: NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = spacing
        paragraph.lineSpacing = 2
        return paragraph
    }

    private var spacing: CGFloat {
        switch self {
        case .title: return 12
        case .heading: return 8
        default: return 3
        }
    }

    #if canImport(AppKit)
    private var appKitFont: NSFont {
        switch self {
        case .title: return .systemFont(ofSize: 30, weight: .bold)
        case .heading(let level): return .systemFont(ofSize: max(17, 27 - CGFloat(level * 2)), weight: .semibold)
        case .code: return .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        case .label, .listMarker: return .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        case .term: return .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        default: return .preferredFont(forTextStyle: .body)
        }
    }
    #elseif canImport(UIKit)
    private var uiKitFont: UIFont {
        switch self {
        case .title: return .preferredFont(forTextStyle: .largeTitle)
        case .heading(let level):
            return .preferredFont(forTextStyle: level <= 1 ? .title1 : level == 2 ? .title2 : .title3)
        case .code: return .monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize, weight: .regular)
        case .label, .listMarker: return .preferredFont(forTextStyle: .caption1)
        case .term: return .preferredFont(forTextStyle: .headline)
        default: return .preferredFont(forTextStyle: .body)
        }
    }
    #endif

    private func importAttributes(font: Any, foreground: Any, paragraph: NSParagraphStyle) -> [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: foreground, .paragraphStyle: paragraph]
    }
}

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
