import Testing
@testable import AsciiDocCore

@Suite("Parser smoke tests")
struct ParserSmokeTests {

    @Test
    func parses_heading_and_paragraph() throws {
        let src = """
        = Title

        Hello, world.
        """

        let parser = AdocParser()
        let doc = parser.parse(text: src)

        #expect(doc.blocks.count == 1)
        #expect(doc.header?.title?.plain == "Title")

        guard case .paragraph(let p) = doc.blocks[0] else {
            Issue.record("First block is a paragraph")
            return
        }
        #expect(p.text.plain == "Hello, world.")
    }

    @Test
    func header_attributes_are_parsed() throws {
        let src = """
        :product: Hydra

        = {product} Docs

        Intro.
        """
        let parser = AdocParser()
        let doc = parser.parse(text: src)
        #expect(doc.attributes["product"] == "Hydra")

        guard case .section(let s) = doc.blocks.first else { Issue.record("missing section"); return }
        #expect(s.title.plain == "Hydra Docs")

        // Paragraph lives inside the section.
        //#expect(s.children.contains { if case .paragraph = $0 { true } else { false } })
    }

    @Test
    func windows_and_mac_line_endings_normalize() throws {
        let crlf = "= T\r\n\r\nPara\r\n"
        let cr   = "= T\r\rPara\r"
        let lf   = "= T\n\nPara\n"

        let parser = AdocParser()
        let a = parser.parse(text: crlf)
        let b = parser.parse(text: cr)
        let c = parser.parse(text: lf)

        // All three produce the same simple structure
        #expect(a.blocks.count == 1 && a.blocks.count == b.blocks.count && b.blocks.count == c.blocks.count)
        #expect(a.header?.title?.plain == "T" && a.header?.title == b.header?.title && b.header?.title == c.header?.title)
    }
}
