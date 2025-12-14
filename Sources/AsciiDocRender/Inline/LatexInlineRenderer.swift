//
// Copyright (c) 2025 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

import AsciiDocCore

public struct LatexInlineRenderer: AdocInlineRenderer {
    public init() {}

    public func render(_ inlines: [AdocInline]) -> String {
        var out = ""
        for inline in inlines {
            render(node: inline, into: &out)
        }
        return out
    }

    private func render(node: AdocInline, into out: inout String) {
        switch node {
        case .text(let s, _):
            out += latexEscape(s)

        case .strong(let xs, _):
            out += "\\textbf{"
            xs.forEach { render(node: $0, into: &out) }
            out += "}"

        case .emphasis(let xs, _):
            out += "\\textit{"
            xs.forEach { render(node: $0, into: &out) }
            out += "}"

        case .mono(let xs, _):
            out += "\\texttt{"
            xs.forEach { render(node: $0, into: &out) }
            out += "}"

        case .mark(let xs, _):
            xs.forEach { render(node: $0, into: &out) }

        case .link(let target, let text, _):
            out += "\\href{\(latexEscape(target))}{"
            text.forEach { render(node: $0, into: &out) }
            out += "}"

        case .xref(let target, let text, _):
            out += "\\ref{\(latexEscape(target.raw))}"
            if !text.isEmpty {
                out += "{"
                text.forEach { render(node: $0, into: &out) }
                out += "}"
            }

        case .superscript(let xs, _):
            out += "^{"
            xs.forEach { render(node: $0, into: &out) }
            out += "}"

        case .subscript(let xs, _):
            out += "_{"
            xs.forEach { render(node: $0, into: &out) }
            out += "}"

        case .math(let kind, let body, let display, _):
            let payload: String
            switch kind {
            case .latex:
                payload = body
            case .asciimath:
                payload = AsciiMathTranslator.convert(body)
            }
            if display {
                out += "\\[\(payload)\\]"
            } else {
                out += "\\(\(payload)\\)"
            }

        case .inlineMacro(let name, let target, let body, _):
            switch name {
            case "image":
                let t = target ?? ""
                out += "\\includegraphics{" + t + "}"

            case "icon":
                let t = target ?? ""
                out += "\\faIcon{" + latexEscape(t) + "}"

            case "kbd":
                out += "\\kbd{" + latexEscape(body) + "}"

            case "btn":
                out += "\\btn{" + latexEscape(body) + "}"

            case "menu":
                var label = target ?? ""
                if !body.isEmpty {
                    label += " > " + body.replacingOccurrences(of: ">", with: "$\\to$") 
                }
                out += "\\menu{" + label + "}" 

            default:
                if let t = target {
                     out += "\\texttt{\(latexEscape("\(name):\(t)[\(body)]"))}"
                } else {
                     out += "\\texttt{\(latexEscape("\(name):[\(body)]"))}"
                }
            }

            case .footnote(let content, _, let id, _):
                if content.isEmpty, let i = id {
                    // Reference
                     out.append("\\textsuperscript{\\ref{_footnotedef_\(i)}}")
                } else {
                    // Definition
                    let i = id ?? 0
                    out.append("\\footnote{\\label{_footnotedef_\(i)}")
                    content.forEach { render(node: $0, into: &out) }
                    out.append("}")
                }
            
            case .indexTerm(let terms, let visible, _):
                if visible, let first = terms.first {
                    out.append(first)
                }
                // LaTeX \index{Primary!Secondary!Tertiary}
                let indexString = terms.joined(separator: "!")
                out.append("\\index{\(indexString)}")

            case .passthrough(let raw, _):
            out += raw
        }
    }

    private func parseAttributes(from body: String) -> [String] {
        return body.split(separator: ",").map { 
            String($0).trimmingCharacters(in: .whitespaces) 
        }
    }
}

private func latexEscape(_ text: String) -> String {
    var out = ""
    out.reserveCapacity(text.count + 8)
    for ch in text {
        switch ch {
        case "\\":
            out.append("\\textbackslash{}")
        case "{":
            out.append("\\{")
        case "}":
            out.append("\\}")
        case "$":
            out.append("\\$")
        case "&":
            out.append("\\&")
        case "#":
            out.append("\\#")
        case "_":
            out.append("\\_")
        case "%":
            out.append("\\%")
        case "~":
            out.append("\\textasciitilde{}")
        case "^":
            out.append("\\textasciicircum{}")
        default:
            out.append(ch)
        }
    }
    return out
}
