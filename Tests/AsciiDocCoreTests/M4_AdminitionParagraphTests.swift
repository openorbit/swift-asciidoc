import Testing
@testable import AsciiDocCore

@Suite("Admonition Paragraph")
struct AdmonitionParagraphTests {


    @Test
    func admonition_paragraph_basic() throws {
        let src = """
    NOTE: This is a note.
    """
        let parser = AdocParser()
        let doc = parser.parse(text: src)
        #expect(doc.blocks.count == 1)
        guard case .admonition(let a) = doc.blocks.first else { Issue.record("expected admonition"); return }
        #expect(a.kind == "NOTE")
        let para = a.blocks.compactMap { if case .paragraph(let p) = $0 { p } else { nil } }.first
        #expect(para?.text.plain == "This is a note.")
    }

    @Test
    func admonition_paragraph_multiline_until_blank() throws {
        let src = """
    TIP: First line
    continues here
    and here.
    
    Afterward paragraph.
    """
        let parser = AdocParser()
        let doc = parser.parse(text: src)
        #expect(doc.blocks.count == 2)
        guard case .admonition(let a) = doc.blocks[0] else { Issue.record("expected admonition"); return }
        #expect(a.kind == "TIP")
        let p = a.blocks.compactMap { if case .paragraph(let p) = $0 { p } else { nil } }.first
        #expect(p?.text.plain == "First line\ncontinues here\nand here.")

        guard case .paragraph(let p2) = doc.blocks[1] else { Issue.record("expected trailing paragraph"); return }
        #expect(p2.text.plain == "Afterward paragraph.")
    }

    @Test
    func admonition_paragraph_respects_block_title() throws {
        let src = """
    .Heads up
    WARNING: Dragons ahead.
    """
        let parser = AdocParser()
        let doc = parser.parse(text: src)
        guard case .admonition(let a) = doc.blocks.first else { Issue.record("expected admonition"); return }
        #expect(a.kind == "WARNING")
        #expect(a.title?.plain == "Heads up")  // title applies to admonition, not inner paragraph
    }

    @Test
    func admonition_paragraph_inside_list_continuation() throws {
        let src = """
    * Item
    +
    CAUTION: Check your gear.
    """
        let parser = AdocParser()
        let doc = parser.parse(text: src)
        #expect(doc.blocks.count == 1)
        guard case .list(let list) = doc.blocks[0] else { Issue.record("expected ulist"); return }
        #expect(list.items.count == 1)

        let itemBlocks = list.items[0].blocks
        // The continuation should attach an admonition to the item
        #expect(itemBlocks.contains { if case .admonition = $0 { true } else { false } })
    }

    @Test
    func admonition_paragraph_then_plus_then_listing_has_plus_paragraph_between() throws {
        let src = """
    NOTE: First para.
    +
    ----
    code
    ----
    """

        let parser = AdocParser()
        let doc = parser.parse(text: src)

        // Three top-level blocks: admonition, '+', listing
        #expect(doc.blocks.count == 3)

        guard case .admonition(let a) = doc.blocks[0] else { Issue.record("expected admonition"); return }
        #expect(a.kind == "NOTE")
        guard case .paragraph(let p0) = a.blocks.first else { Issue.record("admonition should contain paragraph"); return }
        #expect(p0.text.plain == "First para.")

        guard case .paragraph(let plusP) = doc.blocks[1] else { Issue.record("expected '+' paragraph"); return }
        #expect(plusP.text.plain == "+")

        guard case .listing(let l) = doc.blocks[2] else { Issue.record("expected listing"); return }
        #expect(l.text.plain == "code")
    }

    @Test
    func admonition_reftext_expands_attributes() throws {
        let src = """
    :caption: Heads up
    [[warn,{caption}]]
    WARNING: Dragons ahead.
    """
        let parser = AdocParser()
        let doc = parser.parse(text: src)
        guard case .admonition(let a) = doc.blocks.first else { Issue.record("expected admonition"); return }
        #expect(a.kind == "WARNING")
        // The anchor from Parser+BlockMeta sets the reftext, which should reflect expanded attributes.
        #expect(a.reftext?.plain == "Heads up")
    }
}
