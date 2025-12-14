import Testing
@testable import AsciiDocCore

@Suite("Admonition Tests")
struct AdminitionTests {
    @Test
    func admonition_block_basic() throws {
        let src = """
    [NOTE]
    A small note.
    """

        let parser = AdocParser()
        let doc = parser.parse(text: src)
        #expect(doc.blocks.count == 1)

        guard case .admonition(let a) = doc.blocks[0] else { Issue.record("expected admonition"); return }
        #expect(a.kind == "NOTE")
        let para = a.blocks.compactMap { if case .paragraph(let p) = $0 { p.text } else { nil } }.first
        #expect(para?.plain == "A small note.")
    }

    @Test
    func block_title_applies_to_quote() throws {
        let src = """
    .Wise Words
    ____
    Be yourself; everyone else is already taken.
    ____
    """

        let parser = AdocParser()
        let doc = parser.parse(text: src)
        #expect(doc.blocks.count == 1)
        guard case .quote(let q) = doc.blocks[0] else { Issue.record("expected quote"); return }
        #expect(q.title?.plain == "Wise Words")
    }

    @Test
    func quote_attribution_is_captured() throws {
        let src = """
    ____
    Never give up.
    ____
    -- Winston
    """
        let parser = AdocParser()
        let doc = parser.parse(text: src)

        guard case .quote(let q) = doc.blocks.first else { Issue.record("expected quote"); return }
        guard case .paragraph(let p) = q.blocks[0] else { Issue.record("expected paragraph"); return}
        #expect(p.text.plain == "Never give up.")
        #expect(q.attribution?.plain == "Winston")
    }

    @Test
    func title_then_admonition_then_paragraph() throws {
        let src = """
    .Heads up
    [WARNING]
    Beware of dragons.
    """
        let parser = AdocParser()
        let doc = parser.parse(text: src)

        guard case .admonition(let a) = doc.blocks.first else { Issue.record("expected admonition"); return }
        #expect(a.kind == "WARNING")
        #expect(a.title?.plain == "Heads up") // title applied to admonition
        let p = a.blocks.compactMap { if case .paragraph(let p) = $0 { p.text } else { nil } }.first
        #expect(p?.plain == "Beware of dragons.")
    }
}
