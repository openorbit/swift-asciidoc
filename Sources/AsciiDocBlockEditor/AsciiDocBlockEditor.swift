//
// Copyright (c) 2025 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

import AsciiDocCore
import Foundation

public struct AsciiDocEditorDocument: Equatable, Sendable {
    public var ism: AdocDocument

    public init(ism: AdocDocument = .init()) {
        self.ism = ism
    }

    public init(asciiDoc: String) {
        self.ism = AdocParser().parse(text: asciiDoc)
    }

    public var title: String {
        get { ism.header?.title?.plain ?? "" }
        set {
            if ism.header == nil {
                ism.header = AdocHeader()
            }
            ism.header?.title = newValue.isEmpty ? nil : AdocText(plain: newValue)
        }
    }

    public var blocks: [AdocBlock] {
        get { ism.blocks }
        set { ism.blocks = newValue }
    }

    public var warnings: [AdocWarning] { ism.warnings }

    public func asciiDocSource() -> String {
        ism.renderAsAsciiDoc()
    }

    public func blockKind(at index: Int) -> AsciiDocEditorBlockKind? {
        guard blocks.indices.contains(index) else { return nil }
        switch blocks[index] {
        case .section, .discreteHeading: return .heading
        case .paragraph: return .paragraph
        case .listing, .literalBlock: return .listing
        case .verse: return .verse
        case .list(let list):
            switch list.kind {
            case .ordered: return .orderedList
            case .unordered, .callout: return .unorderedList
            }
        case .dlist: return .descriptionList
        case .math: return .equation
        case .table: return .table
        case .admonition, .quote, .example, .sidebar, .open: return .admonition
        case .blockMacro: return nil
        }
    }

    public mutating func appendBlock(kind: AsciiDocEditorBlockKind) {
        ism.blocks.append(kind.makeBlock())
    }

    public mutating func removeBlock(at index: Int) {
        guard ism.blocks.indices.contains(index) else { return }
        ism.blocks.remove(at: index)
    }

    public func text(for key: AsciiDocEditorFieldKey) -> String? {
        if key.blockIndex == -1, key.path == "title" { return title }
        guard blocks.indices.contains(key.blockIndex) else { return nil }
        return blocks[key.blockIndex].text(for: key.path)
    }

    public mutating func updateText(_ text: String, for key: AsciiDocEditorFieldKey) {
        if key.blockIndex == -1, key.path == "title" {
            title = text
            return
        }
        guard ism.blocks.indices.contains(key.blockIndex) else { return }
        ism.blocks[key.blockIndex].updateText(text, for: key.path)
    }

    func semanticText(for key: AsciiDocEditorFieldKey) -> AdocText? {
        if key.blockIndex == -1, key.path == "title" { return ism.header?.title }
        guard blocks.indices.contains(key.blockIndex) else { return nil }
        return blocks[key.blockIndex].semanticText(for: key.path)
    }

    mutating func replaceSemanticText(
        for key: AsciiDocEditorFieldKey,
        in visibleRange: NSRange,
        with replacement: String
    ) -> Bool {
        guard var text = semanticText(for: key) else { return false }
        let preserved = text.replaceVisibleText(in: visibleRange, with: replacement)

        if key.blockIndex == -1, key.path == "title" {
            if ism.header == nil { ism.header = AdocHeader() }
            ism.header?.title = text
            return preserved
        }

        guard ism.blocks.indices.contains(key.blockIndex) else { return false }
        ism.blocks[key.blockIndex].setSemanticText(text, for: key.path)
        return preserved
    }

    @discardableResult
    public mutating func applySemanticInline(
        _ markup: AsciiDocInlineMarkup,
        to key: AsciiDocEditorFieldKey,
        visibleRange: NSRange
    ) -> Bool {
        guard visibleRange.length > 0, var text = semanticText(for: key),
              text.wrapVisibleText(in: visibleRange, with: markup) else { return false }

        if key.blockIndex == -1, key.path == "title" {
            if ism.header == nil { ism.header = AdocHeader() }
            ism.header?.title = text
            return true
        }

        guard ism.blocks.indices.contains(key.blockIndex) else { return false }
        ism.blocks[key.blockIndex].setSemanticText(text, for: key.path)
        return true
    }

    public func headingLevel(at index: Int) -> Int? {
        guard blocks.indices.contains(index) else { return nil }
        switch blocks[index] {
        case .section(let section): return section.level
        case .discreteHeading(let heading): return heading.level
        default: return nil
        }
    }

