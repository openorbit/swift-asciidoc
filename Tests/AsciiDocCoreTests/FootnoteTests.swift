
import Testing
@testable import AsciiDocCore
@testable import AsciiDocRender

struct FootnoteTests {

    @Test func parsingFootnote() async throws {
        let text = "Text with footnote:[Some *bold* content]."
        let inlines = parseInlines(text, baseSpan: nil)
        
        #expect(inlines.count == 3) // Text, Footnote, Text
        
        guard case .text(let s1, _) = inlines[0] else {
            #expect(Bool(false), "Expected start text")
            return
        }
        #expect(s1 == "Text with ")

        guard case .footnote(let content, let ref, let id, _) = inlines[1] else {
            #expect(Bool(false), "Expected footnote node")
            return
        }
        #expect(id == nil) // Not resolved yet parsing-time
        #expect(ref == nil) 
        #expect(content.count == 3) // Some, bold, content.
        
        guard case .text(let s2, _) = inlines[2] else {
            #expect(Bool(false), "Expected end text")
            return
        }
        #expect(s2 == ".")
    }
    
    @Test func attachedFootnoteAndIDs() async throws {
        // "Wordfootnote:[text]" should parse
        let text = "Wordfootnote:myid[text]."
        let inlines = parseInlines(text, baseSpan: nil)
        
        #expect(inlines.count == 3) // Word, Footnote, .
        
        guard case .text(let w, _) = inlines[0] else { #expect(Bool(false)); return }
        #expect(w == "Word")
        
        guard case .footnote(let content, let ref, let id, _) = inlines[1] else { 
            #expect(Bool(false), "Expected footnote with ref") 
            return 
        }
        #expect(ref == "myid")
        #expect(content.count == 1)
        
        // Also test reference
        let textRef = "Ref to footnote:myid[]."
        let inlinesRef = parseInlines(textRef, baseSpan: nil)
        guard case .footnote(let cRef, let ref2, _, _) = inlinesRef[1] else { return } 
        // actually index 1 is " to ", index 2 is "footnote..."
        #expect(ref2 == "myid")
        #expect(cRef.isEmpty)
    }

    @Test func resolvingFootnotes() async throws {
        // Create a fake doc with footnotes
        let p = AdocParagraph(text: AdocText(plain: "A footnote:[one] and another footnote:[two]."))
        let doc = AdocDocument(blocks: [.paragraph(p)])
        
        let resolution = FootnoteResolver().resolve(doc)
        
        #expect(resolution.definitions.count == 2)
        #expect(resolution.definitions[0].id == 1)
        #expect(resolution.definitions[1].id == 2)
        
        // Inspect resolved document block
        guard let pResolved = resolution.document.blocks.first,
              case .paragraph(let pr) = pResolved else {
            #expect(Bool(false), "Expected resolved paragraph")
            return 
        }
        
        // Inlines: "A ", Footnote(id=1), " and another ", Footnote(id=2), "."
        #expect(pr.text.inlines.count == 5)
        
        if case .footnote(_, _, let id, _) = pr.text.inlines[1] {
            #expect(id == 1)
        } else {
            #expect(Bool(false), "Expected footnote 1")
        }
    }

    @Test func resolvingFootnoteReferences() async throws {
        // Test ref resolution: footnote:foo[Text] ... footnote:foo[]
        let src = "Def footnote:foo[Main]. Ref footnote:foo[]."
        let p = AdocParagraph(text: AdocText(plain: src))
        // Note: AdocText(plain:) parses internally using default parser? 
        // No, AdocText(plain:) creates a .text node. It does NOT parse markup!
        // I need to parse inlines manually for this test to be realistic if I'm testing Resolver on pre-parsed nodes.
        // Or construct the nodes.
        
        // Constructing nodes manually to simulate parsed output:
        let content = [AdocInline.text("Main", span: nil)]
        let defNode = AdocInline.footnote(content: content, ref: "foo", id: nil, span: nil)
        let refNode = AdocInline.footnote(content: [], ref: "foo", id: nil, span: nil)
        
        let inlines: [AdocInline] = [
            .text("Def ", span: nil),
            defNode,
            .text(". Ref ", span: nil),
            refNode,
            .text(".", span: nil)
        ]
        
        let p2 = AdocParagraph(text: AdocText(inlines: inlines, span: nil))
        let doc = AdocDocument(blocks: [.paragraph(p2)])
        
        let resolution = FootnoteResolver().resolve(doc)
        
        #expect(resolution.definitions.count == 1)
        let def = resolution.definitions[0]
        #expect(def.id == 1)
        // Check content?
        
        // Check resolved nodes
        guard let pr = resolution.document.blocks.first as? AdocBlock,
              case .paragraph(let par) = pr else {
            return
        }
        
        let resInlines = par.text.inlines
        // 1: Def
        // 2: Footnote(id=1, content="Main")
        if case .footnote(_, _, let id, _) = resInlines[1] {
            #expect(id == 1)
        } else { #expect(Bool(false), "Expected def has id 1") }
        
        // 4: Ref
        // 5: Footnote(id=1, content=[]) - should reuse ID 1
        if case .footnote(let c, _, let id, _) = resInlines[3] {
            #expect(id == 1)
            #expect(c.isEmpty)
        } else { #expect(Bool(false), "Expected ref has id 1") }
    }

    @Test func htmlRenderingFootnotes() async throws {
         let content: [AdocInline] = [.footnote(content: [.text("Note", span: nil)], ref: nil, id: 5, span: nil)]
         let html = AsciiDocRender.renderInlines(content, backend: .html5)
         
         #expect(html.contains("<sup class=\"footnote\">[<a id=\"_footnoteref_5\" class=\"footnote\" href=\"#_footnotedef_5\" title=\"View footnote.\">5</a>]</sup>"))
    }
}
