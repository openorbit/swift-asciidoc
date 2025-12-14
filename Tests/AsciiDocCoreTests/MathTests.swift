import Testing
@testable import AsciiDocCore

@Suite("Math")
struct MathTests {

    @Test
    func block_stem_macro_parses_as_math_block() throws {
        let src = """
    [stem]
    stem::[x^2 + y^2]
    """
        let parser = AdocParser()
        let doc = parser.parse(text: src)

        guard case .math(let math) = doc.blocks.first else { Issue.record("expected math block"); return }
        #expect(math.display == true)
        #expect(math.kind == .latex)
        #expect(math.body == "x^2 + y^2")
    }

    @Test
    func block_asciimath_macro_uses_kind() throws {
        let src = "asciimath::[sqrt(16) = 4]"
        let parser = AdocParser()
        let doc = parser.parse(text: src)

        guard case .math(let math) = doc.blocks.first else { Issue.record("expected math block"); return }
        #expect(math.kind == .asciimath)
        #expect(math.body == "sqrt(16) = 4")
    }
}
