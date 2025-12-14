//
// Copyright (c) 2025 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

import Foundation
import AsciiDocCore

indirect enum MathNode {
    case row([MathNode])
    case identifier(String)
    case number(String)
    case operatorToken(String)
    case text(String)
    case fraction(MathNode, MathNode)
    case sqrt(MathNode)
    case scripts(base: MathNode, sub: MathNode?, sup: MathNode?)
}

struct MathMLRenderer {
    static func render(kind: AdocMathKind, body: String, display: Bool) -> String {
        let ast: MathNode
        switch kind {
        case .latex:
            var parser = LatexMathParser(input: body)
            ast = parser.parse()
        case .asciimath:
            let translated = AsciiMathTranslator.convert(body)
            var parser = LatexMathParser(input: translated)
            ast = parser.parse()
        }

        let inner = render(node: ast)
        let displayAttr = display ? " display=\"block\"" : ""
        return "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"\(displayAttr)>\(inner)</math>"
    }

    private static func render(node: MathNode) -> String {
        switch node {
        case .row(let nodes):
            guard !nodes.isEmpty else { return "<mrow/>" }
            if nodes.count == 1 {
                return render(node: nodes[0])
            }
            let inner = nodes.map { render(node: $0) }.joined()
            return "<mrow>\(inner)</mrow>"

        case .identifier(let value):
            return "<mi>\(escape(value))</mi>"

        case .number(let value):
            return "<mn>\(escape(value))</mn>"

        case .operatorToken(let value):
            return "<mo>\(escape(value))</mo>"

        case .text(let value):
            return "<mtext>\(escape(value))</mtext>"

        case .fraction(let numerator, let denominator):
            return "<mfrac>\(render(node: numerator))\(render(node: denominator))</mfrac>"

        case .sqrt(let inner):
            return "<msqrt>\(render(node: inner))</msqrt>"

        case .scripts(let base, let sub, let sup):
            switch (sub, sup) {
            case (let s?, let p?):
                return "<msubsup>\(render(node: base))\(render(node: s))\(render(node: p))</msubsup>"
            case (let s?, nil):
                return "<msub>\(render(node: base))\(render(node: s))</msub>"
            case (nil, let p?):
                return "<msup>\(render(node: base))\(render(node: p))</msup>"
            default:
                return render(node: base)
            }
        }
    }

    private static func escape(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for ch in text {
            switch ch {
            case "&": out.append("&amp;")
            case "<": out.append("&lt;")
            case ">": out.append("&gt;")
            case "\"": out.append("&quot;")
            case "'": out.append("&apos;")
            default: out.append(ch)
            }
        }
        return out
    }
}

private struct LatexMathParser {
    private let input: String
    private var index: String.Index

    init(input: String) {
        self.input = input
        self.index = input.startIndex
    }

    mutating func parse() -> MathNode {
        let nodes = parseRow(until: nil)
        switch nodes.count {
        case 0:
            return .text("")
        case 1:
            return nodes[0]
        default:
            return .row(nodes)
        }
    }

    private mutating func parseRow(until terminator: Character?) -> [MathNode] {
        var nodes: [MathNode] = []
        while true {
            skipSpaces()
            if isAtEnd() { break }
            if let term = terminator, peek() == term {
                advance()
                break
            }

            if let node = parseScriptableAtom() {
                nodes.append(node)
            } else if let ch = advance() {
                nodes.append(.text(String(ch)))
            } else {
                break
            }
        }
        return nodes
    }

    private mutating func parseScriptableAtom() -> MathNode? {
        guard let base = parseAtom() else { return nil }
        var pendingSup: MathNode?
        var pendingSub: MathNode?

        while true {
            skipSpaces()
            guard let ch = peek(), ch == "^" || ch == "_" else { break }
            advance()
            skipSpaces()
            if let script = parseGroupOrAtom() {
                if ch == "^" {
                    pendingSup = script
                } else {
                    pendingSub = script
                }
            }
        }

        if pendingSup != nil || pendingSub != nil {
            return .scripts(base: base, sub: pendingSub, sup: pendingSup)
        }
        return base
    }

    private mutating func parseGroupOrAtom() -> MathNode? {
        if match("{") {
            let nodes = parseRow(until: "}")
            return nodes.count == 1 ? nodes.first : .row(nodes)
        }
        return parseAtom()
    }

    private mutating func parseAtom() -> MathNode? {
        skipSpaces()
        guard let ch = peek() else { return nil }

        if ch == "{" {
            advance()
            let nodes = parseRow(until: "}")
            return nodes.count == 1 ? nodes.first : .row(nodes)
        }

        if ch == "(" {
            advance()
            let nodes = parseRow(until: ")")
            var wrapped = nodes
            wrapped.insert(.operatorToken("("), at: 0)
            wrapped.append(.operatorToken(")"))
            return .row(wrapped)
        }

        if ch == "[" {
            advance()
            let nodes = parseRow(until: "]")
            var wrapped = nodes
            wrapped.insert(.operatorToken("["), at: 0)
            wrapped.append(.operatorToken("]"))
            return .row(wrapped)
        }

        if ch == "\\" {
            return parseCommand()
        }

        if ch.isNumber {
            return parseNumber()
        }

        if ch.isLetter {
            return parseIdentifier()
        }

        if operatorCharacters.contains(ch) {
            advance()
            return .operatorToken(String(ch))
        }

        advance()
        return .text(String(ch))
    }

