import Testing
@testable import AsciiDocCore

@Suite("Admintion Continuations")
struct AdmonitionContinuationTests {

    @Test
    func admonition_inside_list_continuation_then_quote_is_sibling_in_item() throws {
        let src = """
    * Item
    +
    TIP: Tip para.
    +
    ____
    q
    ____
    """
        let parser = AdocParser()
        let doc = parser.parse(text: src)

        // One top-level block: the list
        #expect(doc.blocks.count == 1)
        guard case .list(let list) = doc.blocks[0] else { Issue.record("expected ulist"); return }
        #expect(list.items.count == 1)

        // The list item should have three sibling blocks: bullet paragraph, admonition, quote
        let itemBlocks = list.items[0].blocks
        #expect(itemBlocks.count == 2)

        #expect(list.items[0].principal.plain == "Item")

        guard case .admonition(let a) = itemBlocks[0] else { Issue.record("second should be admonition"); return }
        #expect(a.kind == "TIP")
        guard case .paragraph(let tipPara) = a.blocks.first else { Issue.record("admonition should contain paragraph"); return }
        #expect(tipPara.text.plain == "Tip para.")

        guard case .quote(let q) = itemBlocks[1] else { Issue.record("third should be quote"); return }
        let qparas = q.blocks.compactMap { if case .paragraph(let p) = $0 { p.text.plain } else { nil } }
        #expect(qparas == ["q"])
    }
}
