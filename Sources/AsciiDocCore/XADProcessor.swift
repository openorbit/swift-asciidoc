//
// Copyright (c) 2026 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

import Foundation
import YYJSON

public struct XADProcessor: Sendable {
    public init() {}

    public func apply(document: AdocDocument) -> AdocDocument {
        var env = AttrEnv(
            initial: document.attributes,
            typedAttributes: document.typedAttributes,
            xadOptions: document.xadOptions
        )
        var warnings = document.warnings
        let processed = processBlocks(
            document.blocks,
            env: &env,
            warnings: &warnings,
            locals: [:]
        )
        var updated = document
        updated.blocks = processed
        updated.warnings = warnings
        updated.attributes = env.values
        updated.typedAttributes = env.typedValues
        return updated
    }
}

private extension XADProcessor {
    func processBlocks(
        _ blocks: [AdocBlock],
        env: inout AttrEnv,
        warnings: inout [AdocWarning],
        locals: [String: XADAttributeValue]
    ) -> [AdocBlock] {
        var result: [AdocBlock] = []
        var index = 0

        while index < blocks.count {
            let block = blocks[index]
            if case .blockMacro(let macro) = block {
                let name = macro.name.lowercased()
                if name == "if" {
                    let (endIndex, output) = expandIf(
                        from: index,
                        blocks: blocks,
                        env: &env,
                        warnings: &warnings,
                        locals: locals
                    )
                    result.append(contentsOf: output)
                    index = endIndex + 1
                    continue
                }
                if name == "for" {
                    let (endIndex, output) = expandFor(
                        from: index,
                        blocks: blocks,
                        env: &env,
                        warnings: &warnings,
                        locals: locals
                    )
                    result.append(contentsOf: output)
                    index = endIndex + 1
                    continue
                }
                if name == "elif" {
                    warnings.append(
                        AdocWarning(
                            message: "elif without open if block",
                            span: macro.span
                        )
                    )
                    index += 1
                    continue
                }
                if name == "else" {
                    warnings.append(
                        AdocWarning(
                            message: "else without open if block",
                            span: macro.span
                        )
                    )
                    index += 1
                    continue
                }
                if name == "end" {
                    warnings.append(
                        AdocWarning(
                            message: "end without open control block",
                            span: macro.span
                        )
                    )
                    index += 1
                    continue
                }
            }

            let transformed = transformBlock(block, env: &env, warnings: &warnings, locals: locals)
            result.append(transformed)
            index += 1
        }

        return result
    }