    public mutating func setHeadingLevel(_ level: Int, at index: Int) {
        guard ism.blocks.indices.contains(index) else { return }
        ism.blocks[index].setHeadingLevel(level)
    }

    public func admonitionKind(at index: Int) -> AsciiDocAdmonitionKind? {
        guard blocks.indices.contains(index) else { return nil }
        return blocks[index].admonitionKind
    }

    public mutating func setAdmonitionKind(_ kind: AsciiDocAdmonitionKind, at index: Int) {
        guard ism.blocks.indices.contains(index) else { return }
        ism.blocks[index].setAdmonitionKind(kind)
    }

    public func itemCount(at index: Int) -> Int {
        guard blocks.indices.contains(index) else { return 0 }
        switch blocks[index] {
        case .list(let list): return list.items.count
        case .dlist(let list): return list.items.count
        default: return 0
        }
    }

    public mutating func appendListItem(at index: Int) {
        guard ism.blocks.indices.contains(index) else { return }
        ism.blocks[index].appendListItem()
    }

    public func tableRows(at index: Int) -> [[String]] {
        guard blocks.indices.contains(index) else { return [] }
        guard case .table(let table) = blocks[index] else { return [] }
        return Self.parseTableRows(from: table)
    }

    public mutating func appendTableRow(at index: Int) {
        guard ism.blocks.indices.contains(index) else { return }
        ism.blocks[index].appendTableRow()
    }

    public mutating func appendTableColumn(at index: Int) {
        guard ism.blocks.indices.contains(index) else { return }
        ism.blocks[index].appendTableColumn()
    }

    public func canTransformBlock(at index: Int, to kind: AsciiDocEditorBlockKind) -> Bool {
        guard ism.blocks.indices.contains(index) else { return false }
        return ism.blocks[index].canTransform(to: kind)
    }

    public mutating func transformBlock(at index: Int, to kind: AsciiDocEditorBlockKind) {
        guard ism.blocks.indices.contains(index) else { return }
        ism.blocks[index].transform(to: kind)
    }

    @discardableResult
    public mutating func applyInlineMarkup(
        _ markup: AsciiDocInlineMarkup,
        to key: AsciiDocEditorFieldKey,
        selection: Range<String.Index>?
    ) -> Range<String.Index>? {
        guard let text = text(for: key) else { return nil }
        let applied = markup.applying(to: text, selection: selection)
        updateText(applied.text, for: key)
        return applied.selection
    }
}

public struct AsciiDocEditorFieldKey: Hashable, Sendable {
    public let blockIndex: Int
    public let path: String

    public init(blockIndex: Int, path: String) {
        self.blockIndex = blockIndex
        self.path = path
    }
}

public struct AsciiDocEditorSelection: Equatable, Sendable {
    public var field: AsciiDocEditorFieldKey
    public var range: NSRange

    public init(field: AsciiDocEditorFieldKey, range: NSRange) {
        self.field = field
        self.range = range
    }
}

public enum AsciiDocInlineMarkup: String, CaseIterable, Identifiable, Sendable {
    case emphasis
    case strong
    case code
    case mark
    case subscriptText
    case superscriptText

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .emphasis: return "Emphasis"
        case .strong: return "Strong"
        case .code: return "Code"
        case .mark: return "Mark"
        case .subscriptText: return "Subscript"
        case .superscriptText: return "Superscript"
        }
    }

    public var symbol: String {
        switch self {
        case .emphasis: return "italic"
        case .strong: return "bold"
        case .code: return "curlybraces"
        case .mark: return "highlighter"
        case .subscriptText: return "textformat.subscript"
        case .superscriptText: return "textformat.superscript"
        }
    }

    fileprivate var delimiter: String {
        switch self {
        case .emphasis: return "_"
        case .strong: return "*"
        case .code: return "`"
        case .mark: return "#"
        case .subscriptText: return "~"
        case .superscriptText: return "^"
        }
    }

    func wrapping(_ children: [AdocInline]) -> AdocInline {
        switch self {
        case .emphasis: return .emphasis(children, span: nil)
        case .strong: return .strong(children, span: nil)
        case .code: return .mono(children, span: nil)
        case .mark: return .mark(children, span: nil)
        case .subscriptText: return .subscript(children, span: nil)
        case .superscriptText: return .superscript(children, span: nil)
        }
    }

    fileprivate func applying(to text: String, selection: Range<String.Index>?) -> (text: String, selection: Range<String.Index>) {
        let range = selection ?? text.endIndex..<text.endIndex
        let replacement = "\(delimiter)\(text[range])\(delimiter)"
        let updated = text.replacingCharacters(in: range, with: replacement)
        let start = updated.index(range.lowerBound, offsetBy: delimiter.count)
        let end = updated.index(start, offsetBy: text.distance(from: range.lowerBound, to: range.upperBound))
        return (updated, start..<end)
    }
}

