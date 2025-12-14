//
// Copyright (c) 2025 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

import Foundation
import AsciiDocCore

struct IndexEntry: Encodable {
    let primary: String
    var secondary: [String: [String]] = [:] // Secondary -> [Tertiary]
    var locations: [Int] = [] // Potentially store anchors/IDs if we had them?
    // For HTML simple list, we just want hierarchy.
}

struct IndexCatalog: Encodable {
    var entries: [String: IndexEntry] = [:] // Primary -> Entry
    
    var sortedEntries: [(primary: String, secondary: [(name: String, tertiary: [String])])] {
        return entries.keys.sorted().map { key in
            let entry = entries[key]!
            let sortedSecondary = entry.secondary.keys.sorted().map { secKey in
                return (name: secKey, tertiary: entry.secondary[secKey]!.sorted())
            }
            return (primary: key, secondary: sortedSecondary)
        }
    }
}

class IndexResolver {
    private var catalog = IndexCatalog()
    
    func resolve(_ document: AdocDocument) -> IndexCatalog {
        // Traverse metadata first? 
        // Traverse blocks
        for block in document.blocks {
            visit(block)
        }
        return catalog
    }
    
    private func visit(_ block: AdocBlock) {
        switch block {
        case .section(let s):
            // Check title
            visit(inlines: s.title.inlines)
            s.blocks.forEach { visit($0) }
            
        case .paragraph(let p):
            visit(inlines: p.text.inlines)
            
        case .list(let l):
            l.items.forEach { item in
                visit(inlines: item.principal.inlines)
                item.blocks.forEach { visit($0) }
            }
            
        case .dlist(let d):
            d.items.forEach { item in
                visit(inlines: item.term.inlines)
                if let p = item.principal {
                     visit(inlines: p.inlines)
                }
                item.blocks.forEach { visit($0) }
            }
            
        case .table(_):
            // TODO: Table cells
            break
            
        case .listing, .literalBlock:
             break
            
        case .quote(let q):
            visit(inlines: q.title?.inlines ?? [])
            q.blocks.forEach { visit($0) }
            
        case .example(let e):
            visit(inlines: e.title?.inlines ?? [])
            e.blocks.forEach { visit($0) }
            
        case .sidebar(let s):
            visit(inlines: s.title?.inlines ?? [])
            s.blocks.forEach { visit($0) }
            
        case .open(let o):
             o.blocks.forEach { visit($0) }
        
        case .admonition(let a):
             a.blocks.forEach { visit($0) }
             
        case .verse(let v):
             if let t = v.text { visit(inlines: t.inlines) }
             
        case .blockMacro:
            break
            
        case .math, .discreteHeading:
             break
        }
    }
    
    private func visit(inlines: [AdocInline]) {
        for inline in inlines {
            visit(inline)
        }
    }
    
    private func visit(_ inline: AdocInline) {
        switch inline {
        case .text:
            break
            
        case .strong(let i, _), .emphasis(let i, _), .mono(let i, _), .superscript(let i, _), .subscript(let i, _), .mark(let i, _):
            visit(inlines: i)
            
        case .link(_, let t, _), .xref(_, let t, _):
            visit(inlines: t)
        
        case .footnote(let c, _, _, _):
            visit(inlines: c)
            
        case .indexTerm(let terms, _, _):
            add(terms)
            
        case .inlineMacro, .passthrough, .math:
            break
        }
    }
    
    private func add(_ terms: [String]) {
        guard let p = terms.first else { return }
        let primary = p.trimmingCharacters(in: .whitespaces)
        if primary.isEmpty { return }
        
        var entry = catalog.entries[primary] ?? IndexEntry(primary: primary)
        
        if terms.count > 1 {
            let secondary = terms[1].trimmingCharacters(in: .whitespaces)
            if !secondary.isEmpty {
                var tertiaryList = entry.secondary[secondary] ?? []
                if terms.count > 2 {
                    let tertiary = terms[2].trimmingCharacters(in: .whitespaces)
                    if !tertiary.isEmpty && !tertiaryList.contains(tertiary) {
                        tertiaryList.append(tertiary)
                    }
                }
                entry.secondary[secondary] = tertiaryList
            }
        }
        
        catalog.entries[primary] = entry
    }
}
