//
//  ScannerTests.swift
//  AsciiDoc-Swift
//
//  Created by Mattias Holm on 2025-10-29.
//

import Testing
@testable import AsciiDocCore

@Suite("Scanner")
struct ScannerTests {

    private func caseName(_ tok: LineTok) -> String {
        switch tok {
        case .blank: return "blank"
        case .text: return "text"
        case .attrSet: return "attrSet"
        case .blockMeta: return "blockMeta"
        case .attrUnset: return "attrUnset"
        case .atxSection: return "atxSection"
        case .blockFence: return "blockFence"
        case .tableBoundary: return "tableBoundary"
        case .listItem(let kind, let level, _, let check, _):
            let checkVal = check != nil ? "[\(check!)]" : nil
            switch kind {
            case .unordered(let marker):
                return "listItem:ul(\(marker))#\(level):check=\(checkVal ?? "nil")"
            case .ordered:
                return "listItem:ol#\(level):check=\(checkVal ?? "nil")"
            case .callout:
                return "listItem:callout#\(level):check=\(checkVal ?? "nil")"
            }
        case .dlistItem(_, _, _):
            return "dlistItem()"
        case .continuation: return "continuation"
        case .directive(let kind, _):
            switch kind {
            case .include: return "directive:include"
            case .ifdef: return "directive:ifdef"
            case .ifndef: return "directive:ifndef"
            case .ifeval: return "directive:ifeval"
            case .endif: return "directive:endif"
            case .other(let name): return "directive:\(name)"
            }
        case .error: return "error"
        }
    }

    private func kinds(_ tokens: [Token]) -> [String] {
        tokens.map { caseName($0.kind) }
    }

    @Test
    func blankAndText() {
        let src = """
  Hello
    
  World
  """
        let toks = LineScanner().scan(src)
        #expect(kinds(toks) == ["text", "blank", "text"])
        if case let .text(r) = toks[0].kind {
            #expect(r.lowerBound < r.upperBound)
        } else {
            Issue.record("expected text")
        }
    }

    @Test
    func atxSections() {
        let src = """
  = Doc Title
  == Section
  ====== Deep
  ======== TooDeep
  """
        let toks = LineScanner().scan(src)
        #expect(kinds(toks) == ["atxSection","atxSection","atxSection","text"])
    }


    @Test
    func blockFences() {
        let src = """
  ----
  ====
  ****
  ____
  ++++
  -----
  """
        let toks = LineScanner().scan(src)
        for t in toks {
            guard case .blockFence(_, let len) = t.kind else {
                Issue.record("expected blockFence"); continue
            }
            #expect(len >= 4)
        }
    }

    @Test
    func tableBoundary() {
        let src = """
  |===
  ,===
  !===
  |==   // not boundary, only 2 '=' after style char
  """
        let toks = LineScanner().scan(src)
        #expect(kinds(toks) == ["tableBoundary","tableBoundary","tableBoundary","text"])
    }

    @Test
    func lists() {
        let src = """
  * One
  ** Two
  - Dash
  -- DashDash
  . OrderedDot
  .. OrderedDot2
  1. Numeric
  1.1. Numeric
  * [ ] Unchecked
  * [x] Checked
  <1> Callout with space
  <2>Callout tight
"""
        let toks = LineScanner().scan(src)
        let got = kinds(toks)
        #expect(got[0]  == "listItem:ul(*)#1:check=nil")
        #expect(got[1]  == "listItem:ul(*)#2:check=nil")
        #expect(got[2]  == "listItem:ul(-)#1:check=nil")
        #expect(got[3]  == "text")
        #expect(got[4]  == "listItem:ol#1:check=nil")
        #expect(got[5]  == "listItem:ol#2:check=nil")
        #expect(got[6]  == "listItem:ol#1:check=nil")
        #expect(got[7]  == "listItem:ol#2:check=nil")
        #expect(got[8]  == "listItem:ul(*)#1:check=[ ]")
        #expect(got[9]  == "listItem:ul(*)#1:check=[x]")
        #expect(got[10] == "listItem:callout#1:check=nil")
        #expect(got[11] == "listItem:callout#1:check=nil")
    }

    @Test
    func continuation() {
        let src = """
  +
  ++
   +
  """
        let toks = LineScanner().scan(src)
        #expect(kinds(toks) == ["continuation","text","text"])
    }

    @Test
    func directives() {
        let src = """
  include::a.adoc[]
  ifdef::FOO[]
  ifndef::BAR[]
  ifeval::[1==1]
  endif::[]
  custom::payload
  """
        let toks = LineScanner().scan(src)
        #expect(kinds(toks) == [
            "directive:include",
            "directive:ifdef",
            "directive:ifndef",
            "directive:ifeval",
            "directive:endif",
            "directive:custom"
        ])
    }

    @Test
    func attributes() {
        let src = """
  :revnumber: 1.2.3
  :name!:
  """
        let toks = LineScanner().scan(src)
        // Draft scanner uses placeholder ranges for attr names/values.
        #expect(kinds(toks) == ["attrSet","attrUnset"])
    }

    @Test
    func titleAttrs() {
        let src = """
  = Test
  :revnumber: 1.2.3
  :name!:
  """
        let toks = LineScanner().scan(src)
        // Draft scanner uses placeholder ranges for attr names/values.
        #expect(kinds(toks) == ["atxSection", "attrSet", "attrUnset"])
    }


    @Test
    func sourceRangesBasic() {
        let src = "Line A\n\nLine B\n"
        let toks = LineScanner().scan(src)
        #expect(toks[0].line == 1)
        #expect(toks[1].line == 2)
        #expect(toks[2].line == 3)
        #expect(toks[0].range.start.offset < toks[0].range.end.offset)
        #expect(toks[1].range.start.offset < toks[2].range.start.offset)
    }


    @Test
    func listTest() {
        let src = """
  * One
  * Two
  """
        let toks = LineScanner().scan(src)
        #expect(kinds(toks) == ["listItem:ul(*)#1:check=nil","listItem:ul(*)#1:check=nil"])
    }

    @Test
    func mixedTest() {
        let src = """
  = Doc
  Intro para
  
  == Section
  * One
  * Two
  ----
  Verbatim
  ----
  """


        let toks = LineScanner().scan(src)
        let result = kinds(toks)

        #expect(result == ["atxSection","text","blank","atxSection","listItem:ul(*)#1:check=nil",
                           "listItem:ul(*)#1:check=nil","blockFence","text","blockFence"])

    }


    @Test
    func sidebarTest() {
        let src = """
  ****
  * phone
  * wallet
  * keys
  ****
  """


        let toks = LineScanner().scan(src)
        let result = kinds(toks)

        #expect(result == ["blockFence","listItem:ul(*)#1:check=nil","listItem:ul(*)#1:check=nil","listItem:ul(*)#1:check=nil","blockFence"])

    }
}
