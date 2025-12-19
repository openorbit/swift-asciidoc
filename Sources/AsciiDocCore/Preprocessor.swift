//
// Copyright (c) 2025 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

import Foundation

public struct Preprocessor: Sendable {
    public enum SafeMode: Sendable {
        case unsafe
        case safe
        case secure
    }

    public struct Options: Sendable {
        public var sourceURL: URL?
        public var safeMode: SafeMode
        public var allowURIRead: Bool
        public var maxDepth: Int
        public var includeResolvers: [IncludeResolver]

        public init(
            sourceURL: URL? = nil,
            safeMode: SafeMode = .unsafe,
            allowURIRead: Bool = true,
            maxDepth: Int = 32,
            includeResolvers: [IncludeResolver] = []
        ) {
            self.sourceURL = sourceURL?.standardizedFileURL
            self.safeMode = safeMode
            self.allowURIRead = allowURIRead
            self.maxDepth = maxDepth
            self.includeResolvers = includeResolvers
        }
    }

    public struct Result: Sendable {
        public var source: PreprocessedSource
        public var attributes: [String: String?]
        public var diagnostics: [String]
    }

    private let options: Options

    public init(options: Options = .init()) {
        self.options = options
    }

    public func process(
        text: String,
        attributes initialAttributes: [String: String?],
        lockedAttributes: Set<String> = []
    ) -> Result {
        var processor = Processor(
            options: options,
            initialAttributes: initialAttributes,
            lockedAttributes: lockedAttributes
        )
        return processor.run(text: text)
    }
}

private extension Preprocessor {
    struct Processor {
        let options: Options
        let locked: Set<String>
        var env: AttrEnv
        var diagnostics: [String] = []
        var outputLines: [String] = []
        var origins: [LineOrigin] = []
        var frames: [SourceFrame] = []
        var conditionals: [ConditionalFrame] = []
        let fileManager = FileManager.default

        init(options: Options, initialAttributes: [String: String?], lockedAttributes: Set<String>) {
            self.options = options
            self.locked = lockedAttributes
            self.env = AttrEnv(initial: initialAttributes)
            
            if options.includeResolvers.isEmpty {
                // Default to file system resolver if none provided
                let fsResolver = FileSystemIncludeResolver(
                    rootDirectory: options.sourceURL?.deletingLastPathComponent(),
                    allowURIRead: options.allowURIRead,
                    safeMode: options.safeMode
                )
                self.resolvers = [fsResolver]
            } else {
                self.resolvers = options.includeResolvers
            }
        }
        
        let resolvers: [IncludeResolver]

        mutating func run(text: String) -> Result {
            let rootLines = splitLines(text)
            let directory = options.sourceURL?.deletingLastPathComponent()
            let rootFrame = SourceFrame(
                lines: rootLines,
                directory: directory,
                filePath: options.sourceURL?.path,
                parentStack: [],
                levelOffset: 0,
                indent: "",
                includeDepth: 0
            )
            frames.append(rootFrame)
            process()
            let rendered = outputLines.joined(separator: "\n")
            let source = PreprocessedSource(text: rendered, lineOrigins: origins)
            return Result(source: source, attributes: env.values, diagnostics: diagnostics)
        }

        mutating func process() {
            while var frame = frames.last {
                if frame.isFinished {
                    frames.removeLast()
                    continue
                }

                let line = frame.nextLine()
                frames[frames.count - 1] = frame
                let originFrames = frame.originStack(for: line.number)
                let isActive = conditionals.last?.isActive ?? true

                if let escaped = unescapeInclude(line.text) {
                    guard isActive else { continue }
                    emit(line: escaped, originFrames: originFrames, frame: frame)
                    continue
                }

                if handleDirectiveLine(
                    line: line,
                    originFrames: originFrames,
                    frame: frame,
                    isActive: isActive
                ) {
                    continue
                }

                guard isActive else { continue }

                if let attr = parseAttributeLine(line.text) {
                    applyAttribute(attr)
                }

                emit(line: line.text, originFrames: originFrames, frame: frame)
            }
        }

        mutating func emit(line: String, originFrames: [LineOrigin.Frame], frame: SourceFrame) {
            let adjusted = apply(levelOffset: frame.levelOffset, to: line)
            let indented: String
            if frame.indent.isEmpty || adjusted.isEmpty || shouldSkipIndent(for: adjusted) {
                indented = adjusted
            } else {
                indented = frame.indent + adjusted
            }
            outputLines.append(indented)
            origins.append(LineOrigin(frames: originFrames))
        }

