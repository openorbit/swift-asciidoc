//
// Copyright (c) 2025 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//
import AsciiDocCore

public enum Backend {
    case html5
    case docbook5
    case latex
}

public enum AdocInlineBackend {
    case html5
    case docbook5
    case latex
}

public protocol AdocInlineRenderer {
    func render(_ inlines: [AdocInline]) -> String
}

public func renderInlines(_ inlines: [AdocInline], backend: AdocInlineBackend) -> String {
    switch backend {
    case .html5:    return HtmlInlineRenderer().render(inlines)
    case .docbook5: return DocBookInlineRenderer().render(inlines)
    case .latex:    return LatexInlineRenderer().render(inlines)
    }
}