public enum AsciiDocEditorBlockKind: String, CaseIterable, Identifiable, Sendable {
    case heading
    case paragraph
    case unorderedList
    case orderedList
    case descriptionList
    case listing
    case verse
    case equation
    case table
    case admonition

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .heading: return "Heading"
        case .paragraph: return "Paragraph"
        case .unorderedList: return "Unordered List"
        case .orderedList: return "Ordered List"
        case .descriptionList: return "Description List"
        case .listing: return "Listing"
        case .verse: return "Verse"
        case .equation: return "Equation"
        case .table: return "Table"
        case .admonition: return "Admonition"
        }
    }

    fileprivate func makeBlock() -> AdocBlock {
        switch self {
        case .heading:
            return .section(AdocSection(level: 1, title: AdocText(plain: "New section")))
        case .paragraph:
            return .paragraph(AdocParagraph(text: AdocText(plain: "Write here")))
        case .unorderedList:
            return .list(AdocList(
                kind: .unordered(marker: "*"),
                items: [
                    AdocListItem(marker: "*", principal: AdocText(plain: "First item")),
                    AdocListItem(marker: "*", principal: AdocText(plain: "Second item"))
                ]
            ))
        case .orderedList:
            return .list(AdocList(
                kind: .ordered(marker: "."),
                items: [
                    AdocListItem(marker: ".", principal: AdocText(plain: "First step")),
                    AdocListItem(marker: ".", principal: AdocText(plain: "Second step"))
                ]
            ))
        case .descriptionList:
            return .dlist(AdocDList(
                items: [
                    AdocDListItem(term: AdocText(plain: "Term"), principal: AdocText(plain: "Definition"))
                ]
            ))
        case .listing:
            return .listing(AdocListing(text: AdocText(plain: "let answer = 42")))
        case .verse:
            return .verse(AdocVerse(text: AdocText(plain: "A line of verse")))
        case .equation:
            return .math(AdocMathBlock(kind: .latex, body: "E = mc^2", display: true))
        case .table:
            return .table(AdocTable(rows: [
                "| Column A | Column B",
                "| Value 1 | Value 2"
            ]))
        case .admonition:
            return .admonition(AdocAdmonition(
                kind: "note",
                blocks: [.paragraph(AdocParagraph(text: AdocText(plain: "Capture structured notes here.")))]
            ))
        }
    }
}

public enum AsciiDocAdmonitionKind: String, CaseIterable, Identifiable, Sendable {
    case note
    case tip
    case warning
    case caution
    case important
    case quote
    case example
    case sidebar
    case open

    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

public extension AsciiDocEditorDocument {
    static let sample = AsciiDocEditorDocument(
        ism: AdocDocument(
            header: AdocHeader(title: AdocText(plain: "Structured AsciiDoc Editing")),
            blocks: [
                .paragraph(AdocParagraph(text: AdocText(plain: "This editor now edits the ISM directly, so the structural view is the source of truth."))),
                .section(AdocSection(level: 1, title: AdocText(plain: "Inline formatting"))),
                .paragraph(AdocParagraph(text: AdocText(plain: "Select text and use the toolbar for *strong*, _emphasis_, `code`, and #mark#."))),
                .list(AdocList(
                    kind: .unordered(marker: "*"),
                    items: [
                        AdocListItem(marker: "*", principal: AdocText(plain: "WYSIWYM means the block structure is what you edit")),
                        AdocListItem(marker: "*", principal: AdocText(plain: "No rendered preview is required for the basic workflow"))
                    ]
                )),
                .section(AdocSection(level: 1, title: AdocText(plain: "Tables and equations"))),
                .table(AdocTable(rows: [
                    "| Feature | State",
                    "| ISM editing | Direct",
                    "| Equations | Stem blocks"
                ])),
                .math(AdocMathBlock(kind: .latex, body: "\\int_a^b f(x) dx", display: true)),
                .admonition(AdocAdmonition(
                    kind: "note",
                    blocks: [.paragraph(AdocParagraph(text: AdocText(plain: "The editor UI is a structural authoring surface over ISM, not a preview pane.")))]
                ))
            ]
        )
    )
}

private extension AdocBlock {
    func semanticText(for path: String) -> AdocText? {
        switch self {
        case .section(let value) where path == "text": return value.title
        case .discreteHeading(let value) where path == "text": return value.title
        case .paragraph(let value) where path == "text": return value.text
        case .listing(let value) where path == "text": return value.text
        case .literalBlock(let value) where path == "text": return value.text
        case .verse(let value) where path == "text": return value.text
        case .list(let value):
            guard path.hasPrefix("item:"), let index = Int(path.split(separator: ":").last ?? ""),
                  value.items.indices.contains(index) else { return nil }
            return value.items[index].principal
        case .dlist(let value):
            let parts = path.split(separator: ":")
            guard parts.count == 3, let index = Int(parts[1]), value.items.indices.contains(index) else { return nil }
            if parts[0] == "term" { return value.items[index].term }
            if parts[0] == "definition" { return value.items[index].principal }
            return nil
        default: return nil
        }
    }

