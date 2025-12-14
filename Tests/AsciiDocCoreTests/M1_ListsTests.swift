import Testing
@testable import AsciiDocCore

@Suite("List parsing")
struct ListParsingTests {

    @Test
    func parses_unordered_list_simple() throws {
        let src = """
        * One
        * Two
        """

        let parser = AdocParser()
        let doc = parser.parse(text: src)

        #expect(doc.blocks.count == 1)
        guard case .list(let list) = doc.blocks[0] else {
            Issue.record("expected list"); return }
        #expect(list.kind == .unordered(marker: "*"))
        #expect(list.items.count == 2)

        #expect(list.items[0].principal.plain == "One")
        #expect(list.items[1].principal.plain == "Two")
    }

    @Test
    func parses_ordered_list_simple() throws {
        let src = """
        . First
        . Second
        """

        let parser = AdocParser()
        let doc = parser.parse(text: src)

        #expect(doc.blocks.count == 1)
        guard case .list(let list) = doc.blocks[0] else {
            Issue.record("expected list"); return }
        #expect(list.kind == .ordered(marker: "."))
        #expect(list.items.count == 2)

        #expect(list.items[0].principal.plain == "First")
        #expect(list.items[1].principal.plain == "Second")
    }

    @Test
    func parses_nested_unordered_list_by_marker_depth() throws {
        let src = """
        * Top
        ** Child
        * Sibling
        """

        let parser = AdocParser()
        let doc = parser.parse(text: src)

        #expect(doc.blocks.count == 1)
        guard case .list(let top) = doc.blocks[0] else { Issue.record("expected list"); return }
        #expect(top.items.count == 2)

        // The first item's children should contain a nested list
        let firstChildren = top.items[0].blocks
        #expect(firstChildren.contains { if case .list = $0 { true } else { false } })
    }

    @Test
    func list_continuation_attaches_paragraph() throws {
        let src = """
        * Item
        +
        Continuation paragraph.
        """
        let parser = AdocParser()
        let doc = parser.parse(text: src)
        guard case .list(let list) = doc.blocks.first else { Issue.record("expected ulist"); return }
        #expect(list.items.count == 1)
        let blocks = list.items[0].blocks
        let paras = blocks.compactMap { if case .paragraph(let p) = $0 { p } else { nil } }
        #expect(paras.count == 1)
        #expect(list.items[0].principal.plain == "Item")
        #expect(paras[0].text.plain == "Continuation paragraph.")
    }
}
