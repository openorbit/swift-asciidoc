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
}
