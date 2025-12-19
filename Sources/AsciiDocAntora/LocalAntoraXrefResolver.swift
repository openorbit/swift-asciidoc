//
// Copyright (c) 2025 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

import Foundation
import AsciiDocCore
import AsciiDocRender

public final class LocalAntoraXrefResolver: XrefResolver {
    public let component: AntoraComponent
    
    public init(component: AntoraComponent) {
        self.component = component
    }
    
    public func resolve(target: AdocXrefTarget, source: URL?) -> String? {
        guard let antora = target.antora else { return nil }
        
        // 1. Resolve Target Info
        let targetModule = antora.module ?? "ROOT"
        let targetFamily = antora.family ?? "pages"
        let targetResource = antora.resource
        
        // Check existence
        guard let _ = component.index.modules[targetModule]?[targetFamily]?[targetResource] else {
            return nil
        }
        
        // 2. Resolve Source Info
        var sourceModule: String? = nil
        
        if let sourceURL = source {
            let path = sourceURL.standardizedFileURL.path
            if let range = path.range(of: "/modules/") {
                let substring = path[range.upperBound...]
                let components = substring.split(separator: "/")
                if let mod = components.first {
                    sourceModule = String(mod)
                }
            }
        }
        
        // 3. Construct Relative Path
        // Assumption: Output structure is outputDir/moduleName/pageName.html (flattened pages)
        
        var href = ""
        let targetFilename = targetResource.replacingOccurrences(of: ".adoc", with: ".html")

        if let srcMod = sourceModule {
            if srcMod == targetModule {
                // Same module: sibling file
                href = targetFilename
            } else {
                // Different module: parent -> targetModule -> file
                href = "../\(targetModule)/\(targetFilename)"
            }
        } else {
            // Source unknown (or not in a module?), default to absolute-like or ROOT reference?
            // Fallback to "absolute" path from root of site output
            href = "/\(targetModule)/\(targetFilename)"
        }
        
        if let fragment = antora.fragment {
            href += "#\(fragment)"
        }
        
        return href
    }
}
