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
        Issue.record("Expected typed attribute 'page' to be parsed.")
        return
    }
    if case .dictionary(let pageDict) = page {
        #expect(pageDict["size"] == .string("A4"))
        if case .dictionary(let margins)? = pageDict["margins"] {
            #expect(margins["top"] == .string("24mm"))
            #expect(margins["right"] == .string("22mm"))
        } else {
            Issue.record("Expected margins to be a dictionary.")
        }
    } else {
        Issue.record("Expected 'page' to be a dictionary.")
    }

    if case .dictionary(let grid)? = doc.typedAttributes["grid"] {
        if case .array(let cols)? = grid["columns"] {
            #expect(cols.count == 2)
            #expect(cols.first == .string("2fr"))
            #expect(cols.last == .string("1fr"))
        } else {
            Issue.record("Expected grid.columns to be an array.")
        }
    } else {
        Issue.record("Expected typed attribute 'grid' to be a dictionary.")
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
            Issue.record("Expected typed attribute 'page' to be parsed with JSON5 syntax.")
            return
        }
        if case .dictionary(let pageDict) = page {
            #expect(pageDict["size"] == .string("A4"))
            if case .dictionary(let margins)? = pageDict["margins"] {
                #expect(margins["top"] == .string("24mm"))
            } else {
                Issue.record("Expected margins to be a dictionary.")
            }
        } else {
            Issue.record("Expected 'page' to be a dictionary.")
        }
    }
}
@Test func typedAttributesParseMultilineStringContent() {
    let source = """
    :note: {"text":"line1\\nline2"}
    """
    let parser = AdocParser()
    let doc = parser.parse(text: source, xadOptions: XADOptions(enabled: true))

    guard let note = doc.typedAttributes["note"] else {
        Issue.record("Expected typed attribute 'note' to be parsed.")
        return
    }
    if case .dictionary(let noteDict) = note {
        #expect(noteDict["text"] == .string("line1\nline2"))
    } else {
        Issue.record("Expected 'note' to be a dictionary.")
    }
}

@Test func typedAttributesParseContinuationLines() {
    let source = """
    :page: {"size":"A4", \\
    "margins":{"top":"24mm"}}
    """
    let parser = AdocParser()
    let doc = parser.parse(text: source, xadOptions: XADOptions(enabled: true))
    guard let page = doc.typedAttributes["page"] else {
        Issue.record("Expected typed attribute 'page' to be parsed.")
        return
    }
    if case .dictionary(let pageDict) = page {
        #expect(pageDict["size"] == .string("A4"))
        if case .dictionary(let margins)? = pageDict["margins"] {
            #expect(margins["top"] == .string("24mm"))
        } else {
            Issue.record("Expected margins to be a dictionary.")
        }
    } else {
        Issue.record("Expected 'page' to be a dictionary.")
    }
}

@Test func typedAttributesParseEscapedLeadingBraces() {
    let source = """
    :page: \\{"size":"A4"}
    :list: \\["a","b"]
    """
    let parser = AdocParser()
    let doc = parser.parse(text: source, xadOptions: XADOptions(enabled: true))

    if case .dictionary(let pageDict)? = doc.typedAttributes["page"] {
        #expect(pageDict["size"] == .string("A4"))
    } else {
        Issue.record("Expected escaped JSON object to parse.")
    }
    if case .array(let items)? = doc.typedAttributes["list"] {
        #expect(items.count == 2)
        #expect(items.first == .string("a"))
        #expect(items.last == .string("b"))
    } else {
        Issue.record("Expected escaped JSON array to parse.")
    }
}


@Test func typedAttributeParseMultilineAttr() {
    let source = """
    :page: {
        size: "A4"
    }
    :list: [
        "a", "b"
    ]
    """
    let parser = AdocParser()
    let doc = parser.parse(text: source, xadOptions: XADOptions(enabled: true))

    if case .dictionary(let pageDict)? = doc.typedAttributes["page"] {
        #expect(pageDict["size"] == .string("A4"))
    } else {
        Issue.record("Expected escaped JSON object to parse.")
    }
    if case .array(let items)? = doc.typedAttributes["list"] {
        #expect(items.count == 2)
        #expect(items.first == .string("a"))
        #expect(items.last == .string("b"))
    } else {
        Issue.record("Expected escaped JSON array to parse.")
    }
}



