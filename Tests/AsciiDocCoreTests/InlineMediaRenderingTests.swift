
import Testing
@testable import AsciiDocCore
@testable import AsciiDocRender

@Suite("Inline Media Rendering Tests")
struct InlineMediaRenderingTests {

    @Test
    func html_image_rendering() {
        let node = AdocInline.inlineMacro(name: "image", target: "logo.png", body: "Logo, 200", span: nil)
        let html = HtmlInlineRenderer().render([node])
        // Expect: <img src="logo.png" alt="Logo" width="200">
        #expect(html.contains("<img src=\"logo.png\" alt=\"Logo\" width=\"200\">"))
    }
    
    @Test
    func html_icon_rendering() {
        let node = AdocInline.inlineMacro(name: "icon", target: "heart", body: "", span: nil)
        let html = HtmlInlineRenderer().render([node])
        // Expect: <i class="fa fa-heart"></i>
        #expect(html == "<i class=\"fa fa-heart\"></i>")
    }

    @Test
    func html_kbd_rendering() {
        let node = AdocInline.inlineMacro(name: "kbd", target: nil, body: "Ctrl+C", span: nil)
        let html = HtmlInlineRenderer().render([node])
        // Expect: <kbd>Ctrl</kbd>+<kbd>C</kbd>
        #expect(html == "<kbd>Ctrl</kbd>+<kbd>C</kbd>")
    }
    
    @Test
    func docbook_image_rendering() {
        let node = AdocInline.inlineMacro(name: "image", target: "logo.png", body: "Logo", span: nil)
        let xml = DocBookInlineRenderer().render([node])
        // Expect: <inlinemediaobject><imageobject><imagedata fileref="logo.png"/></imageobject><textobject><phrase>Logo</phrase></textobject></inlinemediaobject>
        #expect(xml.contains("<imagedata fileref=\"logo.png\"/>"))
        #expect(xml.contains("<phrase>Logo</phrase>"))
    }

    @Test
    func latex_image_rendering() {
        let node = AdocInline.inlineMacro(name: "image", target: "logo.png", body: "Logo", span: nil)
        let tex = LatexInlineRenderer().render([node])
        // Expect: \includegraphics{logo.png}
        #expect(tex == "\\includegraphics{logo.png}")
    }
}