    func transformBlock(
        _ block: AdocBlock,
        env: inout AttrEnv,
        warnings: inout [AdocWarning],
        locals: [String: XADAttributeValue]
    ) -> AdocBlock {
        switch block {
        case .section(var section):
            section.title = expandText(section.title, env: env, locals: locals)
            section.blocks = processBlocks(section.blocks, env: &env, warnings: &warnings, locals: locals)
            return .section(section)

        case .paragraph(var para):
            para.text = expandText(para.text, env: env, locals: locals)
            return .paragraph(para)

        case .listing(var listing):
            listing.text = expandText(listing.text, env: env, locals: locals)
            return .listing(listing)

        case .literalBlock(var literal):
            literal.text = expandText(literal.text, env: env, locals: locals)
            return .literalBlock(literal)

        case .discreteHeading(var heading):
            heading.title = expandText(heading.title, env: env, locals: locals)
            return .discreteHeading(heading)

        case .list(var list):
            list.items = list.items.map { item in
                var copy = item
                copy.principal = expandText(item.principal, env: env, locals: locals)
                copy.blocks = processBlocks(item.blocks, env: &env, warnings: &warnings, locals: locals)
                return copy
            }
            return .list(list)

        case .dlist(var dlist):
            dlist.items = dlist.items.map { item in
                var copy = item
                copy.term = expandText(item.term, env: env, locals: locals)
                if let principal = item.principal {
                    copy.principal = expandText(principal, env: env, locals: locals)
                }
                copy.blocks = processBlocks(item.blocks, env: &env, warnings: &warnings, locals: locals)
                return copy
            }
            return .dlist(dlist)

        case .sidebar(var sidebar):
            sidebar.title = sidebar.title.map { expandText($0, env: env, locals: locals) }
            sidebar.blocks = processBlocks(sidebar.blocks, env: &env, warnings: &warnings, locals: locals)
            return .sidebar(sidebar)

        case .example(var example):
            example.title = example.title.map { expandText($0, env: env, locals: locals) }
            example.blocks = processBlocks(example.blocks, env: &env, warnings: &warnings, locals: locals)
            return .example(example)

        case .quote(var quote):
            quote.title = quote.title.map { expandText($0, env: env, locals: locals) }
            quote.attribution = quote.attribution.map { expandText($0, env: env, locals: locals) }
            quote.citetitle = quote.citetitle.map { expandText($0, env: env, locals: locals) }
            quote.blocks = processBlocks(quote.blocks, env: &env, warnings: &warnings, locals: locals)
            return .quote(quote)

        case .open(var open):
            open.title = open.title.map { expandText($0, env: env, locals: locals) }
            open.blocks = processBlocks(open.blocks, env: &env, warnings: &warnings, locals: locals)
            return .open(open)

        case .admonition(var admonition):
            admonition.title = admonition.title.map { expandText($0, env: env, locals: locals) }
            admonition.blocks = processBlocks(admonition.blocks, env: &env, warnings: &warnings, locals: locals)
            return .admonition(admonition)

        case .verse(var verse):
            verse.title = verse.title.map { expandText($0, env: env, locals: locals) }
            verse.attribution = verse.attribution.map { expandText($0, env: env, locals: locals) }
            verse.citetitle = verse.citetitle.map { expandText($0, env: env, locals: locals) }
            if let text = verse.text {
                verse.text = expandText(text, env: env, locals: locals)
            }
            verse.blocks = processBlocks(verse.blocks, env: &env, warnings: &warnings, locals: locals)
            return .verse(verse)

        default:
            return block
        }
    }

    func expandIf(
        from startIndex: Int,
        blocks: [AdocBlock],
        env: inout AttrEnv,
        warnings: inout [AdocWarning],
        locals: [String: XADAttributeValue]
    ) -> (Int, [AdocBlock]) {
        guard case .blockMacro(let ifMacro) = blocks[startIndex] else {
            return (startIndex, [])
        }
        let initialCond = conditionExpression(from: ifMacro)
        var branches: [(cond: String?, blocks: [AdocBlock])] = [
            (cond: initialCond, blocks: [])
        ]
        var currentIndex = startIndex + 1
        var depth = 0
        var sawElse = false

        while currentIndex < blocks.count {
            let block = blocks[currentIndex]
            if case .blockMacro(let macro) = block {
                let name = macro.name.lowercased()
                if name == "if" || name == "for" {
                    depth += 1
                    branches[branches.count - 1].blocks.append(block)
                    currentIndex += 1
                    continue
                }
                if name == "end" {
                    if depth == 0 {
                        if let target = macro.target?.lowercased(), !target.isEmpty, target != "if" {
                            warnings.append(
                                AdocWarning(
                                    message: "end::\(target) does not match current if block",
                                    span: macro.span
                                )
                            )
                        }
                        break
                    }
                    depth -= 1
                    branches[branches.count - 1].blocks.append(block)
                    currentIndex += 1
                    continue
                }
                if depth == 0 && name == "elif" {
                    if sawElse {
                        warnings.append(
                            AdocWarning(
                                message: "elif after else in if block",
                                span: macro.span
                            )
                        )
                        currentIndex += 1
                        continue
                    }
                    branches.append((cond: conditionExpression(from: macro), blocks: []))
                    currentIndex += 1
                    continue
                }
                if depth == 0 && name == "else" {
                    if sawElse {
                        warnings.append(
                            AdocWarning(
                                message: "multiple else in if block",
                                span: macro.span
                            )
                        )
                        currentIndex += 1
                        continue
                    }
                    sawElse = true
                    branches.append((cond: nil, blocks: []))
                    currentIndex += 1
                    continue
                }
            }

            branches[branches.count - 1].blocks.append(block)
            currentIndex += 1
        }

        if currentIndex >= blocks.count {
            warnings.append(
                AdocWarning(
                    message: "Missing end for if directive",
                    span: ifMacro.span
                )
            )
            return (blocks.count - 1, Array(blocks[startIndex..<blocks.count]))
        }

        var selected: [AdocBlock] = []
        for branch in branches {
            if let cond = branch.cond {
                if evaluateCondition(cond, env: env, locals: locals) {
                    selected = branch.blocks
                    break
                }
            } else {
                selected = branch.blocks
                break
            }
        }

        let processed = processBlocks(selected, env: &env, warnings: &warnings, locals: locals)
        return (currentIndex, processed)
    }

