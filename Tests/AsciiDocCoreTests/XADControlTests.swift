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
        case .list(let list):
            for item in list.items {
                out.append(item.principal.plain)
                out.append(contentsOf: paragraphTexts(from: item.blocks))
            }
        case .dlist(let dlist):
            for item in dlist.items {
                out.append(item.term.plain)
                if let principal = item.principal {
                    out.append(principal.plain)
                }
                out.append(contentsOf: paragraphTexts(from: item.blocks))
            }
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

private func listItemTexts(from blocks: [AdocBlock]) -> [String] {
    var out: [String] = []
    for block in blocks {
        switch block {
        case .list(let list):
            out.append(contentsOf: list.items.map { $0.principal.plain })
        case .section(let section):
            out.append(contentsOf: listItemTexts(from: section.blocks))
        default:
            continue
        }
    }
    return out
}

@Suite("XAD Control Directives")
struct XADControlTests {
    @Test
    func ifElseBranches() {
        let src = """
        :flag: true

        if::[cond="{flag} == true"]
        Hello
        elif::[cond="{flag} == false"]
        No
        else::[]
        Other
        end::if[]
        """

        let parser = AdocParser()
        let doc = parser.parse(text: src, xadOptions: XADOptions(enabled: true))
        let processed = XADProcessor().apply(document: doc)
        let paras = paragraphTexts(from: processed.blocks)
        #expect(paras.contains("Hello"))
        #expect(!paras.contains("No"))
        #expect(!paras.contains("Other"))
    }

    @Test
    func forLoopArrayExpansion() {
        let src = """
        :list: ["Ann", "Bob"]

        for::[in=list, index=i, item=name]
        * {i}: {name}
        end::for[]
        """

        let parser = AdocParser()
        let doc = parser.parse(text: src, xadOptions: XADOptions(enabled: true))
        let processed = XADProcessor().apply(document: doc)
        let items = listItemTexts(from: processed.blocks)
        #expect(items.contains("0: Ann"))
        #expect(items.contains("1: Bob"))
    }

    @Test
    func endWithoutOpenWarns() {
        let src = """
        end::[]
        """

        let parser = AdocParser()
        let doc = parser.parse(text: src, xadOptions: XADOptions(enabled: true))
        let processed = XADProcessor().apply(document: doc)
        #expect(processed.warnings.contains { $0.message.contains("end without open") })
    }

    @Test
    func elseWithoutIfWarns() {
        let src = """
        else::[]
        Hello
        """

        let parser = AdocParser()
        let doc = parser.parse(text: src, xadOptions: XADOptions(enabled: true))
        let processed = XADProcessor().apply(document: doc)
        #expect(processed.warnings.contains { $0.message.contains("else without open if") })
    }

    @Test
    func endTypeMismatchWarns() {
        let src = """
        :list: ["Ann"]

        for::[in=list, index=i, item=name]
        * {i}: {name}
        end::if[]
        """

        let parser = AdocParser()
        let doc = parser.parse(text: src, xadOptions: XADOptions(enabled: true))
        let processed = XADProcessor().apply(document: doc)
        #expect(processed.warnings.contains { $0.message.contains("does not match current for block") })
    }
}