        mutating func applyAttribute(_ action: AttributeAction) {
            switch action {
            case .set(let name, let value):
                guard !locked.contains(name) else { return }
                env.set(name, to: value)
            case .unset(let name):
                guard !locked.contains(name) else { return }
                env.set(name, to: nil)
            }
        }

        mutating func handleDirectiveLine(
            line: SourceLine,
            originFrames: [LineOrigin.Frame],
            frame: SourceFrame,
            isActive: Bool
        ) -> Bool {
            guard let directive = parseDirective(line.text) else { return false }

            switch directive.kind {
            case .include:
                guard isActive else { return true }
                processInclude(
                    directive: directive,
                    originFrames: originFrames,
                    parentFrame: frame,
                    originalLine: line.text
                )
                return true

            case .ifdef, .ifndef, .ifeval:
                startConditional(
                    directive: directive,
                    parentActive: isActive,
                    originFrames: originFrames,
                    parentFrame: frame
                )
                return true

            case .endif:
                if !conditionals.isEmpty {
                    conditionals.removeLast()
                }
                return true
            }
        }

        mutating func startConditional(
            directive: ParsedDirective,
            parentActive: Bool,
            originFrames: [LineOrigin.Frame],
            parentFrame: SourceFrame
        ) {
            let condition: Bool
            switch directive.kind {
            case .ifdef:
                condition = evaluateIfDef(target: directive.target)
            case .ifndef:
                condition = !evaluateIfDef(target: directive.target)
            case .ifeval:
                condition = evaluateIfEval(expression: directive.body ?? "")
            default:
                condition = true
            }

            if let body = directive.body, !body.isEmpty {
                guard parentActive && condition else { return }
                pushInlineFrame(body: body, originFrames: originFrames, parent: parentFrame)
                return
            }

            let active = parentActive && condition
            conditionals.append(ConditionalFrame(isActive: active))
        }

        mutating func pushInlineFrame(body: String, originFrames: [LineOrigin.Frame], parent: SourceFrame) {
            let lines = splitLines(body)
            let inlineFrame = SourceFrame(
                lines: lines,
                directory: parent.directory,
                filePath: parent.filePath,
                parentStack: originFrames,
                levelOffset: parent.levelOffset,
                indent: parent.indent,
                includeDepth: parent.includeDepth
            )
            frames.append(inlineFrame)
        }

        mutating func processInclude(
            directive: ParsedDirective,
            originFrames: [LineOrigin.Frame],
            parentFrame: SourceFrame,
            originalLine: String
        ) {
            let target = env.expand(directive.target).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !target.isEmpty else { return }

            if parentFrame.includeDepth + 1 > options.maxDepth {
                diagnostics.append("Maximum include depth exceeded at \(target)")
                return
            }

            let includeOptions = IncludeOptions.parse(text: directive.body ?? "", env: env)

            guard let payload = loadInclude(
                target: target,
                parentDirectory: parentFrame.directory
            ) else {
                emit(line: originalLine, originFrames: originFrames, frame: parentFrame)
                return
            }

            let filtered = applyFilters(
                lines: payload.lines,
                options: includeOptions
            )
            guard !filtered.isEmpty else { return }

            let nextLevelOffset = includeOptions.levelOffset.map {
                parentFrame.levelOffset + $0
            } ?? parentFrame.levelOffset

            let indent = parentFrame.indent + (includeOptions.indent ?? "")

            let newFrame = SourceFrame(
                lines: filtered,
                directory: payload.directory,
                filePath: payload.filePath,
                parentStack: originFrames,
                levelOffset: nextLevelOffset,
                indent: indent,
                includeDepth: parentFrame.includeDepth + 1
            )
            frames.append(newFrame)
        }

        func applyFilters(lines: [SourceLine], options: IncludeOptions) -> [SourceLine] {
            var result = lines
            if let tags = options.tags {
                result = filterByTags(lines: result, filter: tags)
            }
            if !options.lines.isEmpty {
                result = filterByLineSelection(lines: result, selections: options.lines)
            }
            return result
        }

