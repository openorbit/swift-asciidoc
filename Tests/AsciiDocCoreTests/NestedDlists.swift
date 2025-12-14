//
//  NestedDlists.swift
//  AsciiDoc-Swift
//
//  Created by Mattias Holm on 2025-11-19.
//
import Testing
@testable import AsciiDocCore

@Suite("Nested Description Lists")
struct NestedDListTests {

    @Test
    func dlist_nested_by_marker_change() {
        let input = """
    Term 1::
    +
    SubTerm 1.1;; Desc 1.1
    SubTerm 1.2;; Desc 1.2
    
    Term 2:: Top level 2
    """

        let parser = AdocParser()
        let ism = parser.parse(text: input)

        #expect(ism.blocks.count == 1)
        guard case .dlist(let outer) = ism.blocks[0] else {
            #expect(Bool(false), "Expected outer dlist")
            return
        }

        #expect(outer.marker == "::")
        #expect(outer.items.count == 2)

        let item1 = outer.items[0]
        #expect(item1.term.plain == "Term 1")
        #expect(item1.blocks.count == 1)

        guard case .dlist(let inner) = item1.blocks[0] else {
            #expect(Bool(false), "Expected nested dlist under Term 1")
            return
        }

        #expect(inner.marker == ";;")
        #expect(inner.items.count == 2)

        let item2 = outer.items[1]
        #expect(item2.term.plain == "Term 2")
        #expect(item2.principal?.plain == "Top level 2")
    }

    @Test
    func list_item_with_dlist_via_continuation() {
        let input = """
    * Item
    +
    Term:: Desc
    """

        let parser = AdocParser()
        let ism = parser.parse(text: input)

        #expect(ism.blocks.count == 1)
        guard case .list(let list) = ism.blocks[0] else {
            #expect(Bool(false), "Expected outer block to be a list")
            return
        }

        #expect(list.items.count == 1)
        let item = list.items[0]
        #expect(item.principal.plain == "Item")

        #expect(item.blocks.count == 1)
        guard case .dlist(let dl) = item.blocks[0] else {
            #expect(Bool(false), "Expected nested dlist under list item")
            return
        }

        #expect(dl.items.count == 1)
        #expect(dl.items[0].term.plain == "Term")
        #expect(dl.items[0].principal?.plain == "Desc")
    }


    @Test
    func dlist_item_with_list_body_via_continuation() {
        let input = """
    Term::
    +
    * one
    * two
    """

        let parser = AdocParser()
        let ism = parser.parse(text: input)

        #expect(ism.blocks.count == 1)
        guard case .dlist(let dl) = ism.blocks[0] else {
            #expect(Bool(false), "Expected outer block to be a dlist")
            return
        }

        #expect(dl.items.count == 1)
        let item = dl.items[0]
        #expect(item.term.plain == "Term")

        #expect(item.blocks.count == 1)
        guard case .list(let list) = item.blocks[0] else {
            #expect(Bool(false), "Expected nested list under dlist item")
            return
        }

        #expect(list.items.count == 2)
        #expect(list.items[0].principal.plain == "one")
        #expect(list.items[1].principal.plain == "two")
    }
}
