//
// Copyright (c) 2025 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

import Foundation
import AsciiDocCore

/// Result of a footnote resolution pass.
public struct FootnoteResolution {
    /// The document with footnote IDs assigned.
    public let document: AdocDocument
    /// The collected definitions, ordered by ID.
    public let definitions: [FootnoteDefinition]
}

/// A footnote definition extracted from the document.
public struct FootnoteDefinition: Sendable, Equatable {
    public let id: Int
    /// The content of the footnote.
    public let content: [AdocInline]
}

public final class FootnoteResolver {
    public init() {}

    public func resolve(_ document: AdocDocument) -> FootnoteResolution {
        var collected: [FootnoteDefinition] = []
        var nextId = 1
        var refs: [String: Int] = [:]
        var idToIndex: [Int: Int] = [:] // Map ID -> Index in collected

        let newBlocks = document.blocks.map { resolveBlock($0, collected: &collected, nextId: &nextId, refs: &refs, idToIndex: &idToIndex) }
        
        let newDoc = AdocDocument(
            attributes: document.attributes,
            header: document.header,
            blocks: newBlocks,
            span: document.span
        )
        
        return FootnoteResolution(document: newDoc, definitions: collected)
    }

    private func resolveBlock(_ block: AdocBlock, collected: inout [FootnoteDefinition], nextId: inout Int, refs: inout [String: Int], idToIndex: inout [Int: Int]) -> AdocBlock {
        switch block {
        case .section(var s):
            s.title = resolveText(s.title, collected: &collected, nextId: &nextId, refs: &refs, idToIndex: &idToIndex)
            s.blocks = s.blocks.map { resolveBlock($0, collected: &collected, nextId: &nextId, refs: &refs, idToIndex: &idToIndex) }
            return .section(s)

        case .paragraph(var p):
            p.text = resolveText(p.text, collected: &collected, nextId: &nextId, refs: &refs, idToIndex: &idToIndex)
            return .paragraph(p)

        case .list(var l):
            l.items = l.items.map { item in
                var newItem = item
                newItem.principal = resolveText(item.principal, collected: &collected, nextId: &nextId, refs: &refs, idToIndex: &idToIndex)
                newItem.blocks = item.blocks.map { resolveBlock($0, collected: &collected, nextId: &nextId, refs: &refs, idToIndex: &idToIndex) }
                return newItem
            }
            return .list(l)

        case .listing(let l):
            var newL = l
            newL.text = resolveText(l.text, collected: &collected, nextId: &nextId, refs: &refs, idToIndex: &idToIndex)
            return .listing(newL)

        case .dlist(var d):
            d.items = d.items.map { item in
                var newItem = item
                newItem.term = resolveText(item.term, collected: &collected, nextId: &nextId, refs: &refs, idToIndex: &idToIndex)
                newItem.principal = item.principal.map { resolveText($0, collected: &collected, nextId: &nextId, refs: &refs, idToIndex: &idToIndex) }
                newItem.blocks = item.blocks.map { resolveBlock($0, collected: &collected, nextId: &nextId, refs: &refs, idToIndex: &idToIndex) }
                return newItem
            }
            return .dlist(d)
        
        // Skipping table body again (same reason)
        case .table(let t):
             return .table(t)

        case .admonition(var a):
            a.blocks = a.blocks.map { resolveBlock($0, collected: &collected, nextId: &nextId, refs: &refs, idToIndex: &idToIndex) }
            return .admonition(a)

        case .example(var e):
            e.blocks = e.blocks.map { resolveBlock($0, collected: &collected, nextId: &nextId, refs: &refs, idToIndex: &idToIndex) }
            return .example(e)

        case .sidebar(var s):
            s.blocks = s.blocks.map { resolveBlock($0, collected: &collected, nextId: &nextId, refs: &refs, idToIndex: &idToIndex) }
            return .sidebar(s)

        case .quote(var q):
            q.blocks = q.blocks.map { resolveBlock($0, collected: &collected, nextId: &nextId, refs: &refs, idToIndex: &idToIndex) }
            if let attr = q.attribution {
                q.attribution = resolveText(attr, collected: &collected, nextId: &nextId, refs: &refs, idToIndex: &idToIndex)
            }
            return .quote(q)
            
        case .open(var o):
            o.blocks = o.blocks.map { resolveBlock($0, collected: &collected, nextId: &nextId, refs: &refs, idToIndex: &idToIndex) }
            return .open(o)

        case .literalBlock, .verse, .math, .blockMacro:
             return block
        case .discreteHeading(var h):
            h.title = resolveText(h.title, collected: &collected, nextId: &nextId, refs: &refs, idToIndex: &idToIndex)
            return .discreteHeading(h)
        }
    }

