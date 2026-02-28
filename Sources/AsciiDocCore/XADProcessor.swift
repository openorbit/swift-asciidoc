//
// Copyright (c) 2026 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

import Foundation
import YYJSON

private enum MacroKind {
    case block
    case inline
}

private struct MacroParam {
    let name: String
    let defaultValue: String?
}

private struct MacroDefinition {
    let name: String
    let kind: MacroKind
    let params: [MacroParam]
    let body: [AdocBlock]
    let span: AdocRange?
}

public struct XADProcessor: Sendable {
    public init() {}

    public func apply(document: AdocDocument) -> AdocDocument {
        var env = AttrEnv(
            initial: document.attributes,
            typedAttributes: document.typedAttributes,
            xadOptions: document.xadOptions
        )
        var warnings = document.warnings
        let (macroDefs, strippedBlocks) = collectMacroDefinitions(
            from: document.blocks,
            warnings: &warnings
        )
        let processed = processBlocks(
            strippedBlocks,
            env: &env,
            warnings: &warnings,
            locals: [:],
            macros: macroDefs,
            macroStack: []
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
        locals: [String: XADAttributeValue],
        macros: [String: MacroDefinition],
        macroStack: [String]
    ) -> [AdocBlock] {
        var result: [AdocBlock] = []
        var index = 0

        while index < blocks.count {
            let block = blocks[index]
            if case .blockMacro(let macro) = block {
                let name = macro.name
                if let definition = macros[name] {
                    switch definition.kind {
                    case .block:
                        let expanded = expandBlockMacro(
                            macro,
                            definition: definition,
                            env: &env,
                            warnings: &warnings,
                            locals: locals,
                            macros: macros,
                            macroStack: macroStack
                        )
                        result.append(contentsOf: expanded)
                    case .inline:
                        warnings.append(
                            AdocWarning(
                                message: "inline macro used in block context: \(name)",
                                span: macro.span
                            )
                        )
                        result.append(block)
                    }
                    index += 1
                    continue
                }

                let lowered = name.lowercased()
                if lowered == "if" {
                    let (endIndex, output) = expandIf(
                        from: index,
                        blocks: blocks,
                        env: &env,
                        warnings: &warnings,
                        locals: locals,
                        macros: macros,
                        macroStack: macroStack
                    )
                    result.append(contentsOf: output)
                    index = endIndex + 1
                    continue
                }
                if lowered == "for" {
                    let (endIndex, output) = expandFor(
                        from: index,
                        blocks: blocks,
                        env: &env,
                        warnings: &warnings,
                        locals: locals,
                        macros: macros,
                        macroStack: macroStack
                    )
                    result.append(contentsOf: output)
                    index = endIndex + 1
                    continue
                }
                if lowered == "elif" {
                    warnings.append(
                        AdocWarning(
                            message: "elif without open if block",
                            span: macro.span
                        )
                    )
                    index += 1
                    continue
                }
                if lowered == "else" {
                    warnings.append(
                        AdocWarning(
                            message: "else without open if block",
                            span: macro.span
                        )
                    )
                    index += 1
                    continue
                }
                if lowered == "end" {
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

            let transformed = transformBlock(
                block,
                env: &env,
                warnings: &warnings,
                locals: locals,
                macros: macros,
                macroStack: macroStack
            )
            result.append(transformed)
            index += 1
        }

        return result
    }

    func collectMacroDefinitions(
        from blocks: [AdocBlock],
        warnings: inout [AdocWarning]
    ) -> ([String: MacroDefinition], [AdocBlock]) {
        var definitions: [String: MacroDefinition] = [:]
        var output: [AdocBlock] = []
        var index = 0

        while index < blocks.count {
            let block = blocks[index]
            switch block {
            case .section(var section):
                let (childDefs, childBlocks) = collectMacroDefinitions(from: section.blocks, warnings: &warnings)
                section.blocks = childBlocks
                for (name, def) in childDefs { definitions[name] = def }
                output.append(.section(section))
                index += 1

            case .blockMacro(let macro) where macro.name.lowercased() == "macro":
                guard let name = macro.target?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
                    warnings.append(
                        AdocWarning(
                            message: "macro definition missing name",
                            span: macro.span
                        )
                    )
                    index += 1
                    continue
                }
                let (endIndex, body) = collectMacroBody(
                    startIndex: index,
                    macroName: name,
                    blocks: blocks,
                    warnings: &warnings
                )
                if endIndex == index {
                    output.append(block)
                    index += 1
                    continue
                }

                let kind = parseMacroKind(macro.attributes["kind"])
                let params = parseMacroParams(macro.attributes["params"])
                let (nestedDefs, strippedBody) = collectMacroDefinitions(from: body, warnings: &warnings)
                for (nestedName, def) in nestedDefs { definitions[nestedName] = def }

                let definition = MacroDefinition(
                    name: name,
                    kind: kind,
                    params: params,
                    body: strippedBody,
                    span: macro.span
                )
                if definitions[name] != nil {
                    warnings.append(
                        AdocWarning(
                            message: "macro redefinition: \(name)",
                            span: macro.span
                        )
                    )
                }
                definitions[name] = definition
                index = endIndex + 1

            case .blockMacro(let macro) where macro.name.lowercased() == "endmacro":
                warnings.append(
                    AdocWarning(
                        message: "endmacro without open macro",
                        span: macro.span
                    )
                )
                index += 1

            default:
                output.append(block)
                index += 1
            }
        }

        return (definitions, output)
    }

    func collectMacroBody(
        startIndex: Int,
        macroName: String,
        blocks: [AdocBlock],
        warnings: inout [AdocWarning]
    ) -> (Int, [AdocBlock]) {
        var body: [AdocBlock] = []
        var index = startIndex + 1
        var depth = 0

        while index < blocks.count {
            let block = blocks[index]
            if case .blockMacro(let macro) = block {
                let name = macro.name.lowercased()
                if name == "macro" {
                    depth += 1
                    body.append(block)
                    index += 1
                    continue
                }
                if name == "endmacro" {
                    if depth == 0 {
                        if let target = macro.target?.trimmingCharacters(in: .whitespacesAndNewlines),
                           !target.isEmpty,
                           target != macroName {
                            warnings.append(
                                AdocWarning(
                                    message: "endmacro name does not match \(macroName)",
                                    span: macro.span
                                )
                            )
                        }
                        return (index, body)
                    }
                    depth -= 1
                    body.append(block)
                    index += 1
                    continue
                }
            }
            body.append(block)
            index += 1
        }

        warnings.append(
            AdocWarning(
                message: "missing endmacro for \(macroName)",
                span: blocks[startIndex].span
            )
        )
        return (startIndex, [])
    }

    func parseMacroKind(_ raw: String?) -> MacroKind {
        switch raw?.lowercased() {
        case "inline":
            return .inline
        default:
            return .block
        }
    }

    func parseMacroParams(_ raw: String?) -> [MacroParam] {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        let parts = raw.split(separator: ",")
        var params: [MacroParam] = []
        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if let eq = trimmed.firstIndex(of: "=") {
                let name = trimmed[..<eq].trimmingCharacters(in: .whitespacesAndNewlines)
                let valueStart = trimmed.index(after: eq)
                let defaultValue = trimmed[valueStart...].trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty {
                    params.append(MacroParam(name: String(name), defaultValue: String(defaultValue)))
                }
            } else {
                params.append(MacroParam(name: String(trimmed), defaultValue: nil))
            }
        }
        return params
    }

    func bindMacroParams(
        definition: MacroDefinition,
        args: [String: String],
        warnings: inout [AdocWarning],
        span: AdocRange?
    ) -> [String: XADAttributeValue] {
        var locals: [String: XADAttributeValue] = [:]
        let paramNames = Set(definition.params.map { $0.name })

        for param in definition.params {
            if let value = args[param.name] {
                locals[param.name] = .string(value)
            } else if let defaultValue = param.defaultValue {
                locals[param.name] = .string(defaultValue)
            } else {
                warnings.append(
                    AdocWarning(
                        message: "missing macro parameter: \(param.name)",
                        span: span
                    )
                )
            }
        }

        for (key, _) in args where !paramNames.contains(key) {
            warnings.append(
                AdocWarning(
                    message: "unknown macro parameter: \(key)",
                    span: span
                )
            )
        }

        return locals
    }

    func mergeMacroLocals(
        base: [String: XADAttributeValue],
        params: [String: XADAttributeValue],
        warnings: inout [AdocWarning],
        span: AdocRange?
    ) -> [String: XADAttributeValue] {
        var merged = base
        for (key, value) in params {
            if merged[key] != nil {
                warnings.append(
                    AdocWarning(
                        message: "macro parameter shadows local variable: \(key)",
                        span: span
                    )
                )
            }
            merged[key] = value
        }
        return merged
    }

    func expandBlockMacro(
        _ macro: AdocBlockMacro,
        definition: MacroDefinition,
        env: inout AttrEnv,
        warnings: inout [AdocWarning],
        locals: [String: XADAttributeValue],
        macros: [String: MacroDefinition],
        macroStack: [String]
    ) -> [AdocBlock] {
        if macroStack.contains(definition.name) {
            warnings.append(
                AdocWarning(
                    message: "macro recursion detected: \(definition.name)",
                    span: macro.span
                )
            )
            return [.blockMacro(macro)]
        }

        let paramLocals = bindMacroParams(
            definition: definition,
            args: macro.attributes,
            warnings: &warnings,
            span: macro.span
        )
        let mergedLocals = mergeMacroLocals(
            base: locals,
            params: paramLocals,
            warnings: &warnings,
            span: macro.span
        )
        return processBlocks(
            definition.body,
            env: &env,
            warnings: &warnings,
            locals: mergedLocals,
            macros: macros,
            macroStack: macroStack + [definition.name]
        )
    }

    func expandInlineMacros(
        _ inlines: [AdocInline],
        env: AttrEnv,
        macros: [String: MacroDefinition],
        warnings: inout [AdocWarning],
        macroStack: [String]
    ) -> [AdocInline] {
        var result: [AdocInline] = []
        result.reserveCapacity(inlines.count)

        for inline in inlines {
            switch inline {
            case .strong(let xs, let span):
                let mapped = expandInlineMacros(xs, env: env, macros: macros, warnings: &warnings, macroStack: macroStack)
                result.append(.strong(mapped, span: span))
            case .emphasis(let xs, let span):
                let mapped = expandInlineMacros(xs, env: env, macros: macros, warnings: &warnings, macroStack: macroStack)
                result.append(.emphasis(mapped, span: span))
            case .mono(let xs, let span):
                let mapped = expandInlineMacros(xs, env: env, macros: macros, warnings: &warnings, macroStack: macroStack)
                result.append(.mono(mapped, span: span))
            case .mark(let xs, let span):
                let mapped = expandInlineMacros(xs, env: env, macros: macros, warnings: &warnings, macroStack: macroStack)
                result.append(.mark(mapped, span: span))
            case .superscript(let xs, let span):
                let mapped = expandInlineMacros(xs, env: env, macros: macros, warnings: &warnings, macroStack: macroStack)
                result.append(.superscript(mapped, span: span))
            case .subscript(let xs, let span):
                let mapped = expandInlineMacros(xs, env: env, macros: macros, warnings: &warnings, macroStack: macroStack)
                result.append(.subscript(mapped, span: span))
            case .link(let target, let text, let span):
                let mapped = expandInlineMacros(text, env: env, macros: macros, warnings: &warnings, macroStack: macroStack)
                result.append(.link(target: target, text: mapped, span: span))
            case .xref(let target, let text, let span):
                let mapped = expandInlineMacros(text, env: env, macros: macros, warnings: &warnings, macroStack: macroStack)
                result.append(.xref(target: target, text: mapped, span: span))
            case .footnote(let content, let ref, let id, let span):
                let mapped = expandInlineMacros(content, env: env, macros: macros, warnings: &warnings, macroStack: macroStack)
                result.append(.footnote(content: mapped, ref: ref, id: id, span: span))
            case .inlineMacro(let name, let target, let body, let span):
                if let definition = macros[name] {
                    if definition.kind == .inline {
                        if macroStack.contains(definition.name) {
                            warnings.append(
                                AdocWarning(
                                    message: "macro recursion detected: \(definition.name)",
                                    span: span
                                )
                            )
                            result.append(inline)
                            continue
                        }
                        let args = parseMacroAttributeList(body)
                        let paramLocals = bindMacroParams(
                            definition: definition,
                            args: args,
                            warnings: &warnings,
                            span: span
                        )
                        var macroEnv = env
                        for (key, value) in paramLocals {
                            if case .string(let str) = value {
                                macroEnv.applyAttributeSet(name: key, value: str)
                            }
                        }
                        let expandedBlocks = definition.body.map { $0.applyingAttributes(using: macroEnv) }
                        let expandedInlines: [AdocInline]
                        if expandedBlocks.count == 1, case .paragraph(let para) = expandedBlocks[0] {
                            expandedInlines = para.text.inlines
                        } else {
                            warnings.append(
                                AdocWarning(
                                    message: "inline macro body must be a single paragraph: \(definition.name)",
                                    span: span
                                )
                            )
                            let text = expandedBlocks.map { $0.renderAsAsciiDoc() }.joined()
                            expandedInlines = parseInlines(text, baseSpan: span)
                        }
                        let mapped = expandInlineMacros(
                            expandedInlines,
                            env: macroEnv,
                            macros: macros,
                            warnings: &warnings,
                            macroStack: macroStack + [definition.name]
                        )
                        result.append(contentsOf: mapped)
                    } else {
                        warnings.append(
                            AdocWarning(
                                message: "block macro used in inline context: \(name)",
                                span: span
                            )
                        )
                        result.append(inline)
                    }
                } else {
                    result.append(inline)
                }
            default:
                result.append(inline)
            }
        }

        return result
    }

    func transformBlock(
        _ block: AdocBlock,
        env: inout AttrEnv,
        warnings: inout [AdocWarning],
        locals: [String: XADAttributeValue],
        macros: [String: MacroDefinition],
        macroStack: [String]
    ) -> AdocBlock {
        switch block {
        case .section(var section):
            section.title = expandText(section.title, env: env, locals: locals, macros: macros, warnings: &warnings, macroStack: macroStack)
            section.blocks = processBlocks(section.blocks, env: &env, warnings: &warnings, locals: locals, macros: macros, macroStack: macroStack)
            return .section(section)

        case .paragraph(var para):
            para.text = expandText(para.text, env: env, locals: locals, macros: macros, warnings: &warnings, macroStack: macroStack)
            return .paragraph(para)

        case .listing(var listing):
            listing.text = expandText(listing.text, env: env, locals: locals, macros: macros, warnings: &warnings, macroStack: macroStack)
            return .listing(listing)

        case .literalBlock(var literal):
            literal.text = expandText(literal.text, env: env, locals: locals, macros: macros, warnings: &warnings, macroStack: macroStack)
            return .literalBlock(literal)

        case .discreteHeading(var heading):
            heading.title = expandText(heading.title, env: env, locals: locals, macros: macros, warnings: &warnings, macroStack: macroStack)
            return .discreteHeading(heading)

        case .list(var list):
            list.items = list.items.map { item in
                var copy = item
                copy.principal = expandText(item.principal, env: env, locals: locals, macros: macros, warnings: &warnings, macroStack: macroStack)
                copy.blocks = processBlocks(item.blocks, env: &env, warnings: &warnings, locals: locals, macros: macros, macroStack: macroStack)
                return copy
            }
            return .list(list)

        case .dlist(var dlist):
            dlist.items = dlist.items.map { item in
                var copy = item
                copy.term = expandText(item.term, env: env, locals: locals, macros: macros, warnings: &warnings, macroStack: macroStack)
                if let principal = item.principal {
                    copy.principal = expandText(principal, env: env, locals: locals, macros: macros, warnings: &warnings, macroStack: macroStack)
                }
                copy.blocks = processBlocks(item.blocks, env: &env, warnings: &warnings, locals: locals, macros: macros, macroStack: macroStack)
                return copy
            }
            return .dlist(dlist)

        case .sidebar(var sidebar):
            sidebar.title = sidebar.title.map { expandText($0, env: env, locals: locals, macros: macros, warnings: &warnings, macroStack: macroStack) }
            sidebar.blocks = processBlocks(sidebar.blocks, env: &env, warnings: &warnings, locals: locals, macros: macros, macroStack: macroStack)
            return .sidebar(sidebar)

        case .example(var example):
            example.title = example.title.map { expandText($0, env: env, locals: locals, macros: macros, warnings: &warnings, macroStack: macroStack) }
            example.blocks = processBlocks(example.blocks, env: &env, warnings: &warnings, locals: locals, macros: macros, macroStack: macroStack)
            return .example(example)

        case .quote(var quote):
            quote.title = quote.title.map { expandText($0, env: env, locals: locals, macros: macros, warnings: &warnings, macroStack: macroStack) }
            quote.attribution = quote.attribution.map { expandText($0, env: env, locals: locals, macros: macros, warnings: &warnings, macroStack: macroStack) }
            quote.citetitle = quote.citetitle.map { expandText($0, env: env, locals: locals, macros: macros, warnings: &warnings, macroStack: macroStack) }
            quote.blocks = processBlocks(quote.blocks, env: &env, warnings: &warnings, locals: locals, macros: macros, macroStack: macroStack)
            return .quote(quote)

        case .open(var open):
            open.title = open.title.map { expandText($0, env: env, locals: locals, macros: macros, warnings: &warnings, macroStack: macroStack) }
            open.blocks = processBlocks(open.blocks, env: &env, warnings: &warnings, locals: locals, macros: macros, macroStack: macroStack)
            return .open(open)

        case .admonition(var admonition):
            admonition.title = admonition.title.map { expandText($0, env: env, locals: locals, macros: macros, warnings: &warnings, macroStack: macroStack) }
            admonition.blocks = processBlocks(admonition.blocks, env: &env, warnings: &warnings, locals: locals, macros: macros, macroStack: macroStack)
            return .admonition(admonition)

        case .verse(var verse):
            verse.title = verse.title.map { expandText($0, env: env, locals: locals, macros: macros, warnings: &warnings, macroStack: macroStack) }
            verse.attribution = verse.attribution.map { expandText($0, env: env, locals: locals, macros: macros, warnings: &warnings, macroStack: macroStack) }
            verse.citetitle = verse.citetitle.map { expandText($0, env: env, locals: locals, macros: macros, warnings: &warnings, macroStack: macroStack) }
            if let text = verse.text {
                verse.text = expandText(text, env: env, locals: locals, macros: macros, warnings: &warnings, macroStack: macroStack)
            }
            verse.blocks = processBlocks(verse.blocks, env: &env, warnings: &warnings, locals: locals, macros: macros, macroStack: macroStack)
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
        locals: [String: XADAttributeValue],
        macros: [String: MacroDefinition],
        macroStack: [String]
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
                let (ok, unresolved, exprWarnings) = evaluateCondition(cond, env: env, locals: locals)
                for message in exprWarnings {
                    warnings.append(
                        AdocWarning(
                            message: message,
                            span: ifMacro.span
                        )
                    )
                }
                if !unresolved.isEmpty {
                    warnings.append(
                        AdocWarning(
                            message: "unknown variable in if expression: \(unresolved.joined(separator: ", "))",
                            span: ifMacro.span
                        )
                    )
                }
                if let ok {
                    if ok {
                        selected = branch.blocks
                        break
                    }
                } else {
                    warnings.append(
                        AdocWarning(
                            message: "invalid if expression: \(cond)",
                            span: ifMacro.span
                        )
                    )
                }
            } else {
                selected = branch.blocks
                break
            }
        }

        let processed = processBlocks(selected, env: &env, warnings: &warnings, locals: locals, macros: macros, macroStack: macroStack)
        return (currentIndex, processed)
    }

