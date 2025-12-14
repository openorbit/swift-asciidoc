//
// Copyright (c) 2025 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

import Foundation
import AsciiDocCore

public struct LintWarning: Sendable {
    public enum Kind: String, Sendable {
        case spelling
        case semanticBreak
    }

    public let kind: Kind
    public let message: String
    public let line: Int
    public let column: Int
}

public struct LintOptions: Sendable {
    public var enableSpellcheck: Bool
    public var enableSemanticBreaks: Bool
    public var spellLanguage: String

    public init(enableSpellcheck: Bool = true, enableSemanticBreaks: Bool = true, spellLanguage: String = "en_US") {
        self.enableSpellcheck = enableSpellcheck
        self.enableSemanticBreaks = enableSemanticBreaks
        self.spellLanguage = spellLanguage
    }
}

public struct LintRunner {
    private let document: AdocDocument
    private let sourceText: String
    private let options: LintOptions
    private let spellcheckerFactory: (String) -> Spellchecker?
    private let attrEnvironment: AttrEnv

    public init(
        document: AdocDocument,
        sourceText: String,
        options: LintOptions = .init(),
        spellcheckerFactory: @escaping (String) -> Spellchecker? = { HunspellSpellchecker(language: $0) }
    ) {
        self.document = document
        self.sourceText = sourceText
        self.options = options
        self.spellcheckerFactory = spellcheckerFactory
        self.attrEnvironment = AttrEnv(initial: document.attributes)
    }

    public func run() -> [LintWarning] {
        var docCopy = document
        docCopy.blocks = docCopy.blocks.map { $0.applyingAttributes(using: attrEnvironment) }
        if var header = docCopy.header, let title = header.title {
            header.title = title.applyingAttributes(using: attrEnvironment)
            docCopy.header = header
        }
        let expandedDoc = docCopy
        let expandedSource = attrEnvironment.expand(sourceText)
        let segments = collectSegments(from: expandedDoc)
        let lines = splitLines(expandedSource)
        let eligibleLines = collectEligibleLines(from: segments, lineCount: lines.count)

        var warnings: [LintWarning] = []
        if options.enableSpellcheck {
            warnings.append(
                contentsOf: SpellcheckRule(
                    checker: spellcheckerFactory(options.spellLanguage)
                ).evaluate(on: lines, eligibleLines: eligibleLines)
            )
        }
        if options.enableSemanticBreaks {
            warnings.append(contentsOf: SemanticBreakRule().evaluate(on: lines, eligibleLines: eligibleLines))
        }
        return warnings
    }
}

private struct LintTextSegment {
    let text: String
    let span: AdocRange?
}

private func collectSegments(from doc: AdocDocument) -> [LintTextSegment] {
    var out: [LintTextSegment] = []
    if let header = doc.header {
        append(text: header.title, into: &out)
    }
    for block in doc.blocks {
        collectSegments(from: block, into: &out)
    }
    return out
}