    mutating func setSemanticText(_ text: AdocText, for path: String) {
        switch self {
        case .section(var value) where path == "text":
            value.title = text; self = .section(value)
        case .discreteHeading(var value) where path == "text":
            value.title = text; self = .discreteHeading(value)
        case .paragraph(var value) where path == "text":
            value.text = text; self = .paragraph(value)
        case .listing(var value) where path == "text":
            value.text = text; self = .listing(value)
        case .literalBlock(var value) where path == "text":
            value.text = text; self = .literalBlock(value)
        case .verse(var value) where path == "text":
            value.text = text; self = .verse(value)
        case .list(var value):
            guard path.hasPrefix("item:"), let index = Int(path.split(separator: ":").last ?? ""),
                  value.items.indices.contains(index) else { return }
            value.items[index].principal = text; self = .list(value)
        case .dlist(var value):
            let parts = path.split(separator: ":")
            guard parts.count == 3, let index = Int(parts[1]), value.items.indices.contains(index) else { return }
            if parts[0] == "term" { value.items[index].term = text }
            else if parts[0] == "definition" { value.items[index].principal = text }
            else { return }
            self = .dlist(value)
        default: return
        }
    }

    func text(for path: String) -> String? {
        switch self {
        case .section(let section) where path == "text":
            return section.title.plain
        case .discreteHeading(let heading) where path == "text":
            return heading.title.plain
        case .paragraph(let paragraph) where path == "text":
            return paragraph.text.plain
        case .listing(let listing) where path == "text":
            return listing.text.plain
        case .literalBlock(let block) where path == "text":
            return block.text.plain
        case .verse(let verse) where path == "text":
            return verse.text?.plain ?? ""
        case .math(let math) where path == "text":
            return math.body
        case .admonition(let admonition) where path == "text":
            return admonition.blocks.firstParagraphText
        case .quote(let quote) where path == "text":
            return quote.blocks.firstParagraphText
        case .example(let example) where path == "text":
            return example.blocks.firstParagraphText
        case .sidebar(let sidebar) where path == "text":
            return sidebar.blocks.firstParagraphText
        case .open(let open) where path == "text":
            return open.blocks.firstParagraphText
        case .list(let list):
            guard path.hasPrefix("item:"), let itemIndex = Int(path.split(separator: ":").last ?? ""),
                  list.items.indices.contains(itemIndex) else { return nil }
            return list.items[itemIndex].principal.plain
        case .dlist(let list):
            let parts = path.split(separator: ":")
            guard parts.count == 3, let entryIndex = Int(parts[1]), list.items.indices.contains(entryIndex) else { return nil }
            switch parts[0] {
            case "term": return list.items[entryIndex].term.plain
            case "definition": return list.items[entryIndex].principal?.plain ?? ""
            default: return nil
            }
        case .table(let table):
            let parts = path.split(separator: ":")
            let rows = AsciiDocEditorDocument.parseTableRows(from: table)
            guard parts.count == 3, parts[0] == "cell",
                  let row = Int(parts[1]), let column = Int(parts[2]),
                  rows.indices.contains(row), rows[row].indices.contains(column) else { return nil }
            return rows[row][column]
        default:
            return nil
        }
    }

