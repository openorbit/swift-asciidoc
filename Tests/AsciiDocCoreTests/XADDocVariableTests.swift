import Testing
import AsciiDocCore

private func docRoot(from doc: AdocDocument) -> [String: XADAttributeValue] {
    guard case .dictionary(let dict) = doc.typedAttributes["doc"] else {
        return [:]
    }
    return dict
}

@Suite("XAD Document Variables")
struct XADDocVariableTests {
    @Test
    func docsetStoresScalar() {
        let src = """
        docset::[name="doc.status", value="draft"]
        """

        let parser = AdocParser()
        let doc = parser.parse(text: src, xadOptions: XADOptions(enabled: true))
        let processed = XADProcessor().apply(document: doc)
        let dict = docRoot(from: processed)
        #expect(dict["status"] == .string("draft"))
    }

    @Test
    func docpushAppendsValues() {
        let src = """
        docpush::[name="doc.sections", value={id:"sec1", title:"Intro"}]
        docpush::[name="doc.sections", value={id:"sec2", title:"Body"}]
        """

        let parser = AdocParser()
        let doc = parser.parse(text: src, xadOptions: XADOptions(enabled: true))
        let processed = XADProcessor().apply(document: doc)
        let dict = docRoot(from: processed)
        guard case .array(let sections)? = dict["sections"] else {
            Issue.record("doc.sections should be an array")
            return
        }
        #expect(sections.count == 2)
    }

    @Test
    func docputUpdatesDictionary() {
        let src = """
        docput::[name="doc.byId", key="sec1", value={title:"Intro"}]
        """

        let parser = AdocParser()
        let doc = parser.parse(text: src, xadOptions: XADOptions(enabled: true))
        let processed = XADProcessor().apply(document: doc)
        let dict = docRoot(from: processed)
        guard case .dictionary(let byId)? = dict["byId"] else {
            Issue.record("doc.byId should be a dictionary")
            return
        }
        guard case .dictionary(let entry)? = byId["sec1"] else {
            Issue.record("doc.byId.sec1 should be a dictionary")
            return
        }
        #expect(entry["title"] == .string("Intro"))
    }
}