    func expandFor(
        from startIndex: Int,
        blocks: [AdocBlock],
        env: inout AttrEnv,
        warnings: inout [AdocWarning],
        locals: [String: XADAttributeValue],
        macros: [String: MacroDefinition],
        macroStack: [String]
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

        let (collection, unresolved, exprWarnings) = evaluateValue(inExpr, env: env, locals: locals)
        for message in exprWarnings {
            warnings.append(
                AdocWarning(
                    message: message,
                    span: forMacro.span
                )
            )
        }
        if !unresolved.isEmpty {
            warnings.append(
                AdocWarning(
                    message: "unknown variable in for expression: \(unresolved.joined(separator: ", "))",
                    span: forMacro.span
                )
            )
        }
        guard let collection else {
            warnings.append(
                AdocWarning(
                    message: "invalid for in expression: \(inExpr)",
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
            if keyName != nil || valueName != nil {
                warnings.append(
                    AdocWarning(
                        message: "for array iteration does not use key/value",
                        span: forMacro.span
                    )
                )
            }
            for (idx, value) in items.enumerated() {
                var loopLocals = locals
                loopLocals[indexName] = .number(Double(idx))
                loopLocals[itemName] = value
                let processed = processBlocks(body, env: &env, warnings: &warnings, locals: loopLocals, macros: macros, macroStack: macroStack)
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
            if indexName != nil || itemName != nil {
                warnings.append(
                    AdocWarning(
                        message: "for dictionary iteration does not use index/item",
                        span: forMacro.span
                    )
                )
            }
            for (key, value) in dict {
                var loopLocals = locals
                loopLocals[keyName] = .string(key)
                loopLocals[valueName] = value
                let processed = processBlocks(body, env: &env, warnings: &warnings, locals: loopLocals, macros: macros, macroStack: macroStack)
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

    func evaluateCondition(
        _ expr: String,
        env: AttrEnv,
        locals: [String: XADAttributeValue]
    ) -> (Bool?, [String], [String]) {
        var unresolved: [String] = []
        var warnings: [String] = []
        guard let value = evaluateExpression(
            expr,
            env: env,
            locals: locals,
            unresolved: &unresolved,
            warnings: &warnings
        ) else {
            return (nil, unresolved, warnings)
        }
        return (isTruthy(value), unresolved, warnings)
    }

    func evaluateValue(
        _ expr: String,
        env: AttrEnv,
        locals: [String: XADAttributeValue]
    ) -> (XADAttributeValue?, [String], [String]) {
        let trimmed = expr.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            if let parsed = XADAttributeValue.parse(from: trimmed, xadOptions: env.xadOptions) {
                return (parsed, [], [])
            }
        }
        var unresolved: [String] = []
        var warnings: [String] = []
        let value = evaluateExpression(
            expr,
            env: env,
            locals: locals,
            unresolved: &unresolved,
            warnings: &warnings
        )
        return (value, unresolved, warnings)
    }

    func evaluateExpression(
        _ expr: String,
        env: AttrEnv,
        locals: [String: XADAttributeValue],
        unresolved: inout [String],
        warnings: inout [String]
    ) -> XADAttributeValue? {
        guard let tokens = tokenize(expr) else { return nil }
        var localUnresolved: [String] = []
        var localWarnings: [String] = []
        var parser = ExprParser(tokens: tokens, warningSink: { message in
            if !localWarnings.contains(message) {
                localWarnings.append(message)
            }
        }) { name in
            if let resolved = resolveValue(name, env: env, locals: locals) {
                return resolved
            }
            if !localUnresolved.contains(name) {
                localUnresolved.append(name)
            }
            return .null
        }
        let value = parser.parseExpression()
        for name in localUnresolved where !unresolved.contains(name) {
            unresolved.append(name)
        }
        for message in localWarnings where !warnings.contains(message) {
            warnings.append(message)
        }
        return value
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

    func expandText(
        _ text: AdocText,
        env: AttrEnv,
        locals: [String: XADAttributeValue],
        macros: [String: MacroDefinition],
        warnings: inout [AdocWarning],
        macroStack: [String]
    ) -> AdocText {
        let localEnv = localEnvWithLocals(env, locals: locals)
        let attributedInlines = text.inlines.map { $0.applyingAttributes(using: localEnv) }
        let expandedInlines = expandInlineMacros(
            attributedInlines,
            env: localEnv,
            macros: macros,
            warnings: &warnings,
            macroStack: macroStack
        )
        return AdocText(inlines: expandedInlines, span: text.span)
    }

    func expandString(_ value: String, env: AttrEnv, locals: [String: XADAttributeValue]) -> String {
        let localEnv = localEnvWithLocals(env, locals: locals)
        return localEnv.expand(value)
    }

    func localEnvWithLocals(_ env: AttrEnv, locals: [String: XADAttributeValue]) -> AttrEnv {
        guard !locals.isEmpty else { return env }
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
        return localEnv
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
    private let warningSink: (String) -> Void
    private let resolver: (String) -> XADAttributeValue?

    init(
        tokens: [XADProcessor.ExprToken],
        warningSink: @escaping (String) -> Void,
        resolver: @escaping (String) -> XADAttributeValue?
    ) {
        self.tokens = tokens
        self.warningSink = warningSink
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
            if lhs.typeName != rhs.typeName {
                warningSink("type mismatch in comparison: \(lhs.typeName) vs \(rhs.typeName)")
            }
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
private extension XADAttributeValue {
    var typeName: String {
        switch self {
        case .number: return "number"
        case .string: return "string"
        case .bool: return "bool"
        case .null: return "null"
        case .array: return "array"
        case .dictionary: return "dictionary"
        }
    }
}

