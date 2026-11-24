import Foundation
import Testing
import AsciiDocCore
@testable import AsciiDocBlockEditor
#if canImport(AppKit)
import AppKit
#endif

@Suite("Semantic editor projection")
struct SemanticProjectionTests {
    @Test
    func projectionMapsEditableFieldsWithoutAsciiDocBlockMarkers() throws {
        let document = AsciiDocEditorDocument.sample
        let projection = AdocSemanticProjectionBuilder.make(document: document)
        let projectedText = projection.attributedString.string

        #expect(projectedText.contains("Structured AsciiDoc Editing"))
        #expect(projectedText.contains("•\tWYSIWYM"))
        #expect(projectedText.contains("strong, emphasis, code, and mark"))
        #expect(!projectedText.contains("*strong*"))
        #expect(!projectedText.contains("_emphasis_"))
        #expect(!projectedText.contains("#mark#"))
        #expect(!projectedText.contains("== Inline formatting"))
        #expect(!projectedText.contains("|==="))

        let headingKey = AsciiDocEditorFieldKey(blockIndex: 1, path: "text")
        let headingRange = try #require(projection.range(for: headingKey))
        #expect((projectedText as NSString).substring(with: headingRange) == "Inline formatting")
    }

    @Test
    func editingAProjectedFieldMutatesTheISMInsteadOfSource() throws {
        var document = AsciiDocEditorDocument.sample
        let key = AsciiDocEditorFieldKey(blockIndex: 0, path: "text")

        document.updateText("Changed semantic paragraph", for: key)

        #expect(document.text(for: key) == "Changed semantic paragraph")
        #expect(document.blocks.count == AsciiDocEditorDocument.sample.blocks.count)
        #expect(document.asciiDocSource().contains("Changed semantic paragraph"))
    }

    @Test
    func generatedListMarkerIsOutsideEditableItemRange() throws {
        let document = AsciiDocEditorDocument.sample
        let projection = AdocSemanticProjectionBuilder.make(document: document)
        let key = AsciiDocEditorFieldKey(blockIndex: 3, path: "item:0")
        let itemRange = try #require(projection.range(for: key))

        #expect(itemRange.location >= 2)
        let markerRange = NSRange(location: itemRange.location - 2, length: 2)
        #expect(projection.field(containing: markerRange) == nil)
        #expect((projection.attributedString.string as NSString).substring(with: markerRange) == "•\t")
    }

    @Test
    func editingTableCellPreservesStructuredCellMetadata() throws {
        var document = AsciiDocEditorDocument(ism: .init(blocks: [
            .table(.init(rows: [
                AdocTableRow(cells: [
                    AdocTableCell(
                        text: "before",
                        columnSpan: 2,
                        horizontalAlignment: .center,
                        style: .header,
                        rawSpecifier: "2+^h"
                    )
                ])
            ]))
        ]))

        document.updateText("after", for: .init(blockIndex: 0, path: "cell:0:0"))

        let table = try #require(document.blocks.first?.tableValue)
        let cell = try #require(table.rows.first?.cells.first)
        #expect(cell.text == "after")
        #expect(cell.columnSpan == 2)
        #expect(cell.horizontalAlignment == .center)
        #expect(cell.style == .header)
        #expect(cell.rawSpecifier == "2+^h")
    }

    #if canImport(AppKit)
    @Test
    func macOSProjectionUsesNativeTextTableBlocks() throws {
        let projection = AdocSemanticProjectionBuilder.make(document: .sample)
        let key = AsciiDocEditorFieldKey(blockIndex: 5, path: "cell:0:0")
        let range = try #require(projection.range(for: key))
        let paragraph = try #require(
            projection.attributedString.attribute(.paragraphStyle, at: range.location, effectiveRange: nil)
                as? NSParagraphStyle
        )

