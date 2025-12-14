import Foundation
import Testing
@testable import AsciiDocCore
@testable import AsciiDocTools

@Suite("Attributed interop")
struct AttributedInteropTests {

    @Test
    func attributedDocumentRoundTrip() {
        let inline: [AdocInline] = [
            .text("Hello ", span: nil),
            .strong([.text("bold", span: nil)], span: nil),
            .text(" and ", span: nil),
            .emphasis([.text("italic", span: nil)], span: nil),
            .mark([.text("mark", span: nil)], span: nil),
            .mono([.text("code", span: nil)], span: nil),
            .link(target: "https://example.com", text: [.text("link", span: nil)], span: nil)
        ]

        let paragraph = AdocParagraph(text: AdocText(inlines: inline))
        let doc = AdocDocument(attributes: [:], header: nil, blocks: [.paragraph(paragraph)], span: nil)

        let exported = AttributedExport.make(from: doc)
        let imported = AttributedImport.makeDocument(from: exported)

        #expect(imported == doc)
    }

    #if !os(Linux)
    @Test
    func importsInlinePresentationIntentWhenCustomAttributesMissing() {
        var intentContainer = AttributeContainer()
        intentContainer.inlinePresentationIntent = [.stronglyEmphasized]
        let attributed = AttributedString("Strong text", attributes: intentContainer)

        let text = AttributedImport.makeText(from: attributed)
        #expect(text.inlines.count == 1)

        guard case .strong(let children, _) = text.inlines.first else {
            Issue.record("Expected strong inline")
            return
        }
        let expected: [AdocInline] = [.text("Strong text", span: nil)]
        #expect(children == expected)
    }
    #endif

    @Test
    func splitsParagraphsOnBlankLines() {
        var attr = AttributedString("First paragraph")
        attr.append(AttributedString("\n\n"))

        let marked = AttributedExport.make(from: AdocText(inlines: [.mark([.text("Second paragraph", span: nil)], span: nil)]))
        attr.append(marked)

        let doc = AttributedImport.makeDocument(from: attr)
        #expect(doc.blocks.count == 2)

        guard case .paragraph(let first) = doc.blocks[0],
              case .paragraph(let second) = doc.blocks[1] else {
            Issue.record("Expected paragraphs")
            return
        }

        #expect(first.text.plain == "First paragraph")
        guard case .mark = second.text.inlines.first else {
            Issue.record("Missing mark inline on second paragraph")
            return
        }
    }
}
