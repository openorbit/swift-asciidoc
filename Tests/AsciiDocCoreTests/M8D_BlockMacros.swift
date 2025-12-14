import Testing
@testable import AsciiDocCore

/*
@Test
func block_macro_image_top_level() throws {
    let src = """
    .A caption
    image::pic.png[Alt text,width=500]
    """
    let parser = AdocParser()
    let doc = parser.parse(text: src)

    #expect(doc.blocks.count == 1)
    guard case .blockMacro(let m) = doc.blocks[0] else { Issue.record("expected block macro"); return }
    #expect(m.name == "image")
    #expect(m.target == "pic.png")
    #expect(m.title == "A caption")
    #expect(m.attributes?.contains("Alt text") == true)
}

@Test
func block_macro_generic_in_list_continuation() throws {
    let src = """
    * Item
    +
    plantuml::uml/diagram.puml[format=svg]
    """
    let parser = AdocParser()
    let doc = parser.parse(text: src)


    guard case .list(let l) = doc.blocks.first else { Issue.record("expected list"); return }

    let hasMacro = l.items.first?.blocks.contains(where: {
        if case .blockMacro(let m) = $0 { return m.name == "plantuml" }
        return false
    })
    #expect(hasMacro == true)
}
*/
