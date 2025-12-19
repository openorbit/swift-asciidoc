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
        guard let antora = target.antora else { return nil }
        
        // We only resolve if we can find the target file in our component map.
        // And we map it to a relative URL for the HTML output?
        // Or absolute?
        // Usually, checking if it exists is the validation.
        // But what should the output string be?
        
        // If we are generating a static site, we need to know where the output will be.
        // But XrefResolver is asking for the HREF string.
        // If we assume a standard output structure:
        // component/module/family/resource.html
        
        let module = antora.module ?? "ROOT"
        let family = antora.family ?? "pages"
        let resource = antora.resource
        
        // Check existence
        guard let _ = component.index.modules[module]?[family]?[resource] else {
            return nil
        }
        
        // Construct Link
        // For now, assuming distinct output folders per module
        // We really need the context of the *source* file to generate a relative link.
        // But XrefResolver protocol currently does not provide the 'from' context (source file path).
        // I missed adding `context` to `XrefResolver.resolve` in the plan/protocol definition!
        
        // I need to update XrefResolver protocol to include context (e.g. current file URL).
        // But for now, let's return a root-relative path or similar.
        
        var href = "/\(module)/\(resource)"
        if let fragment = antora.fragment {
            href += "#\(fragment)"
        }
        
        // Note: Real Antora rewrites extensions (adoc -> html).
        if href.hasSuffix(".adoc") {
            href = href.replacingOccurrences(of: ".adoc", with: ".html")
        }
        
        return href
    }
}
