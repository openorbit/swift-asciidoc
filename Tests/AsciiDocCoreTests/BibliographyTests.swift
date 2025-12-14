import Testing
@testable import AsciiDocCore

@Suite("Bibliography lists")
struct BibliographyTests {

    @Test
    func bibliography_items_capture_ids_and_labels() {
        let src = """
        [bibliography]
        * [[[taoup]]]Eric S. Raymond. _The Art of Unix Programming_. 2004.
        * [[[walsh,Walsh & Muellner]]]Walsh & Muellner. DocBook 5.
        """

        let parser = AdocParser()
        let doc = parser.parse(text: src)

        guard case .list(let list) = doc.blocks.first else {
            Issue.record("Expected list block")
            return
        }
        #expect(list.meta.attributes["style"]?.lowercased() == "bibliography")
        #expect(list.items.count == 2)

        let first = list.items[0]
        #expect(first.id == "taoup")
        #expect(first.reftext == nil)
        #expect(first.principal.plain.hasPrefix("Eric S. Raymond"))

        let second = list.items[1]
        #expect(second.id == "walsh")
        #expect(second.reftext?.plain == "Walsh & Muellner")
        #expect(second.principal.plain.hasPrefix("Walsh & Muellner"))
    }

    @Test
    func regular_list_leaves_triple_brackets_literal() {
        let src = """
        * [[[keep]]] literal anchor
        """

        let parser = AdocParser()
        let doc = parser.parse(text: src)

        guard case .list(let list) = doc.blocks.first else {
            Issue.record("Expected list block")
            return
        }
        guard let item = list.items.first else {
            Issue.record("Missing list item")
            return
        }
        #expect(item.id == nil)
        #expect(item.principal.plain.contains("[[[keep]]]"))
    }
}
