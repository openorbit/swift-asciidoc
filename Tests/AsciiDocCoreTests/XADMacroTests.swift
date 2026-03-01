import Testing
import AsciiDocCore

private func paragraphTexts(from blocks: [AdocBlock]) -> [String] {
    var out: [String] = []
    for block in blocks {
        switch block {
        case .paragraph(let para):
            out.append(para.text.plain)
        case .section(let section):
            out.append(contentsOf: paragraphTexts(from: section.blocks))
        case .sidebar(let sidebar):
            out.append(contentsOf: paragraphTexts(from: sidebar.blocks))
        case .example(let example):
            out.append(contentsOf: paragraphTexts(from: example.blocks))
        case .quote(let quote):
            out.append(contentsOf: paragraphTexts(from: quote.blocks))
        case .open(let open):
            out.append(contentsOf: paragraphTexts(from: open.blocks))
        case .admonition(let admonition):
            out.append(contentsOf: paragraphTexts(from: admonition.blocks))
        case .verse(let verse):
            if let text = verse.text {
                out.append(text.plain)
            }
            out.append(contentsOf: paragraphTexts(from: verse.blocks))
        default:
            continue
        }
    }
    return out
}

@Suite("XAD Macros")
struct XADMacroTests {
    @Test
    func blockMacroExpands() {
        let src = """
        macro::greet[params="name"]
        Hello {name}
        endmacro::greet[]

        greet::[name=World]
        """

        let parser = AdocParser()
        let doc = parser.parse(text: src, xadOptions: XADOptions(enabled: true))
        let processed = XADProcessor().apply(document: doc)
        let paras = paragraphTexts(from: processed.blocks)
        #expect(paras.contains("Hello World"))
    }

    @Test
    func inlineMacroExpands() {
        let src = """
        macro::hi[kind=inline, params="name"]
        Hello {name}
        endmacro::hi[]

        Say hi:[name=Bob].
        """

        let parser = AdocParser()
        let doc = parser.parse(text: src, xadOptions: XADOptions(enabled: true))
        let processed = XADProcessor().apply(document: doc)
        let paras = paragraphTexts(from: processed.blocks)
        #expect(paras.contains("Say Hello Bob."))
    }

    @Test
    func blockMacroUsesBody() {
        let src = """
        macro::wrap[params="title"]
        {title}: {body}
        endmacro::wrap[]

        wrap::[title=Note]
        This is body paragraph
        """

        let parser = AdocParser()
        let doc = parser.parse(text: src, xadOptions: XADOptions(enabled: true))
        let processed = XADProcessor().apply(document: doc)
        let paras = paragraphTexts(from: processed.blocks).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        #expect(paras.contains("Note: This is body paragraph"))
        #expect(paras.filter { $0 == "This is body paragraph" }.isEmpty)
    }

    @Test
    func macroEffectsWarning() {
        let src = """
        macro::setter[]
        docset::[name="doc.status", value="draft"]
        endmacro::setter[]

        setter::[]
        """

        let parser = AdocParser()
        let doc = parser.parse(text: src, xadOptions: XADOptions(enabled: true))
        let processed = XADProcessor().apply(document: doc)
        let messages = processed.warnings.map { $0.message }
        #expect(messages.contains { $0.contains("macro uses effects not declared") })
    }

    @Test
    func macroEffectsAllowed() {
        let src = """
        macro::setter[effects="docset"]
        docset::[name="doc.status", value="draft"]
        endmacro::setter[]

        setter::[]
        """

        let parser = AdocParser()
        let doc = parser.parse(text: src, xadOptions: XADOptions(enabled: true))
        let processed = XADProcessor().apply(document: doc)
        let messages = processed.warnings.map { $0.message }
        #expect(messages.filter { $0.contains("macro uses effects not declared") }.isEmpty)
    }

    @Test
    func blockMacroRecursionWarns() {
        let src = """
        macro::loop[]
        loop::[]
        endmacro::loop[]

        loop::[]
        """

        let parser = AdocParser()
        let doc = parser.parse(text: src, xadOptions: XADOptions(enabled: true))
        let processed = XADProcessor().apply(document: doc)
        let messages = processed.warnings.map { $0.message }
        #expect(messages.contains { $0.contains("macro recursion detected: loop") })
    }

    @Test
    func inlineMacroRecursionWarns() {
        let src = """
        macro::a[kind=inline]
        b:[]
        endmacro::a[]

        macro::b[kind=inline]
        a:[]
        endmacro::b[]

        a:[]
        """

        let parser = AdocParser()
        let doc = parser.parse(text: src, xadOptions: XADOptions(enabled: true))
        let processed = XADProcessor().apply(document: doc)
        let messages = processed.warnings.map { $0.message }
        #expect(messages.contains { $0.contains("macro recursion detected: a") })
    }
}
