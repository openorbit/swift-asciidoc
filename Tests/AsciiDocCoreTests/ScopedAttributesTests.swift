import Testing
@testable import AsciiDocCore

@Test func scopedAttributesPushPopRestoresValues() {
    var env = AttrEnv(initial: ["role": "base"], typedAttributes: [:], xadOptions: .init(enabled: true))
    env.applyAttributeSet(name: "page.margins.top", value: "24mm")

    env.pushScope()
    env.applyAttributeSet(name: "role", value: "compact")
    env.applyAttributeSet(name: "page.margins.top", value: "18mm")

    #expect(env.resolveAttribute("role") == "compact")
    #expect(env.resolveAttribute("page.margins.top") == "18mm")

    let popped = env.popScope()
    #expect(popped == true)
    #expect(env.resolveAttribute("role") == "base")
    #expect(env.resolveAttribute("page.margins.top") == "24mm")
}

@Test func scopedAttributesPopUnderflowReturnsFalse() {
    var env = AttrEnv()
    let popped = env.popScope()
    #expect(popped == false)
}
@Test func blockattrDirectiveAppliesToNextBlockOnly() {
    let source = """
    blockattr::[foo=bar]
    {foo}
    {foo}
    """
    let parser = AdocParser()
    let doc = parser.parse(text: source, xadOptions: XADOptions(enabled: true))

    let paras = doc.blocks.compactMap { if case .paragraph(let p) = $0 { return p.text.plain } else { return nil } }
    #expect(paras.count == 1)
    #expect(paras.first == "bar\nbar")
}

@Test func attrpushPopScopesAttributes() {
    let source = """
    :foo: base
    attrpush::[foo=inner]
    {foo}
    attrpop::[]
    {foo}
    """
    let parser = AdocParser()
    let doc = parser.parse(text: source, xadOptions: XADOptions(enabled: true))

    let paras = doc.blocks.compactMap { if case .paragraph(let p) = $0 { return p.text.plain } else { return nil } }
    #expect(paras.count == 2)
    #expect(paras.first == "inner")
    #expect(paras.last == "base")
}

@Test func attrsDirectiveScopesSection() {
    let source = """
    == A
    attrs::[foo=bar]
    {foo}

    == B
    {foo}
    """
    let parser = AdocParser()
    let doc = parser.parse(text: source, xadOptions: XADOptions(enabled: true))

    guard case .section(let firstSection) = doc.blocks.first else {
        Issue.record("Expected first block to be a section.")
        return
    }
    let firstParas = firstSection.blocks.compactMap { if case .paragraph(let p) = $0 { return p.text.plain } else { return nil } }
    #expect(firstParas.first == "bar")

    guard doc.blocks.count > 1, case .section(let secondSection) = doc.blocks[1] else {
        Issue.record("Expected second block to be a section.")
        return
    }
    let secondParas = secondSection.blocks.compactMap { if case .paragraph(let p) = $0 { return p.text.plain } else { return nil } }
    #expect(secondParas.first == "{foo}")
}

@Test func blockattrBlockFormAppliesToNextBlock() {
    let source = """
    [blockattr]
    ----
    :foo: bar
    ----
    {foo}
    """
    let parser = AdocParser()
    let doc = parser.parse(text: source, xadOptions: XADOptions(enabled: true))

    guard case .paragraph(let para) = doc.blocks.first else {
        Issue.record("Expected paragraph output.")
        return
    }
    #expect(para.text.plain == "bar")
}

@Test func blockattrTypedPathOverrideAppliesToNextBlock() {
    let source = """
    :page: {margins:{top:"24mm"}}
    [blockattr]
    ----
    :page.margins.top: "18mm"
    ----
    {page.margins.top}
    {page.margins.top}
    """
    let parser = AdocParser()
    let doc = parser.parse(text: source, xadOptions: XADOptions(enabled: true))

    let paras = doc.blocks.compactMap { if case .paragraph(let p) = $0 { return p.text.plain } else { return nil } }
    #expect(paras.count == 1)
    #expect(paras.first == "18mm\n18mm")
}

@Test func attrsDirectiveOutsideSectionEmitsWarning() {
    let source = """
    attrs::[foo=bar]
    {foo}
    """
    let parser = AdocParser()
    let doc = parser.parse(text: source, xadOptions: XADOptions(enabled: true))

    #expect(doc.warnings.contains { $0.message.contains("attrs") })
}

@Test func attrpopUnderflowEmitsWarning() {
    let source = """
    attrpop::[]
    """
    let parser = AdocParser()
    let doc = parser.parse(text: source, xadOptions: XADOptions(enabled: true))

    #expect(doc.warnings.contains { $0.message.contains("attrpop") })
}

@Test func blockattrWithoutFollowingBlockEmitsWarning() {
    let source = """
    blockattr::[foo=bar]
    """
    let parser = AdocParser()
    let doc = parser.parse(text: source, xadOptions: XADOptions(enabled: true))

    #expect(doc.warnings.contains { $0.message.contains("blockattr") })
}

