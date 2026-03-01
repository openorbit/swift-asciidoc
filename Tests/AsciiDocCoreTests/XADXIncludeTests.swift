import Testing
import AsciiDocCore
import Foundation

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

private func containsInlineMacro(_ inlines: [AdocInline], name: String) -> Bool {
    for inline in inlines {
        switch inline {
        case .inlineMacro(let macroName, _, _, _):
            if macroName == name { return true }
        case .strong(let xs, _),
             .emphasis(let xs, _),
             .mono(let xs, _),
             .mark(let xs, _),
             .superscript(let xs, _),
             .subscript(let xs, _):
            if containsInlineMacro(xs, name: name) { return true }
        case .link(_, let text, _),
             .xref(_, let text, _):
            if containsInlineMacro(text, name: name) { return true }
        case .footnote(let content, _, _, _):
            if containsInlineMacro(content, name: name) { return true }
        default:
            continue
        }
    }
    return false
}

private func fixturesURL() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")
}

private func xincludeProcessor() -> XADProcessor {
    let fixtures = fixturesURL()
    return XADProcessor(
        options: .init(
            sourceURL: fixtures,
            includeResolvers: [FileSystemIncludeResolver(rootDirectory: fixtures)]
        )
    )
}

@Suite("XAD XInclude")
struct XADXIncludeTests {
    @Test
    func blockXIncludeMergesMacros() {
        let src = """
        xinclude::xinclude-block.adoc[]
        shout::[word=Hello]
        """

        let parser = AdocParser()
        let doc = parser.parse(text: src, xadOptions: XADOptions(enabled: true))
        let processed = xincludeProcessor().apply(document: doc)
        let paras = paragraphTexts(from: processed.blocks)
        #expect(paras.contains("Included paragraph."))
        #expect(paras.contains("Hello!"))
    }

    @Test
    func inlineXIncludeExpands() {
        let src = "See xinclude:xinclude-inline.adoc[]."
        let parser = AdocParser()
        let doc = parser.parse(text: src, xadOptions: XADOptions(enabled: true))
        let processed = xincludeProcessor().apply(document: doc)
        let paras = paragraphTexts(from: processed.blocks)
        #expect(paras.contains("See Inline ok."))
    }

    @Test
    func inlineXIncludeRejectsBlocks() {
        let src = "See xinclude:xinclude-blocks.adoc[]."
        let parser = AdocParser()
        let doc = parser.parse(text: src, xadOptions: XADOptions(enabled: true))
        let processed = xincludeProcessor().apply(document: doc)
        let messages = processed.warnings.map { $0.message }
        #expect(messages.contains { $0.contains("inline xinclude must resolve to a single paragraph") })
        if case .paragraph(let para) = processed.blocks.first {
            #expect(containsInlineMacro(para.text.inlines, name: "xinclude"))
        } else {
            Issue.record("Expected paragraph block in xinclude inline test")
        }
    }

    @Test
    func xincludeEffectsWarning() {
        let src = "xinclude::xinclude-effects.adoc[]"
        let parser = AdocParser()
        let doc = parser.parse(text: src, xadOptions: XADOptions(enabled: true))
        let processed = xincludeProcessor().apply(document: doc)
        let messages = processed.warnings.map { $0.message }
        #expect(messages.contains { $0.contains("xinclude uses effects not declared") })
    }

    @Test
    func xincludeEffectsAllAllows() {
        let src = "xinclude::xinclude-effects.adoc[effects=all]"
        let parser = AdocParser()
        let doc = parser.parse(text: src, xadOptions: XADOptions(enabled: true))
        let processed = xincludeProcessor().apply(document: doc)
        let messages = processed.warnings.map { $0.message }
        #expect(messages.filter { $0.contains("xinclude uses effects not declared") }.isEmpty)
    }
}