        func filterByTags(lines: [SourceLine], filter: IncludeOptions.TagFilter) -> [SourceLine] {
            var active: Set<String> = []
            var output: [SourceLine] = []
            for line in lines {
                if let event = parseTagEvent(line.text) {
                    switch event {
                    case .start(let names):
                        names.forEach { active.insert($0) }
                    case .end(let names):
                        names.forEach { active.remove($0) }
                    }
                    continue
                }

                if !filter.exclude.isDisjoint(with: active) {
                    continue
                }
                if filter.include.isEmpty || !filter.include.isDisjoint(with: active) {
                    output.append(line)
                }
            }
            return output
        }

        func filterByLineSelection(
            lines: [SourceLine],
            selections: [IncludeOptions.LineSelection]
        ) -> [SourceLine] {
            guard !lines.isEmpty else { return [] }
            let maxLine = lines.last?.number ?? 0
            let ranges: [ClosedRange<Int>] = selections.compactMap {
                guard
                    let start = resolveCoordinate($0.start, max: maxLine),
                    let end = resolveCoordinate($0.end, max: maxLine)
                else { return nil }
                return min(start, end)...max(start, end)
            }
            guard !ranges.isEmpty else { return [] }
            return lines.filter { line in
                ranges.contains { $0.contains(line.number) }
            }
        }

        func resolveCoordinate(_ coordinate: IncludeOptions.LineCoordinate, max: Int) -> Int? {
            switch coordinate {
            case .absolute(let value):
                return value >= 1 ? min(value, max) : nil
            case .fromEnd(let value):
                let resolved = max - value + 1
                return resolved >= 1 ? resolved : nil
            }
        }

        mutating func loadInclude(target: String, parentDirectory: URL?) -> IncludePayload? {
            for resolver in resolvers {
                if let result = resolver.resolve(target: target, from: parentDirectory) {
                    let lines = splitLines(result.content)
                    return IncludePayload(
                        lines: lines,
                        directory: result.directory,
                        filePath: result.filePath
                    )
                }
            }
            diagnostics.append("Unresolved include: \(target)")
            return nil
        }

        func evaluateIfDef(target: String) -> Bool {
            let separators = CharacterSet(charactersIn: ",+")
            let names = target
                .components(separatedBy: separators)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard !names.isEmpty else { return false }
            for name in names where env.value(for: name) != nil {
                return true
            }
            return false
        }

        func evaluateIfEval(expression: String) -> Bool {
            let expanded = env.expand(expression)
            let operators = ["==", "!=", ">=", "<=", ">", "<"]
            for op in operators {
                if let range = expanded.range(of: op) {
                    let lhs = expanded[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
                    let rhs = expanded[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                    return compare(lhs: lhs, rhs: rhs, operator: op)
                }
            }
            return false
        }

        func compare(lhs: String, rhs: String, operator op: String) -> Bool {
            let l = stripQuotes(lhs)
            let r = stripQuotes(rhs)
            if let li = Double(l), let ri = Double(r) {
                switch op {
                case "==": return li == ri
                case "!=": return li != ri
                case ">": return li > ri
                case "<": return li < ri
                case ">=": return li >= ri
                case "<=": return li <= ri
                default: return false
                }
            }
            switch op {
            case "==": return l == r
            case "!=": return l != r
            case ">": return l > r
            case "<": return l < r
            case ">=": return l >= r
            case "<=": return l <= r
            default: return false
            }
        }
    }
}

// Models

private struct SourceLine {
    var text: String
    var number: Int
}

private struct SourceFrame {
    var lines: [SourceLine]
    var index: Int = 0
    let directory: URL?
    let filePath: String?
    let parentStack: [LineOrigin.Frame]
    let levelOffset: Int
    let indent: String
    let includeDepth: Int

    var isFinished: Bool { index >= lines.count }

    mutating func nextLine() -> SourceLine {
        let line = lines[index]
        index += 1
        return line
    }

    func originStack(for lineNumber: Int) -> [LineOrigin.Frame] {
        var stack = parentStack
        stack.append(LineOrigin.Frame(file: filePath, line: lineNumber))
        return stack
    }
}

private struct ConditionalFrame {
    var isActive: Bool
}

private enum AttributeAction {
    case set(name: String, value: String)
    case unset(name: String)
}

private enum PreprocessorDirectiveKind {
    case include
    case ifdef
    case ifndef
    case ifeval
    case endif
}

private struct ParsedDirective {
    var kind: PreprocessorDirectiveKind
    var target: String
    var body: String?
}

private struct IncludePayload {
    var lines: [SourceLine]
    var directory: URL?
    var filePath: String?
}

private struct IncludeOptions {
    struct TagFilter {
        var include: Set<String>
        var exclude: Set<String>
    }