private func collectSegments(from block: AdocBlock, into out: inout [LintTextSegment]) {
    switch block {
    case .paragraph(let p):
        append(text: p.text, into: &out)
        append(text: p.title, into: &out)
        append(text: p.reftext, into: &out)

    case .listing(let l):
        append(text: l.text, into: &out)
        append(text: l.title, into: &out)
        append(text: l.reftext, into: &out)

    case .literalBlock(let l):
        append(text: l.text, into: &out)
        append(text: l.title, into: &out)
        append(text: l.reftext, into: &out)

    case .verse(let v):
        append(text: v.text, into: &out)
        append(text: v.title, into: &out)
        append(text: v.reftext, into: &out)
        append(text: v.attribution, into: &out)
        append(text: v.citetitle, into: &out)
        v.blocks.forEach { collectSegments(from: $0, into: &out) }

    case .section(let s):
        append(text: s.title, into: &out)
        append(text: s.reftext, into: &out)
        s.blocks.forEach { collectSegments(from: $0, into: &out) }

    case .list(let list):
        append(text: list.title, into: &out)
        append(text: list.reftext, into: &out)
        for item in list.items {
            append(text: item.principal, into: &out)
            append(text: item.title, into: &out)
            append(text: item.reftext, into: &out)
            item.blocks.forEach { collectSegments(from: $0, into: &out) }
        }

    case .dlist(let dl):
        append(text: dl.title, into: &out)
        append(text: dl.reftext, into: &out)
        for item in dl.items {
            append(text: item.term, into: &out)
            append(text: item.principal, into: &out)
            append(text: item.title, into: &out)
            append(text: item.reftext, into: &out)
            item.blocks.forEach { collectSegments(from: $0, into: &out) }
        }

    case .sidebar(let s):
        append(text: s.title, into: &out)
        append(text: s.reftext, into: &out)
        s.blocks.forEach { collectSegments(from: $0, into: &out) }

    case .example(let e):
        append(text: e.title, into: &out)
        append(text: e.reftext, into: &out)
        e.blocks.forEach { collectSegments(from: $0, into: &out) }

    case .quote(let q):
        append(text: q.title, into: &out)
        append(text: q.reftext, into: &out)
        append(text: q.attribution, into: &out)
        append(text: q.citetitle, into: &out)
        q.blocks.forEach { collectSegments(from: $0, into: &out) }

    case .open(let o):
        append(text: o.title, into: &out)
        append(text: o.reftext, into: &out)
        o.blocks.forEach { collectSegments(from: $0, into: &out) }

    case .admonition(let a):
        append(text: a.title, into: &out)
        append(text: a.reftext, into: &out)
        a.blocks.forEach { collectSegments(from: $0, into: &out) }

    case .table(let t):
        append(text: t.title, into: &out)
        append(text: t.reftext, into: &out)
        for row in t.cells {
            for cell in row {
                out.append(LintTextSegment(text: cell, span: t.span))
            }
        }

    case .blockMacro(let m):
        append(text: m.title, into: &out)

    case .discreteHeading(let h):
        append(text: h.title, into: &out)

    case .math(let m):
        out.append(LintTextSegment(text: m.body, span: m.span))
        append(text: m.title, into: &out)
        append(text: m.reftext, into: &out)
    }
}

private func append(text: AdocText, into out: inout [LintTextSegment]) {
    out.append(LintTextSegment(text: text.plain, span: text.span))
}

private func append(text: AdocText?, into out: inout [LintTextSegment]) {
    guard let text else { return }
    append(text: text, into: &out)
}

private func splitLines(_ text: String) -> [String] {
    var lines: [String] = []
    var current = ""
    for ch in text {
        if ch == "\n" {
            lines.append(current)
            current.removeAll(keepingCapacity: false)
        } else if ch == "\r" {
            continue
        } else {
            current.append(ch)
        }
    }
    lines.append(current)
    return lines
}

private func collectEligibleLines(from segments: [LintTextSegment], lineCount: Int) -> Set<Int> {
    var set: Set<Int> = []
    for segment in segments {
        guard let span = segment.span else { continue }
        let start = max(1, span.start.line)
        let end = max(start, span.end.line)
        let cappedEnd = min(end, lineCount)
        if start > lineCount { continue }
        for line in start...cappedEnd {
            set.insert(line)
        }
    }
    return set
}

private struct SpellcheckRule {
    private let checker: Spellchecker?

    init(checker: Spellchecker?) {
        self.checker = checker
    }

    func evaluate(on lines: [String], eligibleLines: Set<Int>) -> [LintWarning] {
        guard let checker else { return [] }
        let sortedLines = eligibleLines.sorted()
        var occurrences: [WordOccurrence] = []
        for lineNo in sortedLines {
            guard lineNo >= 1, lineNo <= lines.count else { continue }
            let text = lines[lineNo - 1]
            if text.isEmpty { continue }
            occurrences.append(contentsOf: extractWords(in: text, lineNumber: lineNo))
        }

        guard !occurrences.isEmpty else { return [] }
        var cache: [String: Bool] = [:]
        var warnings: [LintWarning] = []
        for occ in occurrences {
            let key = occ.word.lowercased()
            let isCorrect: Bool
            if let cached = cache[key] {
                isCorrect = cached
            } else {
                isCorrect = checker.isCorrect(occ.word)
                cache[key] = isCorrect
            }
            if !isCorrect {
                warnings.append(
                    LintWarning(
                        kind: .spelling,
                        message: "Unknown word '\(occ.word)'",
                        line: occ.line,
                        column: occ.column
                    )
                )
            }
        }
        return warnings
    }
}

