import Testing
@testable import AsciiDocCore

@Suite("Container blocks")
struct ContainerBlockTests {

    @Test
    func example_block_parses_paragraphs() throws {
        let src = """
        ====
        First para.

        Second para.
        ====
        """
        let parser = AdocParser()
        let doc = parser.parse(text: src)
        guard case .example(let ex) = doc.blocks.first else { Issue.record("expected example"); return }
        #expect(ex.blocks.count == 2)
        let texts = ex.blocks.compactMap { if case .paragraph(let p) = $0 { p.text.plain } else { nil } }
        #expect(texts == ["First para.", "Second para."])
    }

    @Test
    func sidebar_block_basic() throws {
        let src = """
        ****
        In a sidebar.
        ****
        """
        let parser = AdocParser()
        let doc = parser.parse(text: src)
        guard case .sidebar(let sb) = doc.blocks.first else { Issue.record("expected sidebar"); return }
        #expect(sb.blocks.count == 1)
    }

    @Test
    func literal_block_verbatim() throws {
        let src = """
        ....
        a <b> tag
        ....
        """
        let parser = AdocParser()
        let doc = parser.parse(text: src)
        guard case .literalBlock(let lit) = doc.blocks.first else { Issue.record("expected literal"); return }
        #expect(lit.text.plain == "a <b> tag")
    }

    @Test
    func open_block_in_list_via_continuation() throws {
        let src = """
        * Item
        +
        --
        in open
        --
        """
        let parser = AdocParser()
        let doc = parser.parse(text: src)
        guard case .list(let l) = doc.blocks.first else { Issue.record("expected list"); return }
        #expect(l.items.first?.blocks.contains { if case .open = $0 { true } else { false } } == true)
    }

    @Test
    func verse_block_with_attribution() throws {
        let src = """
        [verse]
        ____
        roses are red
        violets are blue
        ____
        -- poet
        """
        let parser = AdocParser()
        let doc = parser.parse(text: src)

        guard case .verse(let v) = doc.blocks.first else { Issue.record("expected verse"); return }
        guard case .paragraph(let p) = v.blocks.first else { Issue.record("expected verse"); return }
        #expect(p.text.plain == "roses are red\nviolets are blue")
        #expect(v.attribution?.plain == "poet")
    }
}
