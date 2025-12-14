import Testing
@testable import AsciiDocCore

@Suite("Xref parsing")
struct XrefTests {

    @Test
    func macro_style_xref_collects_antora_parts() throws {
        let src = "See xref:comp:ui:1.0@partial$header.adoc#slot[Custom heading]."
        let parser = AdocParser()
        let doc = parser.parse(text: src)

        guard case .paragraph(let para) = doc.blocks.first else {
            Issue.record("Expected paragraph block")
            return
        }
        guard para.text.inlines.count >= 2 else {
            Issue.record("Missing xref inline")
            return
        }
        guard case .xref(let target, let label, _) = para.text.inlines[1] else {
            Issue.record("Expected xref inline")
            return
        }

        #expect(target.raw == "comp:ui:1.0@partial$header.adoc#slot")
        let antora = target.antora
        #expect(antora?.component == "comp")
        #expect(antora?.module == "ui")
        #expect(antora?.version == "1.0")
        #expect(antora?.family == "partial")
        #expect(antora?.resource == "header.adoc")
        #expect(antora?.fragment == "slot")
        #expect(AdocText(inlines: label).plain == "Custom heading")
    }

    @Test
    func double_chevron_xref_supports_optional_label() throws {
        let src = "Refer to <<chapter-intro,Introduction>> for background."
        let parser = AdocParser()
        let doc = parser.parse(text: src)

        guard case .paragraph(let para) = doc.blocks.first else {
            Issue.record("Expected paragraph block")
            return
        }
        guard case .xref(let target, let label, _) = para.text.inlines[1] else {
            Issue.record("Expected chevron xref inline")
            return
        }
        #expect(target.raw == "chapter-intro")
        #expect(AdocText(inlines: label).plain == "Introduction")
    }

    @Test
    func antora_parser_handles_family_and_fragment() {
        let parsed = AntoraXrefTarget.parse(raw: "docs:ROOT@image$diagram.svg#callout-1")
        #expect(parsed?.component == "docs")
        #expect(parsed?.module == "ROOT")
        #expect(parsed?.version == nil)
        #expect(parsed?.family == "image")
        #expect(parsed?.resource == "diagram.svg")
        #expect(parsed?.fragment == "callout-1")

        let attachment = AntoraXrefTarget.parse(raw: "attachment$payload.zip")
        #expect(attachment?.family == "attachment")
        #expect(attachment?.resource == "payload.zip")
        #expect(attachment?.component == nil)
        #expect(attachment?.module == nil)

        let moduleScoped = AntoraXrefTarget.parse(raw: "config:settings.adoc")
        #expect(moduleScoped?.module == "config")
        #expect(moduleScoped?.resource == "settings.adoc")
    }
}