    private mutating func parseIdentifier() -> MathNode? {
        let start = index
        while let ch = peek(), ch.isLetter {
            advance()
        }
        guard start != index else { return nil }
        let value = String(input[start..<index])
        return .identifier(value)
    }

    private mutating func parseNumber() -> MathNode? {
        let start = index
        var seenDecimal = false

        while let ch = peek() {
            if ch.isNumber {
                advance()
                continue
            }
            if ch == "." && !seenDecimal {
                seenDecimal = true
                advance()
                continue
            }
            break
        }

        guard start != index else { return nil }
        let value = String(input[start..<index])
        return .number(value)
    }

    private mutating func parseCommand() -> MathNode? {
        guard match("\\") else { return nil }
        guard let next = peek() else { return nil }

        if !next.isLetter {
            advance()
            if next == " " {
                return .text(" ")
            }
            return .operatorToken(String(next))
        }

        let start = index
        while let ch = peek(), ch.isLetter {
            advance()
        }
        let name = String(input[start..<index])

        switch name {
        case "frac":
            guard let numerator = parseGroupOrAtom(),
                  let denominator = parseGroupOrAtom() else {
                return nil
            }
            return .fraction(numerator, denominator)

        case "sqrt":
            guard let value = parseGroupOrAtom() else { return nil }
            return .sqrt(value)

        default:
            if let mapped = latexSymbolMap[name] {
                return .identifier(mapped)
            }
            return .identifier(name)
        }
    }

    private mutating func skipSpaces() {
        while let ch = peek(), ch.isWhitespace {
            advance()
        }
    }

    private func peek() -> Character? {
        guard index < input.endIndex else { return nil }
        return input[index]
    }

    @discardableResult
    private mutating func advance() -> Character? {
        guard index < input.endIndex else { return nil }
        let ch = input[index]
        index = input.index(after: index)
        return ch
    }

    @discardableResult
    private mutating func match(_ ch: Character) -> Bool {
        guard let current = peek(), current == ch else { return false }
        advance()
        return true
    }

    private func isAtEnd() -> Bool { index >= input.endIndex }
}

private let operatorCharacters: Set<Character> = ["+", "-", "=", "*", "/", ",", ";", ":", "|", "<", ">", "!", "?"]

private let latexSymbolMap: [String: String] = [
    "alpha": "α",
    "beta": "β",
    "gamma": "γ",
    "delta": "δ",
    "epsilon": "ϵ",
    "theta": "θ",
    "lambda": "λ",
    "mu": "μ",
    "pi": "π",
    "rho": "ρ",
    "sigma": "σ",
    "phi": "φ",
    "psi": "ψ",
    "omega": "ω",
    "Gamma": "Γ",
    "Delta": "Δ",
    "Theta": "Θ",
    "Lambda": "Λ",
    "Pi": "Π",
    "Sigma": "Σ",
    "Phi": "Φ",
    "Psi": "Ψ",
    "Omega": "Ω"
]

enum AsciiMathTranslator {
    static func convert(_ input: String) -> String {
        var output = ""
        var i = input.startIndex

        while i < input.endIndex {
            if input[i...].hasPrefix("sqrt(") {
                let afterKeyword = input.index(i, offsetBy: 4)
                let contentStart = input.index(after: afterKeyword)
                if let (inner, next) = extractBalanced(in: input, start: contentStart, open: "(", close: ")") {
                    output += "\\sqrt{"
                    output += convert(String(inner))
                    output += "}"
                    i = next
                    continue
                }
            }

            if input[i...].hasPrefix("frac(") {
                let afterKeyword = input.index(i, offsetBy: 4)
                let contentStart = input.index(after: afterKeyword)
                if let (numerator, denominator, next) = extractFracArgs(in: input, start: contentStart) {
                    output += "\\frac{"
                    output += convert(String(numerator))
                    output += "}{"
                    output += convert(String(denominator))
                    output += "}"
                    i = next
                    continue
                }
            }

            output.append(input[i])
            i = input.index(after: i)
        }

        return output
    }

    private static func extractBalanced(in input: String,
                                        start: String.Index,
                                        open: Character,
                                        close: Character) -> (Substring, String.Index)? {
        var depth = 0
        var i = start
        while i < input.endIndex {
            let ch = input[i]
            if ch == open {
                depth += 1
            } else if ch == close {
                if depth == 0 {
                    return (input[start..<i], input.index(after: i))
                }
                depth -= 1
            }
            i = input.index(after: i)
        }
        return nil
    }

    private static func extractFracArgs(in input: String,
                                        start: String.Index) -> (Substring, Substring, String.Index)? {
        var depth = 0
        var i = start
        var split: String.Index?

        while i < input.endIndex {
            let ch = input[i]
            if ch == "(" {
                depth += 1
            } else if ch == ")" {
                if depth == 0 {
                    guard let comma = split else { return nil }
                    let numerator = input[start..<comma]
                    let denominator = input[input.index(after: comma)..<i]
                    return (numerator, denominator, input.index(after: i))
                }
                depth -= 1
            } else if ch == "," && depth == 0 {
                split = i
            }
            i = input.index(after: i)
        }

        return nil
    }
}
