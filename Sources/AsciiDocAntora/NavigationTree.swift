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
        [
            "items": roots.map { $0.dictionary },
            "flatItems": flatItems
        ]
    }
    
    public var flatItems: [[String: Any]] {
        var result: [[String: Any]] = []
        func traverse(_ items: [NavigationItem], depth: Int) {
            for item in items {
                var dict = item.dictionary
                dict["depth"] = depth
                result.append(dict)
                traverse(item.children, depth: depth + 1)
            }
        }
        traverse(roots, depth: 0)
        return result
    }
    
    // Simplistic parser: reads nested bullet list from a nav.adoc file.
    public static func parse(file: URL, resolver: LocalAntoraXrefResolver) -> NavigationTree {
        guard let content = try? String(contentsOf: file, encoding: .utf8) else {
            return NavigationTree()
        }
        
        let lines = content.components(separatedBy: .newlines)
        return NavigationTree(roots: buildTree(lines: lines, resolver: resolver, file: file))
    }
    
    private static func parseNavLine(_ text: String, resolver: LocalAntoraXrefResolver, file: URL) -> (String, String?) {
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
            let href = resolver.resolve(target: adocTarget, source: file)
            return (label, href)
        }
        return (text, nil)
    }
    
    private static func buildTree(lines: [String], resolver: LocalAntoraXrefResolver, file: URL) -> [NavigationItem] {
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
            let (label, href) = parseNavLine(text, resolver: resolver, file: file)
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
