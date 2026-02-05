//
// Copyright (c) 2025 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

import Foundation
import AsciiDocCore

public final class LocalAntoraIncludeResolver: IncludeResolver {
    public let component: AntoraComponent
    private let fsResolver = FileSystemIncludeResolver(rootDirectory: nil) // Fallback
    
    public init(component: AntoraComponent) {
        self.component = component
    }
    
    public func resolve(target: String, from source: URL?) -> IncludeResult? {
        // Check for antora resource syntax
        // module:family$resource
        // component:module:family$resource (component must match current or we fail/ignore in local mode if we strictly support only one component)
        
        if let (module, family, resource) = parseAntoraResource(target) {
            return resolveResource(module: module, family: family, resource: resource)
        }
        
        // Fallback to relative path resolution, but be aware of standard Antora structure if we want to support relative "up" movement?
        // Standard AsciiDoc relative includes work fine if the files exist on disk relative to each other.
        // Since we are building from disk, the standard FS resolver handles relative paths correctly.
        
        return fsResolver.resolve(target: target, from: source)
    }
    
    private func resolveResource(module: String?, family: String?, resource: String) -> IncludeResult? {
        let modName = module ?? "ROOT" // Default module is ROOT? Or current?
        // Needs context of current file to know "current" module. `source` URL can help?
        // For now assume ROOT or explicit.
        
        // Default family? 'include' usually defaults to 'pages' or 'partials'?
        // "If the family is not specified, it defaults to pages." - Antora docs (actually partials for includes?)
        // Antora docs: "The default family for an include is partials."
        
        let targetFamily = family ?? "partials"
        
        guard let fams = component.index.modules[modName] else { return nil }
        guard let resources = fams[targetFamily] else { return nil }
        
        if let url = resources[resource] {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return IncludeResult(content: text, directory: url.deletingLastPathComponent(), filePath: url.path)
        }
        
        return nil
    }
    
    private func parseAntoraResource(_ raw: String) -> (module: String?, family: String?, resource: String)? {
        guard raw.contains("$") else { return nil }
        // Simplified parser
        let parts = raw.split(separator: "$", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        
        let coordinate = parts[0]
        let resource = String(parts[1])
        
        var module: String?
        var family: String?
        
        // coordinate: [component:[version]@]module[:family]
        // parsing from right to left is safer?
        
        // We only support local component, so ignore component/version if present, or validate it matches?
        // Let's just strip component/version
        
        var remainder = String(coordinate)
        if let at = remainder.lastIndex(of: "@") {
            remainder = String(remainder[remainder.index(after: at)...])
        }
        
        let segments = remainder.split(separator: ":")
        if segments.count == 2 {
            // module:family
            module = String(segments[0])
            family = String(segments[1])
        } else if segments.count == 1 {
            // module? or family?
            // "module:family$resource" -> module: "module", family: "family"
            // "family$resource" -> implied module (current), family? No, coordinate must have module if colon present?
            // If just "example$foo", then module is current, family is example.
            
            // Let's assume input is module:family for now.
             module = String(segments[0])
        }
        
        // TODO: Refine this logic with proper parser or use XrefTarget logic adapted
        
        return (module, family, resource)
    }
}
