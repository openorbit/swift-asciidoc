import Testing
@testable import AsciiDocCore

@Suite("Tables")
struct TableTests {

    @Suite("Parsing basics")
    struct ParsingBasics {

        @Test
        func psv_table_smoke_test() {
            let input = """
            |===
            | Cell A | Cell B
            |===
            """

            let parser = AdocParser()
            let ism = parser.parse(text: input)

            #expect(ism.blocks.count == 1)

            guard case let .table(table) = ism.blocks.first else {
                #expect(Bool(false), "Expected single table block")
                return
            }

            #expect(table.format == .psv)
            #expect(table.separator == "|")

            // Row and cell parsing
            #expect(table.rows == ["| Cell A | Cell B"])

            let cells = table.cells
            #expect(cells.count == 1)
            #expect(cells[0] == ["Cell A", "Cell B"])
        }

        @Test
        func simple_table_two_rows() {
            let src = """
            |===
            | a | b | c
            | 1 | 2 | 3
            |===
            """
            let parser = AdocParser()
            let doc = parser.parse(text: src)
            #expect(doc.blocks.count == 1)
            guard case .table(let t) = doc.blocks[0] else { Issue.record("expected table"); return }
            #expect(t.rows.count == 2)
            let parsed = t.parsedRows
            #expect(parsed.count == 2)
            #expect(parsed[0].map(\.text) == ["a","b","c"])
            #expect(parsed[1].map(\.text) == ["1","2","3"])
        }

        @Test
        func psv_table_basic_cells() {
            let input = """
            |===
            | Cell A | Cell B
            |===
            """

            let parser = AdocParser()
            let ism = parser.parse(text: input)

            #expect(ism.blocks.count == 1)

            guard case let .table(table) = ism.blocks.first else {
                #expect(Bool(false), "Expected single table block")
                return
            }

            #expect(table.format == .psv)
            #expect(table.separator == "|")
            #expect(table.styleChar == "|")

            // One data row
            #expect(table.rows == ["| Cell A | Cell B"])

            let cells = table.cells
            #expect(cells.count == 1)
            #expect(cells[0] == ["Cell A", "Cell B"])
        }

        @Test
        func table_escapes_pipes() {
            let src = """
            |===
            | a\\|a | b | c
            | x | y\\|z | w
            |===
            """
            let parser = AdocParser()
            let doc = parser.parse(text: src)
            guard case .table(let t) = doc.blocks.first else { Issue.record("expected table"); return }
            #expect(t.rows.count == 2)
            let parsed = t.parsedRows
            #expect(parsed.count == 2)
            #expect(parsed[0].map(\.text) == ["a|a","b","c"])
            #expect(parsed[1].map(\.text) == ["x","y|z","w"])
        }

        @Test
        func psv_table_escaping() {
            let input = """
            |===
            | A\\|B | C\\\\D
            |===
            """

            let parser = AdocParser()
            let ism = parser.parse(text: input)

            #expect(ism.blocks.count == 1)

            guard case let .table(table) = ism.blocks.first else {
                #expect(Bool(false), "Expected single table block")
                return
            }

            #expect(table.format == .psv)
            #expect(table.separator == "|")

            // Raw row
            #expect(table.rows == ["| A\\|B | C\\\\D"])

            let cells = table.cells
            #expect(cells.count == 1)

            // Explanation:
            //  `A\\|B`  -> "A|B"
            //  `C\\\\D` -> "C\\D"
            #expect(cells[0] == ["A|B", "C\\D"])
        }
    }

    @Suite("Format parsing")
    struct FormatParsing {

        @Test
        func csv_table_smoke_test() {
            let input = """
            ,===
            a,b,c
            ,===
            """

            let parser = AdocParser()
            let ism = parser.parse(text: input)
            #expect(ism.blocks.count == 1)

            guard case let .table(table) = ism.blocks.first else {
                #expect(Bool(false), "Expected single table block")
                return
            }

            #expect(table.format == .csv)
            #expect(table.separator == ",")
            #expect(table.styleChar == ",")
            #expect(table.rows == ["a,b,c"])
        }

        @Test
        func csv_table_basic_cells() {
            let input = """
            ,===
            a,b,,d
            ,===
            """

            let parser = AdocParser()
            let ism = parser.parse(text: input)

            #expect(ism.blocks.count == 1)

            guard case let .table(table) = ism.blocks.first else {
                #expect(Bool(false), "Expected single table block")
                return
            }

            #expect(table.format == .csv)
            #expect(table.separator == ",")

            #expect(table.rows == ["a,b,,d"])

            let cells = table.cells
            #expect(cells.count == 1)
            #expect(cells[0] == ["a", "b", "", "d"])
        }

