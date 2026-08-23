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
    #endif
}

private extension AdocBlock {
    var tableValue: AdocTable? {
        guard case .table(let table) = self else { return nil }
        return table
    }
}
