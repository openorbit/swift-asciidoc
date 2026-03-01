//
// Copyright (c) 2026 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

import Foundation

public enum LayoutExpr: Sendable, Equatable {
    case node(LayoutNode)
    case value(LayoutValue)
}

public struct LayoutProgram: Sendable, Equatable {
    public var expressions: [LayoutExpr]

    public init(expressions: [LayoutExpr]) {
        self.expressions = expressions
    }
}

public struct LayoutNode: Sendable, Equatable {
    public var name: String
    public var args: [LayoutArg]
    public var children: [LayoutExpr]
    public var span: AdocRange?

    public init(name: String, args: [LayoutArg], children: [LayoutExpr], span: AdocRange?) {
        self.name = name
        self.args = args
        self.children = children
        self.span = span
    }
}

public struct LayoutArg: Sendable, Equatable {
    public var name: String?
    public var value: LayoutExpr
    public var span: AdocRange?

    public init(name: String?, value: LayoutExpr, span: AdocRange?) {
        self.name = name
        self.value = value
        self.span = span
    }
}

public enum LayoutValue: Sendable, Equatable {
    case string(String)
    case number(Double)
    case boolean(Bool)
    case null
    case array([LayoutValue])
    case dict([String: LayoutValue])
    case ref(LayoutRef)
}

public struct LayoutRef: Sendable, Equatable {
    public var parts: [String]
    public var index: LayoutIndex?

    public init(parts: [String], index: LayoutIndex?) {
        self.parts = parts
        self.index = index
    }
}

public enum LayoutIndex: Sendable, Equatable {
    case number(Double)
    case string(String)
    case identifier(String)
}

public struct LayoutDSLParser: Sendable {
    public init() {}

    public func parse(text: String, span: AdocRange? = nil) -> (LayoutProgram?, [AdocWarning]) {
        let tokenizer = LayoutDSLTokenizer(text: text)
        var parser = LayoutDSLParserState(tokenizer: tokenizer, span: span)
        let program = parser.parseProgram()
        return (program, parser.warnings)
    }
}

private enum LayoutDSLTokenKind: Equatable {
    case identifier(String)
    case string(String)
    case number(Double)
    case boolean(Bool)
    case null
    case lparen
    case rparen
    case lbracket
    case rbracket
    case lbrace
    case rbrace
    case colon
    case comma
    case semicolon
    case dot
    case eof
}

private struct LayoutDSLToken: Equatable {
    let kind: LayoutDSLTokenKind
    let span: AdocRange?
}

private struct LayoutDSLTokenizer {
    private let text: String
    private var index: String.Index
    private var line: Int
    private var column: Int

    init(text: String) {
        self.text = text
        self.index = text.startIndex
        self.line = 1
        self.column = 1
    }

    mutating func nextToken() -> LayoutDSLToken {
        skipWhitespaceAndComments()
        guard index < text.endIndex else {
            return LayoutDSLToken(kind: .eof, span: nil)
        }

        let start = position()
        let ch = text[index]

        switch ch {
        case "(":
            advance()
            return token(.lparen, start: start)
        case ")":
            advance()
            return token(.rparen, start: start)
        case "[":
            advance()
            return token(.lbracket, start: start)
        case "]":
            advance()
            return token(.rbracket, start: start)
        case "{":
            advance()
            return token(.lbrace, start: start)
        case "}":
            advance()
            return token(.rbrace, start: start)
        case ":":
            advance()
            return token(.colon, start: start)
        case ",":
            advance()
            return token(.comma, start: start)
        case ";":
            advance()
            return token(.semicolon, start: start)
        case ".":
            advance()
            return token(.dot, start: start)
        case "\"", "'":
            return readString(quote: ch, start: start)
        case "-":
            return readNumber(start: start)
        default:
            if ch.isNumber {
                return readNumber(start: start)
            }
            if isIdentifierStart(ch) {
                return readIdentifier(start: start)
            }
        }

        advance()
        return token(.eof, start: start)
    }

    private mutating func skipWhitespaceAndComments() {
        while index < text.endIndex {
            let ch = text[index]
            if ch == "/" {
                let next = text.index(after: index)
                if next < text.endIndex, text[next] == "/" {
                    advance()
                    advance()
                    while index < text.endIndex, text[index] != "\n" {
                        advance()
                    }
                    continue
                }
            }
            if ch == " " || ch == "\t" || ch == "\r" || ch == "\n" {
                advance()
                continue
            }
            break
        }
    }

    private mutating func readIdentifier(start: AdocPos) -> LayoutDSLToken {
        var value = String()
        while index < text.endIndex {
            let ch = text[index]
            if isIdentifierPart(ch) {
                value.append(ch)
                advance()
            } else {
                break
            }
        }

        switch value {
        case "true":
            return token(.boolean(true), start: start)
        case "false":
            return token(.boolean(false), start: start)
        case "null":
            return token(.null, start: start)
        default:
            return token(.identifier(value), start: start)
        }
    }

