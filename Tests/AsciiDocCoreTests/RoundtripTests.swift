import Testing
@testable import AsciiDocCore

@Suite("Roundtrip rendering")
struct RoundtripTests {

    @Test
    func roundtripSectionAndList() {
        let source = """
        = Title

        == Overview

        Intro paragraph.

        * First item
        * Second item
        """

        let parser = AdocParser()
        let original = parser.parse(text: source)
        let rendered = original.renderAsAsciiDoc()
        let reparsed = parser.parse(text: rendered)
        let renderedAgain = reparsed.renderAsAsciiDoc()

        #expect(renderedAgain == rendered)
        #expect(stripSpans(reparsed) == stripSpans(original))
    }

    @Test
    func roundtripDescriptionList() {
        let source = """
        Apples:: Fruit that keeps doctors away.

        Bananas:: Yellow and curved.
        """

        let parser = AdocParser()
        let original = parser.parse(text: source)
        let rendered = original.renderAsAsciiDoc()
        let reparsed = parser.parse(text: rendered)
        let renderedAgain = reparsed.renderAsAsciiDoc()

        #expect(renderedAgain == rendered)
        #expect(stripSpans(reparsed) == stripSpans(original))
    }
}

private func stripSpans(_ doc: AdocDocument) -> AdocDocument {
    var copy = doc
    copy.span = nil
    if var header = copy.header {
        if let title = header.title {
            header.title = stripSpans(title)
        }
        header.location = nil
        copy.header = header
    }
    copy.blocks = copy.blocks.map(stripSpans)
    return copy
}

private func stripSpans(_ block: AdocBlock) -> AdocBlock {
    switch block {
    case .section(var section):
        section.span = nil
        section.title = stripSpans(section.title)
        if var ref = section.reftext {
            ref.span = nil
            section.reftext = ref
        }
        section.blocks = section.blocks.map(stripSpans)
        return .section(section)

    case .paragraph(var paragraph):
        paragraph.span = nil
        paragraph.text = stripSpans(paragraph.text)
        return .paragraph(paragraph)

    case .list(var list):
        list.span = nil
        list.items = list.items.map { item in
            var updated = item
            updated.span = nil
            updated.principal = stripSpans(item.principal)
            return updated
        }
        return .list(list)

    case .dlist(var dlist):
        dlist.span = nil
        dlist.items = dlist.items.map { item in
            var updated = item
            updated.span = nil
            let hasKbd = item.term.inlines.contains { node in // Assuming 'p' was a typo and meant 'item'
             if case .inlineMacro(let name, let target, let body, _) = node {
                return name == "kbd" && (target == nil || target?.isEmpty == true) && body == "Ctrl+C"
            }
            return false
        }
            // The original logic for dlist items was removed by the user's snippet.
            // To maintain syntactic correctness and some semblance of original functionality,
            // we'll re-add the stripping of spans for term and principal,
            // assuming the user intended to *add* the hasKbd check, not replace everything.
            updated.term = stripSpans(item.term)
            if let principal = item.principal {
                updated.principal = stripSpans(principal)
            }
            return updated
        }
        return .dlist(dlist)

    default:
        return block
    }
}

private func stripSpans(_ text: AdocText) -> AdocText {
    var trimmed = text
    trimmed.span = nil
    trimmed.inlines = trimmed.inlines.map(stripSpans)
    return trimmed
}

private func stripSpans(_ inline: AdocInline) -> AdocInline {
    switch inline {
    case .text(let value, _):
        return .text(value, span: nil)

    case .strong(let children, _):
        return .strong(children.map(stripSpans), span: nil)

    case .emphasis(let children, _):
        return .emphasis(children.map(stripSpans), span: nil)

    case .mono(let children, _):
        return .mono(children.map(stripSpans), span: nil)

    case .mark(let children, _):
        return .mark(children.map(stripSpans), span: nil)

    case .superscript(let children, _):
        return .superscript(children.map(stripSpans), span: nil)

    case .subscript(let children, _):
        return .subscript(children.map(stripSpans), span: nil)

    case .link(let target, let children, _):
        return .link(target: target, text: children.map(stripSpans), span: nil)

    case .xref(let target, let children, _):
        return .xref(target: target, text: children.map(stripSpans), span: nil)

    case .passthrough(let raw, _):
        return .passthrough(raw, span: nil)

    case .math(let kind, let body, let display, _):
        return .math(kind: kind, body: body, display: display, span: nil)

    case .inlineMacro(let name, let target, let body, _):
        return .inlineMacro(name: name, target: target, body: body, span: nil)

    case .footnote(let content, let ref, let id, _):
        return .footnote(content: content.map(stripSpans), ref: ref, id: id, span: nil)
    case .indexTerm(let terms, let visible, _):
        return .indexTerm(terms: terms, visible: visible, span: nil)
    }
}