    mutating func updateText(_ text: String, for path: String) {
        switch self {
        case .section(var section) where path == "text":
            section.title = AdocText(plain: text)
            self = .section(section)
        case .discreteHeading(var heading) where path == "text":
            heading.title = AdocText(plain: text)
            self = .discreteHeading(heading)
        case .paragraph(var paragraph) where path == "text":
            paragraph.text = AdocText(plain: text)
            self = .paragraph(paragraph)
        case .listing(var listing) where path == "text":
            listing.text = AdocText(plain: text)
            self = .listing(listing)
        case .literalBlock(var block) where path == "text":
            block.text = AdocText(plain: text)
            self = .literalBlock(block)
        case .verse(var verse) where path == "text":
            verse.text = AdocText(plain: text)
            self = .verse(verse)
        case .math(var math) where path == "text":
            math.body = text
            self = .math(math)
        case .admonition(var admonition) where path == "text":
            admonition.blocks = [.paragraph(AdocParagraph(text: AdocText(plain: text)))]
            self = .admonition(admonition)
        case .quote(var quote) where path == "text":
            quote.blocks = [.paragraph(AdocParagraph(text: AdocText(plain: text)))]
            self = .quote(quote)
        case .example(var example) where path == "text":
            example.blocks = [.paragraph(AdocParagraph(text: AdocText(plain: text)))]
            self = .example(example)
        case .sidebar(var sidebar) where path == "text":
            sidebar.blocks = [.paragraph(AdocParagraph(text: AdocText(plain: text)))]
            self = .sidebar(sidebar)
        case .open(var open) where path == "text":
            open.blocks = [.paragraph(AdocParagraph(text: AdocText(plain: text)))]
            self = .open(open)
        case .list(var list):
            guard path.hasPrefix("item:"), let itemIndex = Int(path.split(separator: ":").last ?? ""),
                  list.items.indices.contains(itemIndex) else { return }
            list.items[itemIndex].principal = AdocText(plain: text)
            self = .list(list)
        case .dlist(var list):
            let parts = path.split(separator: ":")
            guard parts.count == 3, let entryIndex = Int(parts[1]), list.items.indices.contains(entryIndex) else { return }
            switch parts[0] {
            case "term":
                list.items[entryIndex].term = AdocText(plain: text)
            case "definition":
                list.items[entryIndex].principal = AdocText(plain: text)
            default:
                return
            }
            self = .dlist(list)
        case .table(var table):
            let parts = path.split(separator: ":")
            guard parts.count == 3, parts[0] == "cell",
                  let row = Int(parts[1]), let column = Int(parts[2]),
                  table.rows.indices.contains(row),
                  table.rows[row].cells.indices.contains(column) else { return }
            table.rows[row].cells[column].text = text
            self = .table(table)
        default:
            return
        }
    }

    mutating func setHeadingLevel(_ level: Int) {
        switch self {
        case .section(var section):
            section.level = level
            self = .section(section)
        case .discreteHeading(var heading):
            heading.level = level
            self = .discreteHeading(heading)
        default:
            return
        }
    }

    var admonitionKind: AsciiDocAdmonitionKind? {
        switch self {
        case .admonition(let admonition):
            return AsciiDocAdmonitionKind(rawValue: admonition.kind?.lowercased() ?? "note")
        case .quote:
            return .quote
        case .example:
            return .example
        case .sidebar:
            return .sidebar
        case .open:
            return .open
        default:
            return nil
        }
    }

    mutating func setAdmonitionKind(_ kind: AsciiDocAdmonitionKind) {
        switch kind {
        case .note, .tip, .warning, .caution, .important:
            let blocks = contentBlocks
            self = .admonition(AdocAdmonition(kind: kind.rawValue, blocks: blocks))
        case .quote:
            self = .quote(AdocQuote(blocks: contentBlocks))
        case .example:
            self = .example(AdocExample(blocks: contentBlocks))
        case .sidebar:
            self = .sidebar(AdocSidebar(blocks: contentBlocks))
        case .open:
            self = .open(AdocOpen(blocks: contentBlocks))
        }
    }

