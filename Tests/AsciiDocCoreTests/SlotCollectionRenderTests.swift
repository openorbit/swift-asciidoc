import Testing
import AsciiDocCore
import AsciiDocRender

@Suite("XAD Slot/Collection Rendering")
struct SlotCollectionRenderTests {
    @Test
    func extractsSlotsAndCollections() throws {
        let engine = CapturingTemplateEngine()
        let config = RenderConfig(
            backend: .html5,
            xadOptions: XADOptions(enabled: true)
        )
        let renderer = DocumentRenderer(engine: engine, config: config)

        let mainBlock = AdocBlock.paragraph(AdocParagraph(
            text: AdocText(plain: "Main"),
            meta: AdocBlockMeta()
        ))

        var sidebarMetaEarly = AdocBlockMeta()
        sidebarMetaEarly.attributes["slot"] = "sidebar"
        sidebarMetaEarly.attributes["order"] = "5"
        let sidebarEarly = AdocBlock.paragraph(AdocParagraph(
            text: AdocText(plain: "Sidebar early"),
            meta: sidebarMetaEarly
        ))

        var sidebarMetaLate = AdocBlockMeta()
        sidebarMetaLate.attributes["slot"] = "sidebar"
        sidebarMetaLate.attributes["order"] = "20"
        let sidebarLate = AdocBlock.paragraph(AdocParagraph(
            text: AdocText(plain: "Sidebar late"),
            meta: sidebarMetaLate
        ))

        var collectMeta = AdocBlockMeta()
        collectMeta.attributes["collect"] = "reqs"
        collectMeta.attributes["order"] = "2"
        let collected = AdocBlock.paragraph(AdocParagraph(
            text: AdocText(plain: "Req 1"),
            meta: collectMeta
        ))

        var attributes: [String: String?] = [:]
        attributes["slot.mode.sidebar"] = "move"

        let document = AdocDocument(
            attributes: attributes,
            blocks: [mainBlock, sidebarLate, sidebarEarly, collected]
        )

        _ = try renderer.render(document: document)

        let context = try #require(engine.lastContext)
        let xad = try #require(context["xad"] as? [String: Any])

        let slots = try #require(xad["slots"] as? [String: Any])
        let mainBlocks = plainTextBlocks(slots["main"])
        #expect(mainBlocks == ["Main", "Req 1"])

        let sidebarBlocks = plainTextBlocks(slots["sidebar"])
        #expect(sidebarBlocks == ["Sidebar early", "Sidebar late"])

        let collections = try #require(xad["collections"] as? [String: Any])
        let reqBlocks = plainTextBlocks(collections["reqs"])
        #expect(reqBlocks == ["Req 1"])
    }
}

private final class CapturingTemplateEngine: TemplateEngine {
    var lastContext: [String: Any]?

    func render(templateNamed name: String, context: [String: Any]) throws -> String {
        lastContext = context
        return ""
    }
}

private func plainTextBlocks(_ value: Any?) -> [String] {
    guard let blocks = value as? [[String: Any]] else { return [] }
    return blocks.compactMap { $0["plain"] as? String }
}