    private mutating func readNumber(start: AdocPos) -> LayoutDSLToken {
        var value = String()
        if index < text.endIndex, text[index] == "-" {
            value.append("-")
            advance()
        }
        while index < text.endIndex, text[index].isNumber {
            value.append(text[index])
            advance()
        }
        if index < text.endIndex, text[index] == "." {
            value.append(".")
            advance()
            while index < text.endIndex, text[index].isNumber {
                value.append(text[index])
                advance()
            }
        }
        let number = Double(value) ?? 0
        return token(.number(number), start: start)
    }

    private mutating func readString(quote: Character, start: AdocPos) -> LayoutDSLToken {
        advance()
        var value = String()
        while index < text.endIndex {
            let ch = text[index]
            if ch == quote {
                advance()
                return token(.string(value), start: start)
            }
            if ch == "\\" {
                let next = text.index(after: index)
                if next < text.endIndex {
                    value.append(text[next])
                    advance()
                    advance()
                    continue
                }
            }
            value.append(ch)
            advance()
        }
        return token(.string(value), start: start)
    }

    private func isIdentifierStart(_ ch: Character) -> Bool {
        return ch.isLetter || ch == "_"
    }

    private func isIdentifierPart(_ ch: Character) -> Bool {
        return ch.isLetter || ch.isNumber || ch == "_" || ch == "-"
    }

    private mutating func advance() {
        guard index < text.endIndex else { return }
        if text[index] == "\n" {
            line += 1
            column = 1
        } else {
            column += 1
        }
        index = text.index(after: index)
    }

    private func position() -> AdocPos {
        AdocPos(offset: index, line: line, column: column)
    }

    private func token(_ kind: LayoutDSLTokenKind, start: AdocPos) -> LayoutDSLToken {
        let end = position()
        let span = AdocRange(start: start, end: end)
        return LayoutDSLToken(kind: kind, span: span)
    }
}

private struct LayoutDSLParserState {
    var tokenizer: LayoutDSLTokenizer
    var lookahead: LayoutDSLToken?
    var warnings: [AdocWarning] = []
    let baseSpan: AdocRange?

    init(tokenizer: LayoutDSLTokenizer, span: AdocRange?) {
        self.tokenizer = tokenizer
        self.baseSpan = span
    }

    mutating func parseProgram() -> LayoutProgram? {
        let exprs = parseExprList(terminators: [.eof])
        if exprs.isEmpty {
            return nil
        }
        return LayoutProgram(expressions: exprs)
    }

    mutating func parseExprList(terminators: [LayoutDSLTokenKind]) -> [LayoutExpr] {
        var exprs: [LayoutExpr] = []
        while true {
            let token = peek()
            if token.kind == .eof {
                break
            }
            if terminators.contains(where: { $0 == token.kind }) {
                break
            }
            if let expr = parseExpr() {
                exprs.append(expr)
            } else {
                _ = advance()
            }
            if consumeIf(.comma) || consumeIf(.semicolon) {
                continue
            }
        }
        return exprs
    }

    mutating func parseExpr() -> LayoutExpr? {
        guard let token = peekIdentifierOrValueStart() else {
            warn("expected expression", span: peek().span)
            return nil
        }
        switch token.kind {
        case .identifier(let name):
            let saved = token
            _ = advance()
            if consumeIf(.lparen) {
                let args = parseArgList(closing: .rparen)
                _ = consumeExpected(.rparen, message: "expected ')' to close arguments")
                let children = parseChildrenIfPresent()
                let span = mergeSpan(saved.span, children.span)
                let node = LayoutNode(name: name, args: args, children: children.nodes, span: span)
                return .node(node)
            }
            if consumeIf(.lbracket) {
                let children = parseExprList(terminators: [.rbracket, .eof])
                _ = consumeExpected(.rbracket, message: "expected ']' to close children")
                let span = mergeSpan(saved.span, peek().span)
                let node = LayoutNode(name: name, args: [], children: children, span: span)
                return .node(node)
            }
            return .value(parseRefFromFirst(name: name, span: saved.span))
        default:
            return parseValue().map { .value($0) }
        }
    }

    mutating func parseChildrenIfPresent() -> (nodes: [LayoutExpr], span: AdocRange?) {
        guard consumeIf(.lbracket) else { return ([], nil) }
        let children = parseExprList(terminators: [.rbracket, .eof])
        let closing = consumeExpected(.rbracket, message: "expected ']' to close children")
        let span = mergeSpan(children.first?.span, closing?.span)
        return (children, span)
    }

    mutating func parseArgList(closing: LayoutDSLTokenKind) -> [LayoutArg] {
        var args: [LayoutArg] = []
        while true {
            let next = peek()
            if next.kind == .eof { break }
            if next.kind == closing { break }
            if let arg = parseArg() {
                args.append(arg)
            } else {
                _ = advance()
            }
            if consumeIf(.comma) { continue }
        }
        return args
    }