    enum LineCoordinate {
        case absolute(Int)
        case fromEnd(Int)
    }

    struct LineSelection {
        var start: LineCoordinate
        var end: LineCoordinate
    }

    var indent: String?
    var levelOffset: Int?
    var lines: [LineSelection] = []
    var tags: TagFilter?

    static func parse(text: String, env: AttrEnv) -> IncludeOptions {
        var options = IncludeOptions()
        for (key, value) in parseOptionPairs(text) {
            switch key.lowercased() {
            case "indent":
                if let raw = value.map(env.expand) {
                    if let count = Int(raw) {
                        options.indent = String(repeating: " ", count: max(0, count))
                    } else {
                        options.indent = raw
                    }
                }
            case "leveloffset":
                if let raw = value.map(env.expand), let delta = Int(raw) {
                    options.levelOffset = delta
                }
            case "lines":
                if let raw = value.map(env.expand) {
                    options.lines = parseLineSelections(raw)
                }
            case "tags", "tag":
                if let raw = value.map(env.expand) {
                    options.tags = parseTagFilter(raw)
                }
            default:
                continue
            }
        }
        return options
    }

    static func parseOptionPairs(_ text: String) -> [(String, String?)] {
        var result: [(String, String?)] = []
        var current = ""
        var inQuotes = false

        func flush() {
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                current.removeAll()
                return
            }
            if let eq = trimmed.firstIndex(of: "=") {
                let key = trimmed[..<eq].trimmingCharacters(in: .whitespacesAndNewlines)
                var value = trimmed[trimmed.index(after: eq)...].trimmingCharacters(in: .whitespacesAndNewlines)
                if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
                    value = String(value.dropFirst().dropLast())
                }
                result.append((key, value))
            } else {
                result.append((trimmed, nil))
            }
            current.removeAll()
        }

        for ch in text {
            if ch == "\"" {
                inQuotes.toggle()
                current.append(ch)
                continue
            }
            if ch == "," && !inQuotes {
                flush()
            } else {
                current.append(ch)
            }
        }
        flush()
        return result
    }

    static func parseLineSelections(_ text: String) -> [LineSelection] {
        text
            .split(whereSeparator: { $0 == "," || $0 == ";" })
            .compactMap { token -> LineSelection? in
                let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                if let range = trimmed.range(of: "..") {
                    let start = String(trimmed[..<range.lowerBound])
                    let end = String(trimmed[range.upperBound...])
                    guard
                        let lhs = parseCoordinate(start),
                        let rhs = parseCoordinate(end)
                    else { return nil }
                    return LineSelection(start: lhs, end: rhs)
                } else if let coord = parseCoordinate(trimmed) {
                    return LineSelection(start: coord, end: coord)
                }
                return nil
            }
    }

    static func parseCoordinate(_ text: String) -> LineCoordinate? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("-"), let value = Int(trimmed.dropFirst()) {
            return .fromEnd(max(1, value))
        }
        if let value = Int(trimmed) {
            return .absolute(max(1, value))
        }
        return nil
    }

    static func parseTagFilter(_ text: String) -> TagFilter {
        var include: Set<String> = []
        var exclude: Set<String> = []
        for token in text.split(whereSeparator: { $0 == "," || $0 == ";" }) {
            let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if trimmed.hasPrefix("!") {
                let name = String(trimmed.dropFirst())
                if !name.isEmpty { exclude.insert(name) }
            } else {
                include.insert(trimmed)
            }
        }
        return TagFilter(include: include, exclude: exclude)
    }
}

// Parsing helpers

private func splitLines(_ text: String) -> [SourceLine] {
    var lines: [SourceLine] = []
    let parts = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
    for (idx, part) in parts.enumerated() {
        lines.append(SourceLine(text: String(part), number: idx + 1))
    }
    return lines
}