    private func resolveText(_ text: AdocText, collected: inout [FootnoteDefinition], nextId: inout Int, refs: inout [String: Int], idToIndex: inout [Int: Int]) -> AdocText {
        let newInlines = resolveInlines(text.inlines, collected: &collected, nextId: &nextId, refs: &refs, idToIndex: &idToIndex)
        return AdocText(inlines: newInlines, span: text.span)
    }

    private func resolveInlines(_ inlines: [AdocInline], collected: inout [FootnoteDefinition], nextId: inout Int, refs: inout [String: Int], idToIndex: inout [Int: Int]) -> [AdocInline] {
        return inlines.map { node in
            switch node {
            case .footnote(let content, let ref, _, let span):
                var idToUse: Int
                
                // Recurse content
                // Note: content for definitions should be resolved (footnotes in footnotes)
                // But check potential infinite recursion/cycles? (footnote:x[...footnote:x[...]])
                // Assuming well-formed.
                let resolvedContent = resolveInlines(content, collected: &collected, nextId: &nextId, refs: &refs, idToIndex: &idToIndex)

                if let r = ref {
                    if let existing = refs[r] {
                        idToUse = existing
                        // Existing ref logic
                        if !resolvedContent.isEmpty {
                            // Check if previously collected definition was empty
                            if let idx = idToIndex[idToUse], collected[idx].content.isEmpty {
                                // Update previous definition (was likely a forward ref)
                                collected[idx] = FootnoteDefinition(id: idToUse, content: resolvedContent)
                                // Treating this node as the defining instance
                                return .footnote(content: resolvedContent, ref: ref, id: idToUse, span: span)
                            } else {
                                // Previous definition exists. Treat this as reference.
                                // Return empty content to signal "reference" to renderers
                                return .footnote(content: [], ref: ref, id: idToUse, span: span)
                            }
                        } else {
                            // Reference (empty content). 
                            // Return empty content.
                            return .footnote(content: [], ref: ref, id: idToUse, span: span)
                        }
                    } else {
                        // New ref
                        idToUse = nextId
                        nextId += 1
                        refs[r] = idToUse
                        
                        let def = FootnoteDefinition(id: idToUse, content: resolvedContent)
                        let idx = collected.count
                        collected.append(def)
                        idToIndex[idToUse] = idx
                        
                        return .footnote(content: resolvedContent, ref: ref, id: idToUse, span: span)
                    }
                } else {
                    // Anonymous
                    idToUse = nextId
                    nextId += 1
                    
                    let def = FootnoteDefinition(id: idToUse, content: resolvedContent)
                    let idx = collected.count
                    collected.append(def)
                    idToIndex[idToUse] = idx
                    
                    return .footnote(content: resolvedContent, ref: ref, id: idToUse, span: span)
                }

            case .indexTerm(let terms, let visible, let span):
                // Index terms don't need resolution in this pass (unless we wanted to collect them here?)
                // For now, simple pass-through.
                return .indexTerm(terms: terms, visible: visible, span: span)
            
            case .strong(let xs, let span):
                return .strong(resolveInlines(xs, collected: &collected, nextId: &nextId, refs: &refs, idToIndex: &idToIndex), span: span)
            case .emphasis(let xs, let span):
                return .emphasis(resolveInlines(xs, collected: &collected, nextId: &nextId, refs: &refs, idToIndex: &idToIndex), span: span)
            case .mono(let xs, let span):
                return .mono(resolveInlines(xs, collected: &collected, nextId: &nextId, refs: &refs, idToIndex: &idToIndex), span: span)
            case .mark(let xs, let span):
                return .mark(resolveInlines(xs, collected: &collected, nextId: &nextId, refs: &refs, idToIndex: &idToIndex), span: span)
            case .superscript(let xs, let span):
                return .superscript(resolveInlines(xs, collected: &collected, nextId: &nextId, refs: &refs, idToIndex: &idToIndex), span: span)
            case .`subscript`(let xs, let span):
                return .`subscript`(resolveInlines(xs, collected: &collected, nextId: &nextId, refs: &refs, idToIndex: &idToIndex), span: span)
                
            case .link(let target, let text, let span):
                return .link(target: target, text: resolveInlines(text, collected: &collected, nextId: &nextId, refs: &refs, idToIndex: &idToIndex), span: span)
            case .xref(let target, let text, let span):
                return .xref(target: target, text: resolveInlines(text, collected: &collected, nextId: &nextId, refs: &refs, idToIndex: &idToIndex), span: span)

            case .text, .passthrough, .math, .inlineMacro:
                return node
            }
        }
    }
}
