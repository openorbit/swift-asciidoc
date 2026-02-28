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

    @Test
    func invalidIfExpressionWarns() {
        let src = """
        if::[cond="{flag} == "]
        Hello
        end::if[]
        """

        let parser = AdocParser()
        let doc = parser.parse(text: src, xadOptions: XADOptions(enabled: true))
        let processed = XADProcessor().apply(document: doc)
        #expect(processed.warnings.contains { $0.message.contains("invalid if expression") })
    }

    @Test
    func invalidForExpressionWarns() {
        let src = """
        for::[in={list}
        * item
        end::for[]
        """

        let parser = AdocParser()
        let doc = parser.parse(text: src, xadOptions: XADOptions(enabled: true))
        let processed = XADProcessor().apply(document: doc)
        #expect(processed.warnings.contains { $0.message.contains("invalid for in expression") })
    }

    @Test
    func forArrayMissingIndexWarns() {
        let src = """
        :list: ["Ann"]

        for::[in=list, item=name]
        * {name}
        end::for[]
        """

        let parser = AdocParser()
        let doc = parser.parse(text: src, xadOptions: XADOptions(enabled: true))
        let processed = XADProcessor().apply(document: doc)
        #expect(processed.warnings.contains { $0.message.contains("requires index and item") })
    }

    @Test
    func forArrayWithKeyValueWarns() {
        let src = """
        :list: ["Ann"]

        for::[in=list, index=i, item=name, key=k, value=v]
        * {i}: {name}
        end::for[]
        """

        let parser = AdocParser()
        let doc = parser.parse(text: src, xadOptions: XADOptions(enabled: true))
        let processed = XADProcessor().apply(document: doc)
        #expect(processed.warnings.contains { $0.message.contains("does not use key/value") })
    }

    @Test
    func forDictionaryWithIndexItemWarns() {
        let src = """
        :map: {a: 1}

        for::[in=map, key=k, value=v, index=i, item=name]
        * {k} = {v}
        end::for[]
        """

        let parser = AdocParser()
        let doc = parser.parse(text: src, xadOptions: XADOptions(enabled: true))
        let processed = XADProcessor().apply(document: doc)
        #expect(processed.warnings.contains { $0.message.contains("does not use index/item") })
    }

    @Test
    func forDictionaryMissingKeyWarns() {
        let src = """
        :map: {a: 1}

        for::[in=map, value=v]
        * {v}
        end::for[]
        """

        let parser = AdocParser()
        let doc = parser.parse(text: src, xadOptions: XADOptions(enabled: true))
        let processed = XADProcessor().apply(document: doc)
        #expect(processed.warnings.contains { $0.message.contains("requires key and value") })
    }

    @Test
    func unknownVariableInIfWarns() {
        let src = """
        if::[cond="{missing} == true"]
        Hello
        end::if[]
        """

        let parser = AdocParser()
        let doc = parser.parse(text: src, xadOptions: XADOptions(enabled: true))
        let processed = XADProcessor().apply(document: doc)
        #expect(processed.warnings.contains { $0.message.contains("unknown variable in if expression") })
    }

    @Test
    func unknownVariableInForWarns() {
        let src = """
        for::[in=missing, index=i, item=name]
        * {name}
        end::for[]
        """

        let parser = AdocParser()
        let doc = parser.parse(text: src, xadOptions: XADOptions(enabled: true))
        let processed = XADProcessor().apply(document: doc)
        #expect(processed.warnings.contains { $0.message.contains("unknown variable in for expression") })
    }

    @Test
    func nonIterableForWarns() {
        let src = """
        :value: 42

        for::[in=value, index=i, item=name]
        * {name}
        end::for[]
        """

        let parser = AdocParser()
        let doc = parser.parse(text: src, xadOptions: XADOptions(enabled: true))
        let processed = XADProcessor().apply(document: doc)
        #expect(processed.warnings.contains { $0.message.contains("expects array or dictionary") })
    }

    @Test
    func typeMismatchComparisonWarns() {
        let src = """
        :flag: true

        if::[cond="{flag} > 1"]
        Hello
        end::if[]
        """

        let parser = AdocParser()
        let doc = parser.parse(text: src, xadOptions: XADOptions(enabled: true))
        let processed = XADProcessor().apply(document: doc)
        #expect(processed.warnings.contains { $0.message.contains("type mismatch in comparison") })
    }
}