        @Test
        func tsv_table_basic_cells() {
            let input = """
            :===
            col1\tcol2\tcol3
            :===
            """

            let parser = AdocParser()
            let ism = parser.parse(text: input)

            #expect(ism.blocks.count == 1)

            guard case let .table(table) = ism.blocks.first else {
                #expect(Bool(false), "Expected single table block")
                return
            }

            // In our current mapping, ':' fences default to .dsv with ':' separator,
            // so this is just illustrative. Once you wire format=tsv from attributes,
            // this test can assert `.tsv` and `\t` separator instead.
            #expect(table.format == .dsv || table.format == .tsv)

            let cells = table.cells
            #expect(cells.count == 1)
        }

        @Test
        func dsv_table_basic_cells() {
            let input = """
            :===
            a:b::d
            :===
            """

            let parser = AdocParser()
            let ism = parser.parse(text: input)

            #expect(ism.blocks.count == 1)

            guard case let .table(table) = ism.blocks.first else {
                #expect(Bool(false), "Expected single table block")
                return
            }

            // With current inferTableFormat, ':' → .dsv, ':' separator
            #expect(table.format == .dsv)
            #expect(table.separator == ":")


            #expect(table.rows == ["a:b::d"])

            let cells = table.cells
            #expect(cells.count == 1)
            #expect(cells[0] == ["a", "b", "", "d"])
        }

        @Test
        func table_block_attributes_override_fence() {
            let input = """
            [format=csv,separator=;]
            |===
            a;b;c
            |===
            """

            let parser = AdocParser()
            let ism = parser.parse(text: input)

            #expect(ism.blocks.count == 1)

            guard case let .table(table) = ism.blocks.first else {
                #expect(Bool(false), "Expected single table block")
                return
            }

            // Even though the fence is '|===', attributes say csv + ';'
            #expect(table.format == .csv)
            #expect(table.separator == ";")

            #expect(table.rows == ["a;b;c"])
            let cells = table.cells
            #expect(cells.count == 1)
            #expect(cells[0] == ["a", "b", "c"])

            // And attributes should be stored on meta
            #expect(table.meta.attributes["format"] == "csv")
            #expect(table.meta.attributes["separator"] == ";")
        }
    }

    @Suite("Options & layout")
    struct OptionsAndLayout {

        @Test
        func table_with_header_option_marks_first_row() {
            let src = """
            [options="header"]
            |===
            | A | B | C
            | 1 | 2 | 3
            |===
            """
            let parser = AdocParser()
            let doc = parser.parse(text: src)
            #expect(doc.blocks.count == 1)
            guard case .table(let t) = doc.blocks[0] else { Issue.record("expected table"); return }
            #expect(t.headerRowCount == 1)
            #expect(t.parsedRows.count == 2)
        }

        @Test
        func table_with_blank_row_marks_first_row_as_header() {
            let src = """
            |===
            | A | B | C

            | 1 | 2 | 3
            |===
            """
            let parser = AdocParser()
            let doc = parser.parse(text: src)
            #expect(doc.blocks.count == 1)
            guard case .table(let t) = doc.blocks[0] else { Issue.record("expected table"); return }
            #expect(t.headerRowCount == 1)
            #expect(t.parsedRows.count == 2)
        }

        @Test
        func table_with_cols_alignment_parses_aligns() {
            let src = """
            [cols="l,c,r"]
            |===
            | a | b | c
            | 1 | 2 | 3
            |===
            """
            let parser = AdocParser()
            let doc = parser.parse(text: src)
            guard case .table(let t) = doc.blocks.first else { Issue.record("expected table"); return }
            #expect(t.columnAlignments?.count == 3)
            #expect(t.columnAlignments?[0] == .left)
            #expect(t.columnAlignments?[1] == .center)
            #expect(t.columnAlignments?[2] == .right)
        }

