import Testing
@testable import AsciiDocCore

@Suite struct ReproductionTests {
    @Test func testIncludeDirectiveIgnored() {
        let text = "include::foo.adoc[]"
        let doc = AdocParser().parse(text: text)
        
        // Now expected to be a block macro
        guard case .blockMacro(let m) = doc.blocks.first else {
            Issue.record("Expected blockMacro, got \(String(describing: doc.blocks.first))")
            return
        }
        #expect(m.name == "include")
        #expect(m.target == "foo.adoc")
    }
}
