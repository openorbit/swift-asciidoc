import Testing
@testable import AsciiDocCore

@Suite("Delimited blocks")
struct DelimitedBlockTests {

    @Test
    func parses_quote_block_into_paragraphs() throws {
        let src = """
        ____
        First para in quote.

        Second para in quote.
        ____
        """
        let parser = AdocParser()
        let doc = parser.parse(text: src)

        #expect(doc.blocks.count == 1)
        guard case .quote(let q) = doc.blocks[0] else { Issue.record("expected quote"); return }
        let paras = q.blocks.compactMap { if case .paragraph(let p) = $0 { p.text.plain } else { nil } }
        #expect(paras == ["First para in quote.", "Second para in quote."])
    }

    @Test
    func parses_listing_block_verbatim() throws {
        let src = """
        ----
        let x = 42
        print(x)
        ----
        """
        let parser = AdocParser()
        let doc = parser.parse(text: src)
        #expect(doc.blocks.count == 1)
        guard case .listing(let l) = doc.blocks[0] else { Issue.record("expected listing"); return }
        #expect(l.text.plain == "let x = 42\nprint(x)")
    }

    @Test
    func delimited_block_with_continuation_attaches_inside_list_item() throws {
        let src = """
        * Item
        +
        ____
        Quoted
        ____
        """
        let parser = AdocParser()
        let doc = parser.parse(text: src)
        // One top-level block: the list
        #expect(doc.blocks.count == 1)
        guard case .list(let list) = doc.blocks[0] else { Issue.record("expected ulist"); return }
        #expect(list.items.count == 1)
        // The item's blocks should include a quote block
        let itemBlocks = list.items[0].blocks
        #expect(itemBlocks.contains { if case .quote = $0 { true } else { false } })
    }

    @Test
    func delimited_block_without_continuation_closes_list() throws {
        let src = """
        * Item
        ____
        Quoted
        ____
        """
        let parser = AdocParser()
        let doc = parser.parse(text: src)
        // Two top-level blocks: list, then quote
        #expect(doc.blocks.count == 2)
        guard case .list = doc.blocks[0] else { Issue.record("first should be ulist"); return }
        guard case .quote = doc.blocks[1] else { Issue.record("second should be quote"); return }
    }
}
