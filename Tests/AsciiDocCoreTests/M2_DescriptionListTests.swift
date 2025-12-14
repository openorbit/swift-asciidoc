import Testing
@testable import AsciiDocCore

@Suite("Description Lists")
struct DListTests {

    @Test
    func parses_description_list_with_inline_description() throws {
        let src = """
    Term:: Inline description.
    """

        let parser = AdocParser()
        let doc = parser.parse(text: src)

        #expect(doc.blocks.count == 1)
        guard case .dlist(let dl) = doc.blocks[0] else { Issue.record("expected dlist"); return }
        //#expect(dl.kind == .)
        #expect(dl.items.count == 1)
        #expect(dl.items[0].term.plain == "Term")
        #expect(dl.items[0].principal!.plain == "Inline description.")
    }

    @Test
    func description_list_supports_blank_line_between_items() throws {
        let src = """
    Alpha:: A
     
    Beta:: B
    """
        let parser = AdocParser()
        let doc = parser.parse(text: src)

        guard case .dlist(let dl) = doc.blocks[0] else { Issue.record("expected dlist"); return }

        #expect(dl.items.count == 2)
        #expect(dl.items[0].term.plain == "Alpha")
        #expect(dl.items[0].principal!.plain == "A")
        #expect(dl.items[1].term.plain == "Beta")
        #expect(dl.items[1].principal!.plain == "B")
    }

    @Test
    func description_list_continuation_adds_separate_paragraph() throws {
        let src = """
    Topic::
    +
    First paragraph.
    +
    Second paragraph.
    """
        let parser = AdocParser()
        let doc = parser.parse(text: src)

        guard case .dlist(let dl) = doc.blocks.first else { Issue.record("expected dlist"); return }
        #expect(dl.items.count == 1)
        let blocks = dl.items[0].blocks
        let paras = blocks.compactMap { if case .paragraph(let p) = $0 { p.text.plain } else { nil } }
        #expect(paras == ["First paragraph.", "Second paragraph."])
    }

    @Test
    func switching_from_dlist_to_paragraph_closes_dlist() throws {
        let src = """
    Term:: Desc
    Not part of the list.
    """
        let parser = AdocParser()
        let doc = parser.parse(text: src)
        #expect(doc.blocks.count == 2)
        guard case .dlist = doc.blocks[0] else { Issue.record("expected first block to be dlist"); return }
        guard case .paragraph(let p) = doc.blocks[1] else { Issue.record("expected second block to be paragraph"); return }
        #expect(p.text.plain == "Not part of the list.")
    }

    @Test
    func description_list_respects_attribute_substitutions() throws {
        let src = """
    :name: Hydra
    
    {name}:: The beast.
    """
        let parser = AdocParser()
        let doc = parser.parse(text: src)
        guard case .dlist(let dl) = doc.blocks.first else { Issue.record("expected dlist"); return }
        #expect(dl.items.first?.term.plain == "Hydra")
    }
}
