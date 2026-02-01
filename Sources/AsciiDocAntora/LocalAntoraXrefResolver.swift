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
    
    public func resolve(target: AdocXrefTarget) -> String? {
        resolve(target: target, source: nil)
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
        // Output structure: outputDir/<module>/page.html, except ROOT lives at outputDir/page.html.
        
        var href = ""
        let targetFilename = targetResource.replacingOccurrences(of: ".adoc", with: ".html")

        let isTargetRoot = targetModule == "ROOT"
        if let srcMod = sourceModule {
            let isSourceRoot = srcMod == "ROOT"
            if srcMod == targetModule {
                // Same module: sibling file
                href = targetFilename
            } else if isSourceRoot {
                // From ROOT (site root) to another module
                href = "\(targetModule)/\(targetFilename)"
            } else if isTargetRoot {
                // From module to ROOT (site root)
                href = "../\(targetFilename)"
            } else {
                // Between non-root modules
                href = "../\(targetModule)/\(targetFilename)"
            }
        } else {
            // Source unknown (or not in a module?), default to absolute-like from site root
            href = isTargetRoot ? "/\(targetFilename)" : "/\(targetModule)/\(targetFilename)"
        }
        
        if let fragment = antora.fragment {
            href += "#\(fragment)"
        }
        
        return href
    }
}
