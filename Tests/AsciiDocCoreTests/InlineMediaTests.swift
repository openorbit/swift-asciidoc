
import Testing
@testable import AsciiDocCore

@Suite("Inline Media Tests")
struct InlineMediaTests {

    @Test
    func parse_image_macro() throws {
        let src = "Look at image:logo.png[Company Logo, 200, 100]"
        let parser = AdocParser()
        let doc = parser.parse(text: src)
        
        guard case .paragraph(let p) = doc.blocks.first else { Issue.record("Expected paragraph"); return }
        
        // Check finding the macro
        let hasImage = p.text.inlines.contains { 
            if case .inlineMacro(let name, let target, let body, _) = $0, 
               name == "image", target == "logo.png", body == "Company Logo, 200, 100" { return true }
            return false
        }
        #expect(hasImage)
    }

    @Test
    func parse_icon_macro() throws {
        let src = "Click the icon:heart[size=2x] button."
        let parser = AdocParser()
        let doc = parser.parse(text: src)
        
        guard case .paragraph(let p) = doc.blocks.first else { Issue.record("Expected paragraph"); return }
        
        let hasIcon = p.text.inlines.contains { 
            if case .inlineMacro(let name, let target, let body, _) = $0, 
               name == "icon", target == "heart", body == "size=2x" { return true }
            return false
        }
        #expect(hasIcon)
    }

    @Test
    func parse_kbd_macro() throws {
        let src = "Press kbd:[Ctrl+C] to copy."
        let parser = AdocParser()
        let doc = parser.parse(text: src)
        
        guard case .paragraph(let p) = doc.blocks.first else { Issue.record("Expected paragraph"); return }
        
        let hasKbd = p.text.inlines.contains { 
            if case .inlineMacro(let name, let target, let body, _) = $0, 
               name == "kbd", target == nil, body == "Ctrl+C" { return true }
            return false
        }
        #expect(hasKbd)
    }
}
