//
// Copyright (c) 2025 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

import AsciiDocCore
public struct HtmlInlineRenderer: AdocInlineRenderer {
    public var xrefResolver: XrefResolver?

    public init(xrefResolver: XrefResolver? = nil) {
        self.xrefResolver = xrefResolver
    }

    public func render(_ inlines: [AdocInline]) -> String {
        var out = ""
        for n in inlines {
            render(node: n, into: &out)
        }
        return out
    }

    private func render(node: AdocInline, into out: inout String) {
        switch node {
        case .text(let s, _):
            out += htmlEscape(s)

        case .strong(let xs, _):
            out += "<strong>"
            xs.forEach { render(node: $0, into: &out) }
            out += "</strong>"

        case .emphasis(let xs, _):
            out += "<em>"
            xs.forEach { render(node: $0, into: &out) }
            out += "</em>"

        case .mono(let xs, _):
            out += "<code>"
            xs.forEach { render(node: $0, into: &out) }
            out += "</code>"

        case .mark(let xs, _):
            out += "<mark>"
            xs.forEach { render(node: $0, into: &out) }
            out += "</mark>"

        case .link(let target, let text, _):
            out += "<a href=\""
            out += htmlEscapeAttr(target)
            out += "\">"
            text.forEach { render(node: $0, into: &out) }
            out += "</a>"

        case .xref(let target, let text, _):
            var href = target.raw
            if let custom = xrefResolver?.resolve(target: target) {
                href = custom
            } else {
                 if !href.hasPrefix("#") && !href.contains(".") {
                     href = "#" + href
                 }
            }
            
            out += "<a href=\""
            out += htmlEscapeAttr(href)
            out += "\" class=\"xref\">"
            text.forEach { render(node: $0, into: &out) }
            out += "</a>"

        case .superscript(let xs, _):
            out += "<sup>"
            xs.forEach { render(node: $0, into: &out) }
            out += "</sup>"

        case .subscript(let xs, _):
            out += "<sub>"
            xs.forEach { render(node: $0, into: &out) }
            out += "</sub>"

        case .math(let kind, let body, let display, _):
            let mathML = MathMLRenderer.render(kind: kind, body: body, display: display)
            if display {
                out += "<div class=\"math\">"
                out += mathML
                out += "</div>"
            } else {
                out += "<span class=\"math\">"
                out += mathML
                out += "</span>"
            }

        case .inlineMacro(let name, let target, let body, _):
            switch name {
            case "image":
                let t = target ?? ""
                // Simple parsing for alt,width,height
                let attrs = parseAttributes(from: body)
                let alt = attrs.first ?? ""
                let width = attrs.count > 1 ? attrs[1] : nil
                let height = attrs.count > 2 ? attrs[2] : nil
                
                out += "<img src=\"" + htmlEscapeAttr(t) + "\" alt=\"" + htmlEscapeAttr(alt) + "\""
                if let w = width, !w.isEmpty { out += " width=\"" + htmlEscapeAttr(w) + "\"" }
                if let h = height, !h.isEmpty { out += " height=\"" + htmlEscapeAttr(h) + "\"" }
                out += ">"

            case "icon":
                let t = target ?? ""
                // Icon body often contains size=2x role=foo etc, or just positional
                // Assuming FontAwesome default mapping
                out += "<i class=\"fa fa-" + htmlEscapeAttr(t) + "\"></i>"

            case "kbd":
                // kbd:[Ctrl+C] -> <kbd>Ctrl</kbd>+<kbd>C</kbd>
                // If keys has commas, it's distinct keystrokes? Standard is + for chords.
                let keys = body.split(separator: "+")
                for (idx, key) in keys.enumerated() {
                    if idx > 0 { out += "+" }
                    out += "<kbd>" + htmlEscape(String(key).trimmingCharacters(in: .whitespaces)) + "</kbd>"
                }

            case "btn":
                out += "<b class=\"button\">" + htmlEscape(body) + "</b>"

            case "menu":
                // menu:View[Zoom > In] -> <span class="menu">View</span><span class="menuitem">Zoom</span>...
                out += "<span class=\"menu\">" + htmlEscape(target ?? "") + "</span>"
                if !body.isEmpty {
                    out += "<span class=\"menuitem\">" + htmlEscape(body) + "</span>"
                }

            default:
                // Fallback to generic macro
                out += "<span class=\"macro\" data-name=\""
                out += htmlEscapeAttr(name)
                if let t = target {
                     out += "\" data-target=\""
                     out += htmlEscapeAttr(t)
                }
                out += "\">"
                out += htmlEscape(body)
                out += "</span>"
            }

            case .footnote(let content, _, let id, _):
                // If ID is set, render the reference.
                if let i = id {
                    out.append("<sup class=\"footnote\">[<a id=\"_footnoteref_\(i)\" class=\"footnote\" href=\"#_footnotedef_\(i)\" title=\"View footnote.\">\(i)</a>]</sup>")
                } else {
                    // Fallback if no ID (should rely on resolver)
                    content.forEach { render(node: $0, into: &out) }
                }

            case .indexTerm(let terms, let visible, _):
                // HTML: If visible, output the text. If invisible, output nothing.
                // AsciiDoc HTML doesn't typically output explicit index markers unless using generic HTML renderer.
                if visible, let first = terms.first {
                    out.append(first)
                }

            case .passthrough(let raw, _):
            // trust caller: raw HTML
            out += raw
        }
    }
    private func parseAttributes(from body: String) -> [String] {
        return body.split(separator: ",").map { 
            String($0).trimmingCharacters(in: .whitespaces) 
        }
    }
}

private func htmlEscape(_ s: String) -> String {
    var out = ""
    out.reserveCapacity(s.count + 8)
    for ch in s {
        switch ch {
        case "&":  out.append("&amp;")
        case "<":  out.append("&lt;")
        case ">":  out.append("&gt;")
        case "\"": out.append("&quot;")
        case "'":  out.append("&#39;")
        default:   out.append(ch)
        }
    }
    return out
}

private func htmlEscapeAttr(_ s: String) -> String { htmlEscape(s) }