    func expandFor(
        from startIndex: Int,
        blocks: [AdocBlock],
        env: inout AttrEnv,
        warnings: inout [AdocWarning],
        locals: [String: XADAttributeValue]
    ) -> (Int, [AdocBlock]) {
        guard case .blockMacro(let forMacro) = blocks[startIndex] else {
            return (startIndex, [])
        }

        var body: [AdocBlock] = []
        var currentIndex = startIndex + 1
        var depth = 0

        while currentIndex < blocks.count {
            let block = blocks[currentIndex]
            if case .blockMacro(let macro) = block {
                let name = macro.name.lowercased()
                if name == "if" || name == "for" {
                    depth += 1
                    body.append(block)
                    currentIndex += 1
                    continue
                }
                if name == "end" {
                    if depth == 0 {
                        if let target = macro.target?.lowercased(), !target.isEmpty, target != "for" {
                            warnings.append(
                                AdocWarning(
                                    message: "end::\(target) does not match current for block",
                                    span: macro.span
                                )
                            )
                        }
                        break
                    }
                    depth -= 1
                    body.append(block)
                    currentIndex += 1
                    continue
                }
            }
            body.append(block)
            currentIndex += 1
        }

        if currentIndex >= blocks.count {
            warnings.append(
                AdocWarning(
                    message: "Missing end for for directive",
                    span: forMacro.span
                )
            )
            return (blocks.count - 1, Array(blocks[startIndex..<blocks.count]))
        }

        guard let inExpr = forMacro.attributes["in"] ?? targetFallback(from: forMacro) else {
            warnings.append(
                AdocWarning(
                    message: "for directive missing in expression",
                    span: forMacro.span
                )
            )
            return (currentIndex, [])
        }

        let indexName = forMacro.attributes["index"]
        let itemName = forMacro.attributes["item"]
        let keyName = forMacro.attributes["key"]
        let valueName = forMacro.attributes["value"]

        guard let collection = evaluateValue(inExpr, env: env, locals: locals) else {
            warnings.append(
                AdocWarning(
                    message: "for directive could not resolve in expression",
                    span: forMacro.span
                )
            )
            return (currentIndex, [])
        }

        var expanded: [AdocBlock] = []
        switch collection {
        case .array(let items):
            guard let indexName, let itemName else {
                warnings.append(
                    AdocWarning(
                        message: "for array iteration requires index and item",
                        span: forMacro.span
                    )
                )
                return (currentIndex, [])
            }
            for (idx, value) in items.enumerated() {
                var loopLocals = locals
                loopLocals[indexName] = .number(Double(idx))
                loopLocals[itemName] = value
                let processed = processBlocks(body, env: &env, warnings: &warnings, locals: loopLocals)
                expanded.append(contentsOf: processed)
            }

        case .dictionary(let dict):
            guard let keyName, let valueName else {
                warnings.append(
                    AdocWarning(
                        message: "for dictionary iteration requires key and value",
                        span: forMacro.span
                    )
                )
                return (currentIndex, [])
            }
            for (key, value) in dict {
                var loopLocals = locals
                loopLocals[keyName] = .string(key)
                loopLocals[valueName] = value
                let processed = processBlocks(body, env: &env, warnings: &warnings, locals: loopLocals)
                expanded.append(contentsOf: processed)
            }

        default:
            warnings.append(
                AdocWarning(
                    message: "for directive expects array or dictionary",
                    span: forMacro.span
                )
            )
        }

        return (currentIndex, expanded)
    }

