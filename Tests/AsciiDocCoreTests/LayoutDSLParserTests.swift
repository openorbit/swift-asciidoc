import Testing
import AsciiDocCore

@Suite("Layout DSL Parser")
struct LayoutDSLParserTests {
    @Test
    func parsesSimpleLayoutTree() {
        let source = """
        pages[
          page(master:"title")[
            stack(gap:"6mm")[
              text(get("doctitle")),
              flow(slot("titlemeta"))
            ]
          ],
          page(master:"default")[
            grid(def:get("grid.body"))[
              place(area:"main")[ flow(slot("main"), scope:"chapter") ],
              place(area:"sidebar")[ flow(slot("sidebar")) ]
            ],
            sink(kind:"footnote", scope:"page")
          ]
        ]
        """
        let parser = LayoutDSLParser()
        let (program, warnings) = parser.parse(text: source)
        #expect(warnings.isEmpty)
        #expect(program?.expressions.isEmpty == false)
        if case .node(let root)? = program?.expressions.first {
            #expect(root.name == "pages")
            #expect(root.children.count == 2)
        } else {
            Issue.record("Expected root pages node")
        }
    }

    @Test
    func supportsCommentsAndTrailingSeparators() {
        let source = """
        // header comment
        pages[
          page(master:"title")[text("Hello")], // inline comment
        ];
        """
        let parser = LayoutDSLParser()
        let (program, warnings) = parser.parse(text: source)
        #expect(warnings.isEmpty)
        #expect(program?.expressions.count == 1)
    }

    @Test
    func parsesRefsAndIndexes() {
        let source = """
        grid(def:get("grid.body"))[text(get("style.font.body"))]
        foo.bar[0]
        """
        let parser = LayoutDSLParser()
        let (program, warnings) = parser.parse(text: source)
        #expect(warnings.isEmpty)
        #expect(program?.expressions.count == 2)
    }

    @Test
    func warnsOnMissingClosers() {
        let source = "pages[ page(master:\"title\")[ text(\"Hi\") ]"
        let parser = LayoutDSLParser()
        let (_, warnings) = parser.parse(text: source)
        #expect(!warnings.isEmpty)
    }

    @Test
    func parsesDictsAndArrays() {
        let source = """
        grid(def:{columns:["2fr","1fr"], rows:["auto"], colGap:"8mm"})
        """
        let parser = LayoutDSLParser()
        let (program, warnings) = parser.parse(text: source)
        #expect(warnings.isEmpty)
        #expect(program?.expressions.count == 1)
    }
}
