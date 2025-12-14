
import Testing
@testable import AsciiDocCore

@Suite("Inline Macro Reproduction Tests")
struct InlineMacroReproductionTests {

    @Test
    func inline_macro_with_target_e_g_image() throws {
        let src = "Look at this image:screenshot.png[Screenshot]"
        let parser = AdocParser()
        let doc = parser.parse(text: src)
        
        guard case .paragraph(let p) = doc.blocks.first else { 
            Issue.record("Expected paragraph")
            return 
        }
        
        // Currently this likely parses as text or generic macro failing to capture target
        // We expect: inlineMacro(name: "image", target: "screenshot.png", body: "Screenshot")
        
        let inlines = p.text.inlines
        let hasImage = inlines.contains { node in
            if case .inlineMacro(let name, let target, let body, _) = node {
                return name == "image" && target == "screenshot.png" && body == "Screenshot"
            }
            return false
        }
        
        #expect(hasImage, "Should parse image:screenshot.png[Screenshot] as inline macro with target")
    }

    @Test
    func inline_macro_no_target_legacy() throws {
        let src = "kbd:[Ctrl+C]"
        let parser = AdocParser()
        let doc = parser.parse(text: src)
        
        guard case .paragraph(let p) = doc.blocks.first else { 
            Issue.record("Expected paragraph")
            return 
        }
        
        let hasKbd = p.text.inlines.contains { node in
             if case .inlineMacro(let name, let target, let body, _) = node {
                return name == "kbd" && (target == nil || target?.isEmpty == true) && body == "Ctrl+C"
            }
            return false
        }
        #expect(hasKbd, "Should still parse kbd:[Ctrl+C]")
    }
}