private func parseAttributeLine(_ line: String) -> AttributeAction? {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.first == ":" else { return nil }
    var body = trimmed
    body.removeFirst()
    var i = body.startIndex
    let end = body.endIndex
    let nameStart = i
    while i < end, body[i] != ":", body[i] != "!" {
        i = body.index(after: i)
    }
    guard i < end else { return nil }
    let name = String(body[nameStart..<i]).trimmingCharacters(in: .whitespaces)
    guard !name.isEmpty else { return nil }
    if body[i] == "!" {
        i = body.index(after: i)
        guard i < end, body[i] == ":" else { return nil }
        return .unset(name: name)
    }
    i = body.index(after: i)
    if i < end, body[i] == " " { i = body.index(after: i) }
    let value = String(body[i..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
    return .set(name: name, value: value)
}

private func parseDirective(_ line: String) -> ParsedDirective? {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    var i = trimmed.startIndex
    let end = trimmed.endIndex
    let nameStart = i
    while i < end, trimmed[i].isLetter || trimmed[i].isNumber || trimmed[i] == "-" || trimmed[i] == "_" {
        i = trimmed.index(after: i)
    }
    guard i > nameStart else { return nil }
    let name = trimmed[nameStart..<i].lowercased()
    guard i < end, trimmed[i] == ":", trimmed.index(after: i) < end, trimmed[trimmed.index(after: i)] == ":" else {
        return nil
    }
    i = trimmed.index(i, offsetBy: 2)
    var payloadStart = i
    while payloadStart < end, trimmed[payloadStart].isWhitespace {
        payloadStart = trimmed.index(after: payloadStart)
    }

    guard let kind = directiveKind(named: name) else {
        return nil
    }

    guard let open = trimmed[payloadStart...].firstIndex(of: "["),
          let close = trimmed[open...].lastIndex(of: "]"),
          close > open else {
        let target = trimmed[payloadStart...].trimmingCharacters(in: .whitespaces)
        return ParsedDirective(kind: kind, target: target, body: nil)
    }

    let target = trimmed[payloadStart..<open].trimmingCharacters(in: .whitespaces)
    let body = trimmed[trimmed.index(after: open)..<close]
    return ParsedDirective(kind: kind, target: target, body: String(body))
}

private func directiveKind(named name: String) -> PreprocessorDirectiveKind? {
    switch name {
    case "include": return .include
    case "ifdef": return .ifdef
    case "ifndef": return .ifndef
    case "ifeval": return .ifeval
    case "endif": return .endif
    default: return nil
    }
}

private func unescapeInclude(_ line: String) -> String? {
    var index = line.startIndex
    while index < line.endIndex, line[index].isWhitespace {
        index = line.index(after: index)
    }
    guard index < line.endIndex, line[index] == "\\" else { return nil }
    let afterSlash = line.index(after: index)
    guard line[afterSlash...].hasPrefix("include::") else { return nil }
    var result = line
    result.remove(at: index)
    return result
}

private func stripQuotes(_ value: String) -> String {
    guard value.count >= 2 else { return value }
    if value.first == "\"" && value.last == "\"" {
        return String(value.dropFirst().dropLast())
    }
    return value
}

private func apply(levelOffset: Int, to line: String) -> String {
    guard levelOffset != 0 else { return line }
    var index = line.startIndex
    var count = 0
    while index < line.endIndex, line[index] == "=" {
        count += 1
        index = line.index(after: index)
    }
    guard count > 0 else { return line }
    guard index < line.endIndex, line[index] == " " else { return line }
    let newCount = max(1, count + levelOffset)
    let remainder = line[index...]
    return String(repeating: "=", count: newCount) + remainder
}

private func shouldSkipIndent(for line: String) -> Bool {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard let first = trimmed.first else { return false }
    return first == "="
}

private enum TagEvent {
    case start([String])
    case end([String])
}

private func parseTagEvent(_ line: String) -> TagEvent? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard trimmed.hasPrefix("//") else { return nil }
    let body = trimmed.drop(while: { $0 == "/" || $0 == " " })
    if body.hasPrefix("tag::"),
       let open = body.firstIndex(of: "["),
       let close = body.firstIndex(of: "]"),
       close > open {
        let nameStart = body.index(body.startIndex, offsetBy: 5)
        let name = body[nameStart..<open]
        return .start([String(name)])
    }
    if body.hasPrefix("end::"),
       let open = body.firstIndex(of: "["),
       let close = body.firstIndex(of: "]"),
       close > open {
        let nameStart = body.index(body.startIndex, offsetBy: 5)
        let name = body[nameStart..<open]
        return .end([String(name)])
    }
    return nil
}