private struct WordOccurrence {
    let word: String
    let line: Int
    let column: Int
}

private func extractWords(in line: String, lineNumber: Int) -> [WordOccurrence] {
    var out: [WordOccurrence] = []
    var idx = line.startIndex
    while idx < line.endIndex {
        while idx < line.endIndex, !line[idx].isLetter {
            idx = line.index(after: idx)
        }
        let start = idx
        while idx < line.endIndex, (line[idx].isLetter || line[idx] == "'") {
            idx = line.index(after: idx)
        }
        if start < idx {
            let word = String(line[start..<idx])
            if word.count > 1 {
                let column = line.distance(from: line.startIndex, to: start) + 1
                out.append(WordOccurrence(word: word, line: lineNumber, column: column))
            }
        }
    }
    return out
}

private struct SemanticBreakRule {
    private let abbreviations: Set<String> = [
        "e.g.", "i.e.", "etc.", "vs.", "v.", "mr.", "mrs.", "ms.", "dr.", "prof.", "sr.", "jr.", "st.", "no."
    ].reduce(into: Set<String>()) { acc, word in
        acc.insert(word)
        acc.insert(word.trimmingCharacters(in: CharacterSet(charactersIn: ".")))
    }

    func evaluate(on lines: [String], eligibleLines: Set<Int>) -> [LintWarning] {
        let sorted = eligibleLines.sorted()
        var warnings: [LintWarning] = []
        for lineNo in sorted {
            guard lineNo >= 1, lineNo <= lines.count else { continue }
            let text = lines[lineNo - 1]
            if needsSemanticBreak(text) {
                warnings.append(
                    LintWarning(
                        kind: .semanticBreak,
                        message: "Multiple sentences detected on one line; consider semantic line breaks.",
                        line: lineNo,
                        column: 1
                    )
                )
            }
        }
        return warnings
    }

    private func needsSemanticBreak(_ line: String) -> Bool {
        var sentenceMarkers = 0
        var idx = line.startIndex
        while idx < line.endIndex {
            let ch = line[idx]
            if ch == "." || ch == "!" || ch == "?" {
                if ignoreMarker(at: idx, in: line, character: ch) {
                    idx = line.index(after: idx)
                    continue
                }
                sentenceMarkers += 1
                if sentenceMarkers > 1 {
                    return true
                }
            }
            idx = line.index(after: idx)
        }
        return false
    }

    private func ignoreMarker(at index: String.Index, in line: String, character: Character) -> Bool {
        if character == "." {
            if isDecimalSeparator(at: index, in: line) || isEllipsis(at: index, in: line) {
                return true
            }
            let nextIdx = line.index(after: index)
            if nextIdx < line.endIndex, line[nextIdx].isLetter {
                return true // middle of abbreviation like e.g.
            }
        }
        if let token = tokenEnding(at: index, in: line) {
            let lowered = token.lowercased()
            if abbreviations.contains(lowered) {
                return true
            }
        }
        return false
    }

    private func isDecimalSeparator(at idx: String.Index, in line: String) -> Bool {
        if idx > line.startIndex {
            let prevIdx = line.index(before: idx)
            if line[prevIdx].isNumber {
                let nextIdx = line.index(after: idx)
                if nextIdx < line.endIndex, line[nextIdx].isNumber {
                    return true
                }
            }
        }
        return false
    }

    private func isEllipsis(at idx: String.Index, in line: String) -> Bool {
        if idx > line.startIndex {
            let before = line.index(before: idx)
            if line[before] == "." {
                let after = line.index(after: idx)
                if after < line.endIndex, line[after] == "." {
                    return true
                }
            }
        }
        return false
    }

    private func tokenEnding(at idx: String.Index, in line: String) -> String? {
        var start = idx
        while start > line.startIndex {
            let prev = line.index(before: start)
            if line[prev].isWhitespace {
                break
            }
            start = prev
        }
        let end = line.index(after: idx)
        let token = String(line[start..<end]).trimmingCharacters(in: CharacterSet(charactersIn: "\"') "))
        return token.isEmpty ? nil : token
    }
}
