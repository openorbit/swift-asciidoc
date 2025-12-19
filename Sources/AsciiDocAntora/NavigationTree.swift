//
// Copyright (c) 2025 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

import Foundation
import AsciiDocCore

public struct NavigationItem: Sendable {
    public var label: String
    public var href: String? // Target resolved
    public var children: [NavigationItem] = []
    
    public var dictionary: [String: Any] {
        var dict: [String: Any] = ["label": label]
        if let href { dict["href"] = href }
        if !children.isEmpty {
            dict["children"] = children.map { $0.dictionary }
        }
        return dict
    }
}

public struct NavigationTree: Sendable {
    public var roots: [NavigationItem] = []
    
    public var dictionary: [String: Any] {
        ["items": roots.map { $0.dictionary }]
    }
    
    // Simplistic parser: reads nested bullet list from a nav.adoc file.
    public static func parse(file: URL, resolver: LocalAntoraXrefResolver) -> NavigationTree {
        guard let content = try? String(contentsOf: file, encoding: .utf8) else {
            return NavigationTree()
        }
        
        // Use AsciiDocCore to parse the list?
        // Preprocessor -> Parser (only for list?)
        // Or regex parsing for speed/simplicity as nav files are usually simple lists.
        
        var tree = NavigationTree()
        var stack: [(level: Int, item: NavigationItem)] = []
        
        let lines = content.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("*") else { continue }
            
            // Count level
            var level = 0
            for ch in trimmed {
                if ch == "*" { level += 1 } else { break }
            }
            
            let text = trimmed.dropFirst(level).trimmingCharacters(in: .whitespaces)
            // Parse xref if present: xref:target[Label] or link:target[Label] or just Label
            
            let (label, href) = parseNavLine(text, resolver: resolver)
            
            let item = NavigationItem(label: label, href: href, children: [])
            
            if level == 1 {
                tree.roots.append(item)
                stack = [(1, item)]
            } else {
                // Find parent
                while let last = stack.last, last.level >= level {
                    stack.removeLast()
                }
                if var parent = stack.last {
                    // Append to parent.children. 
                    // This logic is tricky with value types (structs). 
                    // To do this efficiently with structs, we might need a recursive builder or references.
                    // Let's defer full implementation or use a class for the builder.
                }
            }
        }
        
        // Re-implement with recursive approach or class node
        return parseWithClass(lines: lines, resolver: resolver)
    }
    
    private static func parseNavLine(_ text: String, resolver: LocalAntoraXrefResolver) -> (String, String?) {
        // Simple regex-like check
        // xref:module:page.adoc[Label]
        if text.hasPrefix("xref:") {
            guard let close = text.lastIndex(of: "]"),
                  let open = text.firstIndex(of: "[") else {
                return (text, nil)
            }
            let target = String(text[text.index(text.startIndex, offsetBy: 5)..<open])
            let label = String(text[text.index(after: open)..<close])
            
            let adocTarget = AdocXrefTarget(raw: target)
            let href = resolver.resolve(target: adocTarget)
            return (label, href)
        }
        return (text, nil)
    }
    
    private static func parseWithClass(lines: [String], resolver: LocalAntoraXrefResolver) -> NavigationTree {
        class Node {
            var item: NavigationItem
            init(_ item: NavigationItem) { self.item = item }
        }
        
        var roots: [Node] = []
        var stack: [(level: Int, node: Node)] = []
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("*") else { continue }
            var level = 0
            for ch in trimmed {
                if ch == "*" { level += 1 } else { break }
            }
            let text = trimmed.dropFirst(level).trimmingCharacters(in: .whitespaces)
            let (label, href) = parseNavLine(text, resolver: resolver)
            
            let newline = Node(NavigationItem(label: label, href: href))
            
            if level == 1 {
                roots.append(newline)
                stack = [(1, newline)]
            } else {
                 while let last = stack.last, last.level >= level {
                    stack.removeLast()
                }
                if let last = stack.last {
                    last.node.item.children.append(newline.item) // Wait, value type append?
                    // The Node wrapper holds 'item' struct. 
                    // If I append 'newline.item' to 'last.node.item.children', I am copying it. 
                    // But I need to reference 'newline' for subsequent children.
                    // So this doesn't work well if 'NavigationItem' is struct and 'children' is [NavigationItem].
                    // I need to build the tree of Nodes first, then convert.
                    // Or change NavigationItem to be a class or have reference semanitcs?
                    // Let's make NavigationItem a struct but build it recursively.
                    
                    // Actually, easiest is:
                    // Just accept that we add it to the parent node. But we also need to push THIS node to stack.
                    // But if I add it to parent.children, it's a value copy.
                    // The stack needs to hold the Reference to the array inside the parent? No.
                    
                    // Correct approach: Use a Node class for the entire tree building, then map to struct.
                }
                stack.append((level, newline))
            }
        }
        
        // Build logic is flawed above because of `last.node.item.children` mutation not reflecting in previously stored references if I was copying.
        // But `Node` is a class. `last.node` is a reference. 
        // `last.node.item` is a struct property.
        // `last.node.item.children.append(...)` modifies the struct inside the class. 
        // BUT `stack` holds references to Nodes.
        
        // This won't work easily to populate the children of the *children*.
        // Because `parent.node.item.children.append(child.item)` copies `child.item`.
        // Later when we add children to `child`, we modify `child.item` (via the `child` Node),
        // BUT `parent` already has a COPY of the old `child.item`.
        
        // Solution: Use Class for NavigationItem temporarily or permanently.
        // Let's use a helper Class builder.
        
        return NavigationTree(roots: buildTree(lines: lines, resolver: resolver))
    }
    
    private static func buildTree(lines: [String], resolver: LocalAntoraXrefResolver) -> [NavigationItem] {
        class TreeNode {
            var label: String
            var href: String?
            var children: [TreeNode] = []
            init(label: String, href: String?) { self.label = label; self.href = href }
            func toStruct() -> NavigationItem {
                NavigationItem(label: label, href: href, children: children.map { $0.toStruct() })
            }
        }
        
        var roots: [TreeNode] = []
        var stack: [(level: Int, node: TreeNode)] = []
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("*") else { continue }
            var level = 0
            for ch in trimmed {
                if ch == "*" { level += 1 } else { break }
            }
            let text = trimmed.dropFirst(level).trimmingCharacters(in: .whitespaces)
            let (label, href) = parseNavLine(text, resolver: resolver)
            let node = TreeNode(label: label, href: href)
            
            if level == 1 {
                roots.append(node)
                stack = [(1, node)]
            } else {
                 while let last = stack.last, last.level >= level {
                    stack.removeLast()
                }
                if let last = stack.last {
                    last.node.children.append(node)
                }
                stack.append((level, node))
            }
        }
        return roots.map { $0.toStruct() }
    }
}