    func conditionExpression(from macro: AdocBlockMacro) -> String? {
        if let cond = macro.attributes["cond"] { return cond }
        return targetFallback(from: macro)
    }

    func targetFallback(from macro: AdocBlockMacro) -> String? {
        let trimmed = macro.target?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension XADProcessor {
    enum ExprToken: Equatable {
        case lparen
        case rparen
        case op(String)
        case identifier(String)
        case string(String)
        case number(Double)
        case bool(Bool)
        case null
        case variable(String)
    }

    func evaluateCondition(_ expr: String, env: AttrEnv, locals: [String: XADAttributeValue]) -> Bool {
        guard let value = evaluateExpression(expr, env: env, locals: locals) else { return false }
        return isTruthy(value)
    }

    func evaluateValue(_ expr: String, env: AttrEnv, locals: [String: XADAttributeValue]) -> XADAttributeValue? {
        let trimmed = expr.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            if let parsed = XADAttributeValue.parse(from: trimmed, xadOptions: env.xadOptions) {
                return parsed
            }
        }
        return evaluateExpression(expr, env: env, locals: locals)
    }

    func evaluateExpression(_ expr: String, env: AttrEnv, locals: [String: XADAttributeValue]) -> XADAttributeValue? {
        guard let tokens = tokenize(expr) else { return nil }
        var parser = ExprParser(tokens: tokens) { name in
            resolveValue(name, env: env, locals: locals)
        }
        return parser.parseExpression()
    }

    func tokenize(_ expr: String) -> [ExprToken]? {
        var tokens: [ExprToken] = []
        var index = expr.startIndex

        func peekChar() -> Character? {
            guard index < expr.endIndex else { return nil }
            return expr[index]
        }

        func advance() {
            index = expr.index(after: index)
        }

        while let ch = peekChar() {
            if ch.isWhitespace {
                advance()
                continue
            }

            if ch == "(" {
                tokens.append(.lparen)
                advance()
                continue
            }

            if ch == ")" {
                tokens.append(.rparen)
                advance()
                continue
            }

            if ch == "{" {
                let start = expr.index(after: index)
                guard let close = expr[start...].firstIndex(of: "}") else { return nil }
                let content = expr[start..<close].trimmingCharacters(in: .whitespacesAndNewlines)
                tokens.append(.variable(String(content)))
                index = expr.index(after: close)
                continue
            }

            if ch == "\"" || ch == "'" {
                let quote = ch
                advance()
                var value = ""
                while let next = peekChar() {
                    if next == "\\" {
                        advance()
                        if let escaped = peekChar() {
                            value.append(escaped)
                            advance()
                        }
                        continue
                    }
                    if next == quote {
                        advance()
                        break
                    }
                    value.append(next)
                    advance()
                }
                tokens.append(.string(value))
                continue
            }

            if ch.isNumber || (ch == "-" && expr.index(after: index) < expr.endIndex && expr[expr.index(after: index)].isNumber) {
                var number = String(ch)
                advance()
                while let next = peekChar(), next.isNumber || next == "." {
                    number.append(next)
                    advance()
                }
                if let value = Double(number) {
                    tokens.append(.number(value))
                    continue
                }
                return nil
            }

            let twoChar = String(expr[index...].prefix(2))
            if ["==", "!=", "<=", ">="].contains(twoChar) {
                tokens.append(.op(twoChar))
                index = expr.index(index, offsetBy: 2)
                continue
            }
            if ch == "<" || ch == ">" {
                tokens.append(.op(String(ch)))
                advance()
                continue
            }

            if ch.isLetter || ch == "_" {
                var ident = String(ch)
                advance()
                while let next = peekChar(), next.isLetter || next.isNumber || next == "_" || next == "." || next == "[" || next == "]" {
                    ident.append(next)
                    advance()
                }
                let lowered = ident.lowercased()
                if lowered == "and" || lowered == "or" || lowered == "not" {
                    tokens.append(.op(lowered))
                } else if lowered == "true" {
                    tokens.append(.bool(true))
                } else if lowered == "false" {
                    tokens.append(.bool(false))
                } else if lowered == "null" {
                    tokens.append(.null)
                } else {
                    tokens.append(.identifier(ident))
                }
                continue
            }

            return nil
        }

        return tokens
    }

    func resolveValue(_ name: String, env: AttrEnv, locals: [String: XADAttributeValue]) -> XADAttributeValue? {
        if let local = locals[name] {
            return local
        }
        if let typed = env.resolveTypedValue(name) {
            return typed
        }
        if let raw = env.resolveAttribute(name) {
            return parseScalar(raw)
        }
        return nil
    }

    func parseScalar(_ raw: String) -> XADAttributeValue {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()
        if lowered == "true" { return .bool(true) }
        if lowered == "false" { return .bool(false) }
        if lowered == "null" { return .null }
        if let number = Double(trimmed) { return .number(number) }
        return .string(trimmed)
    }

    func isTruthy(_ value: XADAttributeValue) -> Bool {
        switch value {
        case .bool(let b):
            return b
        case .number(let n):
            return n != 0
        case .string(let s):
            return !s.isEmpty
        case .null:
            return false
        case .array(let array):
            return !array.isEmpty
        case .dictionary(let dict):
            return !dict.isEmpty
        }
    }

    func expandText(_ text: AdocText, env: AttrEnv, locals: [String: XADAttributeValue]) -> AdocText {
        let expanded = expandString(text.plain, env: env, locals: locals)
        return AdocText(plain: expanded, span: text.span)
    }

    func expandString(_ value: String, env: AttrEnv, locals: [String: XADAttributeValue]) -> String {
        guard !locals.isEmpty else { return env.expand(value) }
        var localEnv = env
        for (key, val) in locals {
            switch val {
            case .string(let s):
                localEnv.applyAttributeSet(name: key, value: s)
            case .number(let n):
                localEnv.applyAttributeSet(name: key, value: formatNumber(n))
            case .bool(let b):
                localEnv.applyAttributeSet(name: key, value: b ? "true" : "false")
            case .null:
                localEnv.applyAttributeSet(name: key, value: "null")
            case .array, .dictionary:
                localEnv.applyAttributeSet(name: key, value: jsonString(from: val))
            }
        }
        return localEnv.expand(value)
    }

    func formatNumber(_ value: Double) -> String {
        if value.isFinite,
           value.rounded() == value,
           value >= Double(Int.min),
           value <= Double(Int.max) {
            return String(Int(value))
        }
        return String(value)
    }

    func jsonString(from value: XADAttributeValue) -> String {
        let obj = value.toJSONCompatible()
        guard YYJSONSerialization.isValidJSONObject(obj),
              let data = try? YYJSONSerialization.data(withJSONObject: obj, options: []) else {
            return ""
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

private struct ExprParser {
    private var tokens: [XADProcessor.ExprToken]
    private var index: Int = 0
    private let resolver: (String) -> XADAttributeValue?

    init(tokens: [XADProcessor.ExprToken], resolver: @escaping (String) -> XADAttributeValue?) {
        self.tokens = tokens
        self.resolver = resolver
    }

    mutating func parseExpression() -> XADAttributeValue? {
        parseOr()
    }

    private mutating func parseOr() -> XADAttributeValue? {
        guard var lhs = parseAnd() else { return nil }
        while matchOp("or") {
            guard let rhs = parseAnd() else { return nil }
            lhs = .bool(isTruthy(lhs) || isTruthy(rhs))
        }
        return lhs
    }

    private mutating func parseAnd() -> XADAttributeValue? {
        guard var lhs = parseNot() else { return nil }
        while matchOp("and") {
            guard let rhs = parseNot() else { return nil }
            lhs = .bool(isTruthy(lhs) && isTruthy(rhs))
        }
        return lhs
    }

    private mutating func parseNot() -> XADAttributeValue? {
        if matchOp("not") {
            guard let value = parseNot() else { return nil }
            return .bool(!isTruthy(value))
        }
        return parseComparison()
    }

    private mutating func parseComparison() -> XADAttributeValue? {
        guard let lhs = parsePrimary() else { return nil }
        if let op = currentOperator() {
            advance()
            guard let rhs = parsePrimary() else { return nil }
            let result = compare(lhs: lhs, rhs: rhs, op: op)
            return .bool(result)
        }
        return lhs
    }

    private mutating func parsePrimary() -> XADAttributeValue? {
        guard index < tokens.count else { return nil }
        let token = tokens[index]
        index += 1
        switch token {
        case .lparen:
            let inner = parseExpression()
            _ = consume(.rparen)
            return inner
        case .string(let s):
            return .string(s)
        case .number(let n):
            return .number(n)
        case .bool(let b):
            return .bool(b)
        case .null:
            return .null
        case .variable(let name):
            return resolver(name)
        case .identifier(let name):
            return resolver(name)
        case .op:
            return nil
        case .rparen:
            return nil
        }
    }

    private mutating func matchOp(_ op: String) -> Bool {
        guard let token = peek() else { return false }
        if case .op(let value) = token, value == op {
            index += 1
            return true
        }
        return false
    }

    private func currentOperator() -> String? {
        guard let token = peek() else { return nil }
        if case .op(let value) = token, ["==", "!=", "<", "<=", ">", ">="].contains(value) {
            return value
        }
        return nil
    }

    private mutating func consume(_ token: XADProcessor.ExprToken) -> Bool {
        guard let current = peek(), current == token else { return false }
        index += 1
        return true
    }

    private func peek() -> XADProcessor.ExprToken? {
        guard index < tokens.count else { return nil }
        return tokens[index]
    }

    private mutating func advance() {
        index += 1
    }

    private func compare(lhs: XADAttributeValue, rhs: XADAttributeValue, op: String) -> Bool {
        switch (lhs, rhs) {
        case (.number(let l), .number(let r)):
            return compareNumbers(l, r, op)
        case (.string(let l), .string(let r)):
            return compareStrings(l, r, op)
        case (.bool(let l), .bool(let r)):
            return compareBools(l, r, op)
        case (.null, .null):
            return op == "=="
        default:
            let l = stringify(lhs)
            let r = stringify(rhs)
            if op == "==" { return l == r }
            if op == "!=" { return l != r }
            return false
        }
    }

    private func compareNumbers(_ lhs: Double, _ rhs: Double, _ op: String) -> Bool {
        switch op {
        case "==": return lhs == rhs
        case "!=": return lhs != rhs
        case "<": return lhs < rhs
        case "<=": return lhs <= rhs
        case ">": return lhs > rhs
        case ">=": return lhs >= rhs
        default: return false
        }
    }

    private func compareStrings(_ lhs: String, _ rhs: String, _ op: String) -> Bool {
        switch op {
        case "==": return lhs == rhs
        case "!=": return lhs != rhs
        case "<": return lhs < rhs
        case "<=": return lhs <= rhs
        case ">": return lhs > rhs
        case ">=": return lhs >= rhs
        default: return false
        }
    }

    private func compareBools(_ lhs: Bool, _ rhs: Bool, _ op: String) -> Bool {
        switch op {
        case "==": return lhs == rhs
        case "!=": return lhs != rhs
        default: return false
        }
    }

    private func stringify(_ value: XADAttributeValue) -> String {
        switch value {
        case .string(let s): return s
        case .number(let n): return String(n)
        case .bool(let b): return b ? "true" : "false"
        case .null: return "null"
        case .array(let array):
            return "[\(array.map(stringify).joined(separator: ","))]"
        case .dictionary(let dict):
            let parts = dict.map { "\($0.key):\(stringify($0.value))" }
            return "{\(parts.joined(separator: ","))}"
        }
    }

    private func isTruthy(_ value: XADAttributeValue) -> Bool {
        switch value {
        case .bool(let b): return b
        case .number(let n): return n != 0
        case .string(let s): return !s.isEmpty
        case .null: return false
        case .array(let arr): return !arr.isEmpty
        case .dictionary(let dict): return !dict.isEmpty
        }
    }
}
