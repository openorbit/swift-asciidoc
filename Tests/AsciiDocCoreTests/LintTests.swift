import Testing
@testable import AsciiDocCore
@testable import AsciiDocTools

@Suite("Lint runner")
struct LintTests {

    @Test
    func semantic_break_warning_emitted() {
        let src = """
        First sentence. Second sentence.
        """
        let parser = AdocParser()
        let doc = parser.parse(text: src)

        let runner = LintRunner(
            document: doc,
            sourceText: src,
            options: .init(enableSpellcheck: false, enableSemanticBreaks: true)
        )

        let warnings = runner.run()
        #expect(warnings.contains { $0.kind == .semanticBreak && $0.line == 1 })
    }

    @Test
    func abbreviations_do_not_trigger_semantic_warning() {
        let src = """
        Use e.g. this example for clarity.
        """
        let parser = AdocParser()
        let doc = parser.parse(text: src)

        let runner = LintRunner(
            document: doc,
            sourceText: src,
            options: .init(enableSpellcheck: false, enableSemanticBreaks: true)
        )

        let warnings = runner.run()
        #expect(warnings.isEmpty)
    }

    @Test
    func spelling_rule_reports_unknown_words() {
        let src = """
        This line has a speling error.
        """
        let parser = AdocParser()
        let doc = parser.parse(text: src)

        let runner = LintRunner(
            document: doc,
            sourceText: src,
            options: .init(enableSpellcheck: true, enableSemanticBreaks: false),
            spellcheckerFactory: { _ in SpellcheckTestDouble(misspelledWords: ["speling"]) }
        )

        let warnings = runner.run()
        #expect(warnings.contains { $0.kind == .spelling && $0.line == 1 })
    }
}