        @Test
        func table_between_blocks_and_lists() {
            let src = """
            Before.

            |===
            | a | b
            | 1 | 2
            |===

            * after
            """
            let parser = AdocParser()
            let doc = parser.parse(text: src)
            #expect(doc.blocks.count == 3)
            guard case .paragraph(let p0) = doc.blocks[0] else { Issue.record("expected paragraph"); return }
            #expect(p0.text.plain == "Before.")
            guard case .table(let t) = doc.blocks[1] else { Issue.record("expected table"); return }
            #expect(t.rows.count == 2)
            guard case .list(let list) = doc.blocks[2] else { Issue.record("expected ulist"); return }
            #expect(list.items.count == 1)
        }
    }

    @Suite("Cell metadata")
    struct CellMetadata {

        @Test
        func psv_table_cell_specifiers() {
            let input = """
            |===
            2+|Spans two columns
            .2+^h|Group Heading
            | cell A | cell B
            | cell C | cell D
            |===
            """

            let parser = AdocParser()
            let ism = parser.parse(text: input)

            guard case let .table(table) = ism.blocks.first else {
                #expect(Bool(false), "Expected single table block")
                return
            }

            let parsed = table.parsedRows
            #expect(parsed.count == 4)
            #expect(parsed[0].count == 1)
            #expect(parsed[0][0].columnSpan == 2)
            #expect(parsed[0][0].text == "Spans two columns")

            #expect(parsed[1].count == 1)
            #expect(parsed[1][0].rowSpan == 2)
            #expect(parsed[1][0].style == .header)
            #expect(parsed[1][0].horizontalAlignment == .center)
            #expect(parsed[1][0].text == "Group Heading")
        }

        @Test
        func psv_table_multiline_rows() {
            let input = """
            |===
            | Backend | Description

            | HTML
            | Browser-friendly output used by the showcase script.

            | DocBook
            | Useful for downstream toolchains that understand DocBook 5 XML.

            | LaTeX
            | TeX-flavoured output that can be compiled to PDF.
            |===
            """

            let parser = AdocParser()
            let ism = parser.parse(text: input)

            guard case let .table(table) = ism.blocks.first else {
                #expect(Bool(false), "Expected single table block")
                return
            }

            #expect(table.headerRowCount == 1)
            let cells = table.cells
            #expect(cells.count == 4)
            #expect(cells[0] == ["Backend", "Description"])
            #expect(cells[1] == ["HTML", "Browser-friendly output used by the showcase script."])
            #expect(cells[2] == ["DocBook", "Useful for downstream toolchains that understand DocBook 5 XML."])
            #expect(cells[3] == ["LaTeX", "TeX-flavoured output that can be compiled to PDF."])
        }
    }

    @Suite("Scanner integration")
    struct ScannerIntegration {

        @Test
        func psv_table_preserves_text_and_blank() {
            let src = """
            Before line

            |===
            |A |B
            |1 |2

            |3 |4
            |===
            After line
            """

            let toks = LineScanner().scan(src)

            // Boundaries present and ordered
            #expect(TableScanner.boundaryChars(toks) == ["|","|"])

            // Exactly one inside slice
            let slices = TableScanner.insideTableSlices(toks)
            #expect(slices.count == 1)

            // Inside the table: only text and blank
            #expect(TableScanner.onlyKinds(slices[0], allowed: ["text","blank"]))

            // Outside the table, normal text exists
            let ks = TableScanner.kinds(toks)
            #expect(ks.contains("text"))
        }

        @Test
        func csv_table_scans_with_text_only_inside() {
            let src = """
            ,===
            a,b,c
            "has,comma",2,3

            4,5,6
            ,===
            """

            let toks = LineScanner().scan(src)
            #expect(TableScanner.boundaryChars(toks) == [",",","])

            let slices = TableScanner.insideTableSlices(toks)
            #expect(slices.count == 1)
            #expect(TableScanner.onlyKinds(slices[0], allowed: ["text","blank"]))
        }

        @Test
        func tsv_table_scans_with_text_only_inside() {
            let src = """
            !===
            a\tb\tc
            1\t2\t3
            !===
            """

            let toks = LineScanner().scan(src)
            #expect(TableScanner.boundaryChars(toks) == ["!","!"] )

            let slices = TableScanner.insideTableSlices(toks)
            #expect(slices.count == 1)
            #expect(TableScanner.onlyKinds(slices[0], allowed: ["text"]))
        }

