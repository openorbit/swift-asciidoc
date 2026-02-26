//
// Copyright (c) 2025 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

import AsciiDocCore

public struct DocBookInlineRenderer: AdocInlineRenderer {
    public init() {}

    public func render(_ inlines: [AdocInline], context: InlineContext) -> String {
        var out = ""
        for n in inlines {
            render(node: n, into: &out)
        }
        return out
    }

    private func render(node: AdocInline, into out: inout String) {
        switch node {
        case .text(let s, _):
            out += xmlEscape(s)

        case .strong(let xs, _):
            out += "<emphasis role=\"strong\">"
            xs.forEach { render(node: $0, into: &out) }
            out += "</emphasis>"

        case .emphasis(let xs, _):
            out += "<emphasis>"
            xs.forEach { render(node: $0, into: &out) }
            out += "</emphasis>"

        case .mono(let xs, _):
            out += "<literal>"
            xs.forEach { render(node: $0, into: &out) }
            out += "</literal>"

        case .mark(let xs, _):
            out += "<emphasis role=\"mark\">"
            xs.forEach { render(node: $0, into: &out) }
            out += "</emphasis>"

        case .link(let target, let text, _):
            out += "<link xlink:href=\""
            out += xmlEscapeAttr(target)
            out += "\">"
            text.forEach { render(node: $0, into: &out) }
            out += "</link>"

        case .xref(let target, let text, _):
            let linkend = target.raw.trimmingCharacters(in: ["#"])
            out += "<xref linkend=\""
            out += xmlEscapeAttr(linkend)
            out += "\">"
            text.forEach { render(node: $0, into: &out) }
            out += "</xref>"

        case .math(let kind, let body, let display, _):
            let mathML = MathMLRenderer.render(kind: kind, body: body, display: display)
            if display {
                out += "<equation>\(mathML)</equation>"
            } else {
                out += "<inlineequation>\(mathML)</inlineequation>"
            }

        case .passthrough(let raw, _):
            out += raw

        case .superscript(let xs, _):
            out += "<superscript>"
            xs.forEach { render(node: $0, into: &out) }
            out += "</superscript>"

        case .subscript(let xs, _):
            out += "<subscript>"
            xs.forEach { render(node: $0, into: &out) }
            out += "</subscript>"

        case .inlineMacro(let name, let target, let body, _):
            switch name {
            case "image":
                let t = target ?? ""
                let attrs = parseAttributes(from: body)
                let alt = attrs.first ?? ""
                // DocBook uses fileref
                out += "<inlinemediaobject><imageobject><imagedata fileref=\""
                out += xmlEscapeAttr(t)
                out += "\"/></imageobject><textobject><phrase>"
                out += xmlEscape(alt)
                out += "</phrase></textobject></inlinemediaobject>"

            case "icon":
                // Assuming font-based icon
                let t = target ?? ""
                out += "<phrase role=\"icon\">" + xmlEscape(t) + "</phrase>"

            case "kbd":
                // kbd:[Ctrl+C] -> <keycombo action="simul"><keycap>Ctrl</keycap><keycap>C</keycap></keycombo>
                let keys = body.split(separator: "+")
                if keys.count > 1 {
                    out += "<keycombo action=\"simul\">"
                    for key in keys {
                        out += "<keycap>" + xmlEscape(String(key).trimmingCharacters(in: .whitespaces)) + "</keycap>"
                    }
                    out += "</keycombo>"
                } else {
                    out += "<keycap>" + xmlEscape(body) + "</keycap>"
                }

            case "btn":
                out += "<guibutton>" + xmlEscape(body) + "</guibutton>"

            case "menu":
                // menu:View[Zoom > In]
                out += "<menuchoice><guimenu>" + xmlEscape(target ?? "") + "</guimenu>"
                if !body.isEmpty {
                    // Split body by '>' ?
                    let items = body.split(separator: ">")
                    for item in items {
                         // Whitespace trimming?
                         out += "<guimenuitem>" + xmlEscape(String(item).trimmingCharacters(in: .whitespaces)) + "</guimenuitem>"
                    }
                }
                out += "</menuchoice>"

            default:
                out += "<inlinemacro data-name=\""
                out += xmlEscapeAttr(name)
                if let t = target {
                     out += "\" data-target=\""
                     out += xmlEscapeAttr(t)
                }
                out += "\">"
                out += xmlEscape(body)
                out += "</inlinemacro>"
            }

        case .footnote(let content, _, let id, _):
            if content.isEmpty, let i = id {
                out.append("<footnoteref linkend=\"_footnotedef_\(i)\"/>")
            } else {
                let i = id ?? 0
                out.append("<footnote xml:id=\"_footnotedef_\(i)\"><simpara>")
                content.forEach { render(node: $0, into: &out) }
                out.append("</simpara></footnote>")
            }

        case .indexTerm(let terms, let visible, _):
            if visible, let first = terms.first {
                out.append(first)
            }
            out.append("<indexterm>")
            if let p = terms.first { out.append("<primary>\(p)</primary>") }
            if terms.count > 1 { out.append("<secondary>\(terms[1])</secondary>") }
            if terms.count > 2 { out.append("<tertiary>\(terms[2])</tertiary>") }
            out.append("</indexterm>")
        }
    }

    private func parseAttributes(from body: String) -> [String] {
        return body.split(separator: ",").map { 
            String($0).trimmingCharacters(in: .whitespaces) 
        }
    }
}

private func xmlEscape(_ s: String) -> String {
    // same idea as htmlEscape but for XML
    var out = ""
    for ch in s {
        switch ch {
        case "&":  out.append("&amp;")
        case "<":  out.append("&lt;")
        case ">":  out.append("&gt;")
        case "\"": out.append("&quot;")
        case "'":  out.append("&apos;")
        default:   out.append(ch)
        }
    }
    return out
}

private func xmlEscapeAttr(_ s: String) -> String { xmlEscape(s) }
