
import Testing
@testable import AsciiDocCore

@Suite("Inline Parser Ambiguity Tests")
struct InlineParserAmbiguityTests {

    @Test
    func text_colons_do_not_greedy_match_macros() throws {
        // "works too: stem:[...]"
        // Should parse as "works too: ", then math inline.
        // NOT macro named "too" with target " stem:".
        
        let src = "works too: stem:[x^2]"
        let parser = AdocParser()
        let doc = parser.parse(text: src)
        
        guard case .paragraph(let p) = doc.blocks.first else { 
            Issue.record("Expected paragraph")
            return 
        }
        
        // We expect:
        // 1. Text("works too: ")
        // 2. Math(kind: .latex, body: "x^2")
        
        #expect(p.text.inlines.count == 2, "Should have 2 inlines (text + math), got \(p.text.inlines.count)")
        
        if p.text.inlines.count >= 2 {
            guard case .text(let t, _) = p.text.inlines[0] else {
                Issue.record("First inline should be text")
                return
            }
            #expect(t == "works too: ")
            
            guard case .math = p.text.inlines[1] else {
                Issue.record("Second inline should be math. Got: \(p.text.inlines[1])")
                return
            }
        }
    }
}