        #expect(paragraph.textBlocks.first is NSTextTableBlock)
    }

    @Test
    func macOSProjectionStylesInlineNodesWithoutShowingMarkers() throws {
        let document = AsciiDocEditorDocument(ism: .init(blocks: [
            .paragraph(.init(text: .init(plain: "plain *strong* and _emphasis_")))
        ]))
        let projection = AdocSemanticProjectionBuilder.make(document: document)
        let text = projection.attributedString.string

        #expect(text == "plain strong and emphasis")
        let strongLocation = (text as NSString).range(of: "strong").location
        let strongFont = try #require(projection.attributedString.attribute(.font, at: strongLocation, effectiveRange: nil) as? NSFont)
        #expect(NSFontManager.shared.traits(of: strongFont).contains(.boldFontMask))

        let emphasisLocation = (text as NSString).range(of: "emphasis").location
        let emphasisFont = try #require(projection.attributedString.attribute(.font, at: emphasisLocation, effectiveRange: nil) as? NSFont)
        #expect(NSFontManager.shared.traits(of: emphasisFont).contains(.italicFontMask))
    }
    #endif

    @Test
    func typingInsideStrongTextPreservesTheInlineNode() throws {
        var document = AsciiDocEditorDocument(ism: .init(blocks: [
            .paragraph(.init(text: .init(plain: "before *strong* after")))
        ]))
        let key = AsciiDocEditorFieldKey(blockIndex: 0, path: "text")

        let preserved = document.replaceSemanticText(
            for: key,
            in: NSRange(location: 8, length: 1),
            with: "X"
        )

        #expect(preserved)
        let text = try #require(document.semanticText(for: key))
        #expect(text.visibleText == "before sXrong after")
        #expect(text.plain == "before *sXrong* after")
        #expect(text.inlines.contains { inline in
            if case .strong = inline { return true }
            return false
        })
    }

    @Test(arguments: [
        AsciiDocInlineMarkup.emphasis,
        .strong,
        .code,
        .mark,
        .subscriptText,
        .superscriptText
    ])
    func semanticToolbarMarkupWrapsSelectedText(_ markup: AsciiDocInlineMarkup) throws {
        var document = AsciiDocEditorDocument(ism: .init(blocks: [
            .paragraph(.init(text: .init(plain: "before selected after")))
        ]))
        let key = AsciiDocEditorFieldKey(blockIndex: 0, path: "text")

        let applied = document.applySemanticInline(
            markup,
            to: key,
            visibleRange: NSRange(location: 7, length: 8)
        )

        #expect(applied)
        let text = try #require(document.semanticText(for: key))
        #expect(text.visibleText == "before selected after")
        #expect(text.plain.contains("\(markup.delimiterForTesting)selected\(markup.delimiterForTesting)"))
    }

    @Test
    func insertingNewlineInParagraphSplitsIntoTwoParagraphBlocks() throws {
        var document = AsciiDocEditorDocument(ism: .init(blocks: [
            .paragraph(.init(text: .init(plain: "First paragraphSecond paragraph")))
        ]))
        let key = AsciiDocEditorFieldKey(blockIndex: 0, path: "text")

        let next = document.applyEdit(in: key, range: NSRange(location: 15, length: 0), replacement: "\n")

        #expect(document.blocks.count == 2)
        #expect(document.text(for: .init(blockIndex: 0, path: "text")) == "First paragraph")
        #expect(document.text(for: .init(blockIndex: 1, path: "text")) == "Second paragraph")
        #expect(next == AsciiDocEditorSelection(
            field: .init(blockIndex: 1, path: "text"),
            range: NSRange(location: 0, length: 0)
        ))
    }

    @Test
    func setBlockStyleOnMultiLineParagraphOnlyChangesCursorLine() throws {
        var document = AsciiDocEditorDocument(ism: .init(blocks: [
            .paragraph(.init(text: .init(plain: "Intro\nSection Title\nBody")))
        ]))
        let selection = AsciiDocEditorSelection(
            field: .init(blockIndex: 0, path: "text"),
            range: NSRange(location: 8, length: 0)
        )

        let updatedSelection = document.setBlockStyle(.heading, headingLevel: 2, at: selection)

        #expect(document.blocks.count == 3)
        #expect(document.blockKind(at: 0) == .paragraph)
        #expect(document.text(for: .init(blockIndex: 0, path: "text")) == "Intro")
        #expect(document.blockKind(at: 1) == .heading)
        #expect(document.headingLevel(at: 1) == 2)
        #expect(document.text(for: .init(blockIndex: 1, path: "text")) == "Section Title")
        #expect(document.blockKind(at: 2) == .paragraph)
        #expect(document.text(for: .init(blockIndex: 2, path: "text")) == "Body")
        #expect(updatedSelection.field == .init(blockIndex: 1, path: "text"))
    }

    @Test
    func listStyleTransformationPreservesAllItems() throws {
        var document = AsciiDocEditorDocument(ism: .init(blocks: [
            .list(.init(
                kind: .unordered(marker: "*"),
                items: [
                    .init(marker: "*", principal: .init(plain: "One")),
                    .init(marker: "*", principal: .init(plain: "Two"))
                ]
            ))
        ]))

        let selection = AsciiDocEditorSelection(
            field: .init(blockIndex: 0, path: "item:1"),
            range: NSRange(location: 0, length: 0)
        )
        let updated = document.setBlockStyle(.orderedList, at: selection)

        #expect(document.blockKind(at: 0) == .orderedList)
        #expect(document.itemCount(at: 0) == 2)
        #expect(document.text(for: .init(blockIndex: 0, path: "item:0")) == "One")
        #expect(document.text(for: .init(blockIndex: 0, path: "item:1")) == "Two")
        #expect(updated.field == .init(blockIndex: 0, path: "item:1"))
    }

    @Test
    func newlineInEmptyListItemExitsListIntoParagraph() throws {
        var document = AsciiDocEditorDocument(ism: .init(blocks: [
            .list(.init(
                kind: .unordered(marker: "*"),
                items: [
                    .init(marker: "*", principal: .init(plain: "One")),
                    .init(marker: "*", principal: .init(plain: ""))
                ]
            ))
        ]))

        let next = document.applyEdit(
            in: .init(blockIndex: 0, path: "item:1"),
            range: NSRange(location: 0, length: 0),
            replacement: "\n"
        )

        #expect(document.blocks.count == 2)
        #expect(document.itemCount(at: 0) == 1)
        #expect(document.blockKind(at: 1) == .paragraph)
        #expect(next == AsciiDocEditorSelection(
            field: .init(blockIndex: 1, path: "text"),
            range: NSRange(location: 0, length: 0)
        ))
    }

    @Test
    func backspaceAtStartOfParagraphMergesWithPreviousParagraph() throws {
        var document = AsciiDocEditorDocument(ism: .init(blocks: [
            .paragraph(.init(text: .init(plain: "Hello "))),
            .paragraph(.init(text: .init(plain: "world")))
        ]))

        let next = document.deleteBackwardAtStart(of: .init(blockIndex: 1, path: "text"))

        #expect(document.blocks.count == 1)
        #expect(document.text(for: .init(blockIndex: 0, path: "text")) == "Hello world")
        #expect(next == AsciiDocEditorSelection(
            field: .init(blockIndex: 0, path: "text"),
            range: NSRange(location: 6, length: 0)
        ))
    }

    @Test
    func parsingAsciiDocFlattensSectionBlocksIntoEditableProjection() throws {
        let document = AsciiDocEditorDocument(asciiDoc: "= Title\n\n== Section\n\nBody paragraph.")
        let projection = AdocSemanticProjectionBuilder.make(document: document)

        #expect(document.blocks.count == 2)
        #expect(document.blockKind(at: 0) == .heading)
        #expect(document.blockKind(at: 1) == .paragraph)
        #expect(projection.attributedString.string.contains("Body paragraph."))
    }
}

private extension AdocBlock {
    var tableValue: AdocTable? {
        guard case .table(let table) = self else { return nil }
        return table
    }
}

private extension AsciiDocInlineMarkup {
    var delimiterForTesting: String {
        switch self {
        case .emphasis: "_"
        case .strong: "*"
        case .code: "`"
        case .mark: "#"
        case .subscriptText: "~"
        case .superscriptText: "^"
        }
    }
}
