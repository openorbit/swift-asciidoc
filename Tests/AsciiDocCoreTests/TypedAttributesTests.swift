import Testing
@testable import AsciiDocCore

@Test func typedAttributesParseStandardJSON() {
    let source = """
    :page: {"size":"A4","margins":{"top":"24mm","right":"22mm"}}
    :grid: {"columns":["2fr","1fr"],"gutter":"8mm"}
    """
    let parser = AdocParser()
    let doc = parser.parse(text: source, xadOptions: XADOptions(enabled: true))

    guard let page = doc.typedAttributes["page"] else {
        #expect(false, "Expected typed attribute 'page' to be parsed.")
        return
    }
    if case .dictionary(let pageDict) = page {
        #expect(pageDict["size"] == .string("A4"))
        if case .dictionary(let margins)? = pageDict["margins"] {
            #expect(margins["top"] == .string("24mm"))
            #expect(margins["right"] == .string("22mm"))
        } else {
            #expect(false, "Expected margins to be a dictionary.")
        }
    } else {
        #expect(false, "Expected 'page' to be a dictionary.")
    }

    if case .dictionary(let grid)? = doc.typedAttributes["grid"] {
        if case .array(let cols)? = grid["columns"] {
            #expect(cols.count == 2)
            #expect(cols.first == .string("2fr"))
            #expect(cols.last == .string("1fr"))
        } else {
            #expect(false, "Expected grid.columns to be an array.")
        }
    } else {
        #expect(false, "Expected typed attribute 'grid' to be a dictionary.")
    }
}

@Test func typedAttributesParseJSON5WhenAvailable() {
    if #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *) {
        let source = """
        :page: {size:"A4", margins:{top:"24mm"}}
        """
        let parser = AdocParser()
        let doc = parser.parse(text: source, xadOptions: XADOptions(enabled: true))

        guard let page = doc.typedAttributes["page"] else {
            #expect(false, "Expected typed attribute 'page' to be parsed with JSON5 syntax.")
            return
        }
        if case .dictionary(let pageDict) = page {
            #expect(pageDict["size"] == .string("A4"))
            if case .dictionary(let margins)? = pageDict["margins"] {
                #expect(margins["top"] == .string("24mm"))
            } else {
                #expect(false, "Expected margins to be a dictionary.")
            }
        } else {
            #expect(false, "Expected 'page' to be a dictionary.")
        }
    }
}