    mutating func parseArg() -> LayoutArg? {
        let token = peek()
        if case .identifier(let name) = token.kind {
            let next = peekSecond()
            if next.kind == .colon {
                let saved = token
                _ = advance()
                _ = consumeExpected(.colon, message: "expected ':' after argument name")
                if let expr = parseExpr() {
                    return LayoutArg(name: name, value: expr, span: mergeSpan(saved.span, expr.span))
                }
                warn("expected expression after ':'", span: peek().span)
                return LayoutArg(name: name, value: .value(.null), span: saved.span)
            }
        }

        if let expr = parseExpr() {
            return LayoutArg(name: nil, value: expr, span: expr.span)
        }
        return nil
    }

    mutating func parseValue() -> LayoutValue? {
        let token = peek()
        switch token.kind {
        case .string(let value):
            _ = advance()
            return .string(value)
        case .number(let value):
            _ = advance()
            return .number(value)
        case .boolean(let value):
            _ = advance()
            return .boolean(value)
        case .null:
            _ = advance()
            return .null
        case .lbracket:
            return parseArray()
        case .lbrace:
            return parseDict()
        case .identifier(let name):
            _ = advance()
            return parseRefFromFirst(name: name, span: token.span)
        default:
            warn("expected value", span: token.span)
            return nil
        }
    }

    mutating func parseArray() -> LayoutValue {
        _ = consumeExpected(.lbracket, message: "expected '[' to start array")
        var values: [LayoutValue] = []
        while true {
            let next = peek()
            if next.kind == .eof { break }
            if next.kind == .rbracket { break }
            if let value = parseValue() {
                values.append(value)
            } else {
                _ = advance()
            }
            if consumeIf(.comma) { continue }
        }
        _ = consumeExpected(.rbracket, message: "expected ']' to close array")
        return .array(values)
    }

    mutating func parseDict() -> LayoutValue {
        _ = consumeExpected(.lbrace, message: "expected '{' to start dictionary")
        var dict: [String: LayoutValue] = [:]
        while true {
            let next = peek()
            if next.kind == .eof { break }
            if next.kind == .rbrace { break }
            guard let key = parseDictKey() else {
                _ = advance()
                continue
            }
            _ = consumeExpected(.colon, message: "expected ':' after dictionary key")
            if let value = parseValue() {
                dict[key] = value
            } else {
                dict[key] = .null
            }
            if consumeIf(.comma) { continue }
        }
        _ = consumeExpected(.rbrace, message: "expected '}' to close dictionary")
        return .dict(dict)
    }

    mutating func parseDictKey() -> String? {
        let token = peek()
        switch token.kind {
        case .identifier(let name):
            _ = advance()
            return name
        case .string(let value):
            _ = advance()
            return value
        default:
            warn("expected dictionary key", span: token.span)
            return nil
        }
    }

    mutating func parseRefFromFirst(name: String, span: AdocRange?) -> LayoutValue {
        var parts = [name]
        var index: LayoutIndex? = nil
        while true {
            if consumeIf(.dot) {
                if case .identifier(let nextName) = peek().kind {
                    _ = advance()
                    parts.append(nextName)
                } else {
                    warn("expected identifier after '.'", span: peek().span)
                    break
                }
                continue
            }
            if consumeIf(.lbracket) {
                index = parseIndex()
                _ = consumeExpected(.rbracket, message: "expected ']' after index")
                break
            }
            break
        }
        return .ref(LayoutRef(parts: parts, index: index))
    }

    mutating func parseIndex() -> LayoutIndex? {
        let token = peek()
        switch token.kind {
        case .number(let value):
            _ = advance()
            return .number(value)
        case .string(let value):
            _ = advance()
            return .string(value)
        case .identifier(let value):
            _ = advance()
            return .identifier(value)
        default:
            warn("expected index value", span: token.span)
            return nil
        }
    }

    mutating func peek() -> LayoutDSLToken {
        if let lookahead { return lookahead }
        let token = tokenizer.nextToken()
        lookahead = token
        return token
    }

    mutating func peekSecond() -> LayoutDSLToken {
        _ = peek()
        var snapshot = tokenizer
        return snapshot.nextToken()
    }

    mutating func advance() -> LayoutDSLToken {
        let token = peek()
        lookahead = nil
        return token
    }

    mutating func consumeIf(_ kind: LayoutDSLTokenKind) -> Bool {
        if peek().kind == kind {
            _ = advance()
            return true
        }
        return false
    }

    mutating func consumeExpected(_ kind: LayoutDSLTokenKind, message: String) -> LayoutDSLToken? {
        if peek().kind == kind {
            return advance()
        }
        warn(message, span: peek().span)
        return nil
    }

    mutating func peekIdentifierOrValueStart() -> LayoutDSLToken? {
        let token = peek()
        switch token.kind {
        case .identifier, .string, .number, .boolean, .null, .lbracket, .lbrace:
            return token
        default:
            return nil
        }
    }

    mutating func warn(_ message: String, span: AdocRange?) {
        warnings.append(AdocWarning(message: message, span: span))
    }

    func mergeSpan(_ a: AdocRange?, _ b: AdocRange?) -> AdocRange? {
        guard let a, let b else { return a ?? b }
        return AdocRange(start: a.start, end: b.end)
    }
}

private extension LayoutExpr {
    var span: AdocRange? {
        switch self {
        case .node(let node):
            return node.span
        case .value:
            return nil
        }
    }
}