        @Test
        func lists_inside_tables_are_not_tokenized_as_lists() {
            let src = """
            |===
            * not-a-list
            1. not-ordered
            .. not-dot-nested
            |===
            """

            let toks = LineScanner().scan(src)
            let slices = TableScanner.insideTableSlices(toks)
            #expect(slices.count == 1)

            // No listItem inside the table
            let insideKinds = TableScanner.kinds(slices[0])
            #expect(!insideKinds.contains(where: { $0.hasPrefix("li(") }))
            // They should be plain text
            #expect(insideKinds.allSatisfy { $0 == "text" })
        }

        @Test
        func back_to_back_tables_toggle_state_independently() {
            let src = """
            |===
            |A
            |===
            ,===
            a,b
            ,===
            """

            let toks = LineScanner().scan(src)
            #expect(TableScanner.boundaryChars(toks) == ["|","|",",",","])

            let slices = TableScanner.insideTableSlices(toks)
            #expect(slices.count == 2)
            #expect(TableScanner.onlyKinds(slices[0], allowed: ["text"]))
            #expect(TableScanner.onlyKinds(slices[1], allowed: ["text"]))
        }

        @Test
        func preserves_blank_lines_inside_table() {
            let src = """
            |===
            |header1 |header2

            |cell1 |cell2
            |===
            """

            let toks = LineScanner().scan(src)
            let slices = TableScanner.insideTableSlices(toks)
            #expect(slices.count == 1)

            // There should be a blank token due to the empty line
            #expect(TableScanner.kinds(slices[0]).contains("blank"))
        }

        @Test
        func normal_markers_outside_table_are_classified_normally() {
            let src = """
            * outside-list
            |===
            * inside table (should be text)
            |===
            1. outside-ordered
            """

            let toks = LineScanner().scan(src)
            let ks = TableScanner.kinds(toks)

            // One unordered list item outside table
            #expect(ks.contains(where: { $0.hasPrefix("li(u:*") }))

            // One ordered list item outside table
            #expect(ks.contains(where: { $0.hasPrefix("li(o,lvl=") }))

            // Inside slice must be text only
            let slices = TableScanner.insideTableSlices(toks)
            #expect(slices.count == 1)
            #expect(TableScanner.onlyKinds(slices[0], allowed: ["text"]))
        }
    }

    @Suite("Rendering")
    struct Rendering {

        @Test
        func testTableRenderingPlaceholder() {
            let table = AdocTable(
                format: .psv,
                separator: "|",
                styleChar: "|",
                rows: ["|Cell A|Cell B", "|Cell C|Cell D"]
            )
            // Expecting valid AsciiDoc table output
            let output = table.renderAsAsciiDoc()
            #expect(output.contains("|==="))
            #expect(output.contains("|Cell A|Cell B"))
            #expect(output.contains("|Cell C|Cell D"))
        }
    }
}

private enum TableScanner {
    static func kinds(_ tokens: [Token]) -> [String] {
        tokens.map { t in
            switch t.kind {
            case .blank: return "blank"
            case .text: return "text"
            case .blockMeta: return "blockmeta"
            case .continuation: return "+"
            case .directive: return "directive"
            case .attrSet: return "attrSet"
            case .attrUnset: return "attrUnset"
            case .listItem(let k, let lvl, _, _, _):
                let tag = { () -> String in
                    switch k {
                    case .unordered(let c): return "u:\(c)"
                    case .ordered: return "o"
                    case .callout: return "callout"
                    }
                }()
                return "li(\(tag),lvl=\(lvl))"
            case .dlistItem: return "dlistItem"
            case .blockFence(_, let len): return "fence(len=\(len))"
            case .atxSection(let n, _): return "h\(n)"
            case .tableBoundary(let c): return "table(\(c))"
            case .error: return "error"
            }
        }
    }

    static func boundaryChars(_ tokens: [Token]) -> [Character] {
        tokens.compactMap {
            if case .tableBoundary(let c) = $0.kind { return c }
            return nil
        }
    }

    static func insideTableSlices(_ tokens: [Token]) -> [[Token]] {
        // Split tokens into slices that are between .tableBoundary pairs
        var slices: [[Token]] = []
        var current: [Token] = []
        var depth = 0 as Int

        for t in tokens {
            if case .tableBoundary = t.kind {
                if depth > 0 {
                    depth -= 1
                    slices.append(current)
                    current.removeAll()
                } else {
                    depth += 1
                }
                continue
            }
            if depth > 0 { current.append(t) }
        }
        return slices
    }

    static func onlyKinds(_ tokens: [Token], allowed: Set<String>) -> Bool {
        kinds(tokens).allSatisfy { allowed.contains($0) }
    }
}
