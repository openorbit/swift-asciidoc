import Testing
@testable import AsciiDocCore

@Suite("Inline Tests")
struct InlineTests {

    @Test
    func inline_basic_emphasis_and_strong() throws {
        let src = "A *bold* and _italics_."
        let parser = AdocParser()
        let doc = parser.parse(text: src)
        guard case .paragraph(let p) = doc.blocks.first else { Issue.record("paragraph"); return }
        #expect(p.text.inlines.count == 5) // "A ", strong("bold"), " and ", emphasis("italics"), "."
    }

    @Test
    func inline_code_and_escape() throws {
        let src = "Use `x \\\\` y` literal."
        let parser = AdocParser()
        let doc = parser.parse(text: src)

        guard case .paragraph(let p) = doc.blocks.first else { Issue.record("paragraph"); return }
        guard case .text(let f, _) = p.text.inlines[0] else {Issue.record("first inline"); return}
        guard case .mono(let c, _) = p.text.inlines[1] else {Issue.record("second inline"); return}
        guard case .text(let e, _) = p.text.inlines[2] else {Issue.record("third inline"); return}
        guard case .text(let c2, _) = c[0] else {Issue.record("second inline should have text inline"); return}
        #expect(f == "Use ")
        #expect(c2 == "x \\")
        #expect(e == " y` literal.")
    }

    @Test
    func inline_equation_simple() throws {
        let src = "Euler: $e^{i\\pi}+1=0$!"
        let parser = AdocParser()
        let doc = parser.parse(text: src)

        guard case .paragraph(let p) = doc.blocks.first else { Issue.record("paragraph"); return }
        guard case .math(let kind, let body, let display, _) = p.text.inlines[1] else { Issue.record("math inline"); return }
        #expect(kind == .latex)
        #expect(display == false)
        #expect(body == "e^{i\\pi}+1=0")
    }

    @Test
    func inline_display_math_with_double_dollar() throws {
        let src = "Before $$a^2 + b^2 = c^2$$ after"
        let parser = AdocParser()
        let doc = parser.parse(text: src)

        guard case .paragraph(let p) = doc.blocks.first else { Issue.record("paragraph"); return }
        guard case .math(_, let body, let display, _) = p.text.inlines[1] else { Issue.record("math inline"); return }
        #expect(display == true)
        #expect(body == "a^2 + b^2 = c^2")
    }

    @Test
    func inline_link_macro_and_autolink() throws {
        let src = "See link:https://example.com[Example] and https://swift.org"
        let parser = AdocParser()
        let doc = parser.parse(text: src)

        guard case .paragraph(let p) = doc.blocks.first else { Issue.record("paragraph"); return }
        let nodes = p.text.inlines
        #expect(nodes.contains { if case .link(let u, _, _) = $0, u == "https://example.com" { true } else { false } })
        #expect(nodes.contains { if case .link(let u, _, _) = $0, u == "https://swift.org" { true } else { false } })
    }

    @Test
    func inline_generic_macro_detected() throws {
        let src = "kbd:[Ctrl+C]"
        let parser = AdocParser()
        let doc = parser.parse(text: src)

        guard case .paragraph(let p) = doc.blocks.first else { Issue.record("paragraph"); return }
        #expect(p.text.inlines.contains { 
            if case .inlineMacro(let n, let t, let b, _) = $0, n == "kbd", b == "Ctrl+C", t == nil { return true }
            return false 
        })
    }

    @Test
    func inline_stem_macro_produces_math() throws {
        let src = "stem:[x^2 + y^2]"
        let parser = AdocParser()
        let doc = parser.parse(text: src)

        guard case .paragraph(let p) = doc.blocks.first else { Issue.record("paragraph"); return }
        guard case .math(let kind, let body, let display, _) = p.text.inlines.first else { Issue.record("math inline"); return }
        #expect(kind == .latex)
        #expect(display == false)
        #expect(body == "x^2 + y^2")
    }

    @Test
    func inline_asciimath_macro_preserves_kind() throws {
        let src = "asciimath:[sqrt(4) = 2]"
        let parser = AdocParser()
        let doc = parser.parse(text: src)

        guard case .paragraph(let p) = doc.blocks.first else { Issue.record("paragraph"); return }
        guard case .math(let kind, let body, _, _) = p.text.inlines.first else { Issue.record("math inline"); return }
        #expect(kind == .asciimath)
        #expect(body == "sqrt(4) = 2")
    }

    @Test
    func inline_sub_and_sup() throws {
        // Subscript
        do {
            let src = "H~2~O"
            let parser = AdocParser()
            let doc = parser.parse(text: src)

            guard case .paragraph(let p) = doc.blocks.first else { Issue.record("paragraph"); return }
            #expect(p.text.inlines.count == 3)
            guard case .text("H", _) = p.text.inlines[0] else { Issue.record("text H"); return }
            guard case .`subscript`(let xs, _) = p.text.inlines[1] else { Issue.record("sub"); return }
            #expect(xs.count == 1)
            guard case .text("2", _) = xs[0] else { Issue.record("sub content"); return }
            guard case .text("O", _) = p.text.inlines[2] else { Issue.record("text O"); return }
        }

        // Superscript
        do {
            let src = "E=mc^2^"
            let parser = AdocParser()
            let doc = parser.parse(text: src)

            guard case .paragraph(let p) = doc.blocks.first else { Issue.record("paragraph"); return }
            // Expect “… mc”, “^2^ as superscript”, then nothing after
            #expect(p.text.inlines.contains { if case .superscript = $0 { true } else { false } })
        }
    }

    @Test
    func constrained_does_not_break_words() throws {
        // single markers should NOT split a word
        let src = "pre*mid*dle and under_score_d"
        let parser = AdocParser()
        let doc = parser.parse(text: src)

        guard case .paragraph(let p) = doc.blocks.first else { Issue.record("paragraph"); return }
        // Expect pure text (no strong/emphasis nodes)
        #expect(!p.text.inlines.contains { if case .strong = $0 { true } else { false } })
        #expect(!p.text.inlines.contains { if case .emphasis = $0 { true } else { false } })
    }

    @Test
    func constrained_requires_word_boundaries() throws {
        let src = "A *bold* and _italics_."
        let parser = AdocParser()
        let doc = parser.parse(text: src)
        guard case .paragraph(let p) = doc.blocks.first else { Issue.record("paragraph"); return }
        #expect(p.text.inlines.contains { if case .strong = $0 { true } else { false } })
        #expect(p.text.inlines.contains { if case .emphasis = $0 { true } else { false } })
    }

    @Test
    func unconstrained_double_works_inside_words() throws {
        let src = "pre**mid**dle and under__score__d"
        let parser = AdocParser()
        let doc = parser.parse(text: src)

        guard case .paragraph(let p) = doc.blocks.first else { Issue.record("paragraph"); return }
        // Expect strong and emphasis nodes present
        #expect(p.text.inlines.contains { if case .strong = $0 { true } else { false } })
        #expect(p.text.inlines.contains { if case .emphasis = $0 { true } else { false } })
    }
}