    mutating func appendListItem() {
        switch self {
        case .list(var list):
            let marker: String
            switch list.kind {
            case .ordered(let currentMarker):
                marker = currentMarker
            case .unordered(let currentMarker):
                marker = currentMarker
            case .callout:
                marker = "<1>"
            }
            list.items.append(AdocListItem(marker: marker, principal: AdocText(plain: "New item")))
            self = .list(list)
        case .dlist(var list):
            list.items.append(AdocDListItem(term: AdocText(plain: "Term"), principal: AdocText(plain: "Definition")))
            self = .dlist(list)
        default:
            return
        }
    }

    mutating func appendTableRow() {
        guard case .table(var table) = self else { return }
        let columns = table.rows.first?.cells.count ?? 2
        table.rows.append(AdocTableRow(
            cells: (0..<columns).map { _ in AdocTableCell(text: "") }
        ))
        self = .table(table)
    }

    mutating func appendTableColumn() {
        guard case .table(var table) = self else { return }
        if table.rows.isEmpty {
            table.rows = [AdocTableRow(cells: [AdocTableCell(text: ""), AdocTableCell(text: "")])]
        } else {
            for index in table.rows.indices {
                table.rows[index].cells.append(AdocTableCell(text: ""))
            }
        }
        self = .table(table)
    }

    func canTransform(to kind: AsciiDocEditorBlockKind) -> Bool {
        switch (self, kind) {
        case (.paragraph, .heading), (.paragraph, .listing), (.paragraph, .verse), (.paragraph, .admonition),
             (.paragraph, .orderedList), (.paragraph, .unorderedList),
             (.section, .paragraph), (.section, .listing), (.section, .verse),
             (.listing, .paragraph), (.listing, .heading), (.listing, .verse),
             (.verse, .paragraph), (.verse, .heading), (.verse, .listing),
             (.admonition, .paragraph), (.admonition, .heading), (.admonition, .listing), (.admonition, .verse),
             (.list, .orderedList), (.list, .unorderedList):
            return true
        default:
            return false
        }
    }

    mutating func transform(to kind: AsciiDocEditorBlockKind) {
        guard canTransform(to: kind) else { return }

        let plainText = text(for: "text") ?? ""

        switch kind {
        case .paragraph:
            self = .paragraph(AdocParagraph(text: AdocText(plain: plainText)))
        case .heading:
            let level: Int
            switch self {
            case .section(let section):
                level = section.level
            default:
                level = 1
            }
            self = .section(AdocSection(level: level, title: AdocText(plain: plainText)))
        case .listing:
            self = .listing(AdocListing(text: AdocText(plain: plainText)))
        case .verse:
            self = .verse(AdocVerse(text: AdocText(plain: plainText)))
        case .admonition:
            self = .admonition(AdocAdmonition(
                kind: admonitionKind?.rawValue ?? "note",
                blocks: [.paragraph(AdocParagraph(text: AdocText(plain: plainText)))]
            ))
        case .orderedList:
            let items = plainText
                .split(whereSeparator: \.isNewline)
                .map { AdocListItem(marker: ".", principal: AdocText(plain: String($0))) }
            self = .list(AdocList(
                kind: .ordered(marker: "."),
                items: items.isEmpty ? [AdocListItem(marker: ".", principal: AdocText(plain: plainText))] : items
            ))
        case .unorderedList:
            let items = plainText
                .split(whereSeparator: \.isNewline)
                .map { AdocListItem(marker: "*", principal: AdocText(plain: String($0))) }
            self = .list(AdocList(
                kind: .unordered(marker: "*"),
                items: items.isEmpty ? [AdocListItem(marker: "*", principal: AdocText(plain: plainText))] : items
            ))
        case .descriptionList, .equation, .table:
            return
        }
    }

    private var contentBlocks: [AdocBlock] {
        switch self {
        case .admonition(let admonition): return admonition.blocks
        case .quote(let quote): return quote.blocks
        case .example(let example): return example.blocks
        case .sidebar(let sidebar): return sidebar.blocks
        case .open(let open): return open.blocks
        default:
            return [.paragraph(AdocParagraph(text: AdocText(plain: text(for: "text") ?? "")))]
        }
    }
}

private extension Array where Element == AdocBlock {
    var firstParagraphText: String {
        for block in self {
            if case .paragraph(let paragraph) = block {
                return paragraph.text.plain
            }
        }
        return ""
    }
}

extension AsciiDocEditorDocument {
    fileprivate static func parseTableRows(from table: AdocTable) -> [[String]] {
        let rows = table.rows.map { row in row.cells.map(\.text) }
        return rows.isEmpty ? [["", ""]] : rows
    }
}
