//
// Copyright (c) 2025 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

import ArgumentParser
import Foundation
import AsciiDocRender
import AsciiDocCore
import AsciiDocTools
import AsciiDocExtensions

private struct AdapterInput: Decodable {
  enum Payload: String, Decodable {
    case inline
    case block
    case document
  }

  var type: Payload
  var contents: String
  var path: String?
  var attributes: [String: String?]?
}

struct FileLogger: TextOutputStream {
  let out: FileHandle?
  init() {
    out = FileHandle(forWritingAtPath: "asciidoclog.txt")
    if let out {
      try! out.seekToEnd()
    }
  }

  mutating func write(_ string: String) {
    if let data = (string + "\n").data(using: .utf8), let out {
      out.write(data)

    } else {
      print("Bad write")
    }
  }
  mutating func close() {
    try? out?.close()
  }
}



@main
struct AsciiDocSwift: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "asciidoc-swift",
    abstract: "Swift AsciiDoc implementation with a JSON adapter for the Eclipse TCK.",
    subcommands: [JSONAdapter.self, HTML.self, DocBook.self, Latex.self, Lint.self]
  )
}

struct JSONAdapter: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "json-adapter",
    abstract: "Run the JSON adapter: read AdapterInput JSON, emit ASG JSON."
  )

  @Flag(help: "Read AdapterInput JSON from stdin (otherwise last arg is a file path).")
  var stdin: Bool = false
  @Flag(help: "Treat input as plain AsciiDoc instead of JSON.")
  var plain: Bool = false
  @Option(
    name: [.customShort("a"), .customLong("attribute")],
    parsing: .unconditionalSingleValue,
    help: "Set document attribute (name[=value]). Repeatable."
  )
  var attributeAssignments: [String] = []

  mutating func run() throws {
    var outLog = FileLogger()

    print("I am printed to file", to: &outLog)
    outLog.close()
    let (inputData, inputPath) = try loadInput()
    let now = Date()
    let cliSeed = try parseAttributeOptions(attributeAssignments)

    if plain {
      guard let input = String(data: inputData, encoding: .utf8) else {
        throw ValidationError("Could not read input.")
      }

      var seed = AttributeSeed()
      seed.merge(standardAttributeSeed(for: inputPath, now: now))
      seed.merge(cliSeed)

      let parser = AdocParser()
      let ism = parser.parse(
        text: input,
        attributes: seed.values,
        lockedAttributeNames: seed.locked,
        includeHeaderDerivedAttributes: false
      )
      let asg = ism.toASG()
      try writeJSON(asg)
      return
    }

    let decoder = JSONDecoder()
    let adapterIn: AdapterInput
    do {
      adapterIn = try decoder.decode(AdapterInput.self, from: inputData)
    } catch {
      throw ValidationError("Invalid AdapterInput JSON: \(error.localizedDescription)")
    }

    var seed = AttributeSeed()
    seed.merge(standardAttributeSeed(for: adapterIn.path, now: now))
    seed.merge(seedFromAdapterAttributes(adapterIn.attributes))
    seed.merge(cliSeed)

    switch adapterIn.type {
    case .inline:
      let span = inlineSpan(for: adapterIn.contents)
      let inlines = parseInlines(adapterIn.contents, baseSpan: span)
      let asg = inlines.toASGInlines()
      try writeJSON(asg)

    case .block, .document:
      let parser = AdocParser()
      let ism = parser.parse(
        text: adapterIn.contents,
        attributes: seed.values,
        lockedAttributeNames: seed.locked,
        includeHeaderDerivedAttributes: false
      )
      let asg = ism.toASG()
      try writeJSON(asg)
    }
  }

  private func loadInput() throws -> (Data, String?) {
    if stdin {
      return (FileHandle.standardInput.readDataToEndOfFile(), nil)
    }
    guard let path = CommandLine.arguments.last, FileManager.default.fileExists(atPath: path) else {
      throw ValidationError("Provide --stdin or a path to an AdapterInput JSON file.")
    }
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    return (data, path)
  }

  private func writeJSON<T: Encodable>(_ value: T) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
    let outData = try encoder.encode(value)
    FileHandle.standardOutput.write(outData)
    FileHandle.standardOutput.write(Data([0x0A]))
  }

  private func inlineSpan(for text: String) -> AdocRange {
    let startPos = AdocPos(offset: text.startIndex, line: 1, column: 1)
    if text.isEmpty {
      return AdocRange(start: startPos, end: startPos)
    }
    let lastIndex = text.index(before: text.endIndex)
    let endPos = AdocPos(offset: lastIndex, line: 1, column: text.count)
    return AdocRange(start: startPos, end: endPos)
  }
}

struct HTML: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "html",
        abstract: "Render AsciiDoc to HTML."
    )

    @Flag(help: "Read source from stdin. Otherwise provide a path argument.")
    var stdin: Bool = false

    @Option(help: "Path to the Stencil templates root directory.")
    var template: String = "Templates"

    @Option(
        name: [.customShort("a"), .customLong("attribute")],
        parsing: .unconditionalSingleValue,
        help: "Set document attribute (name[=value]). Repeatable."
    )
    var attributeAssignments: [String] = []

    @Option(name: .shortAndLong, help: "Write rendered output to this path.")
    var output: String?

    @Argument(help: "Path to the .adoc document (omit when using --stdin).")
    var inputPath: String?

    @Option(
        name: [.customShort("e"), .customLong("extension")],
        parsing: .upToNextOption,
        help: "Enable an extension by name (repeatable)."
    )
    var extensions: [String] = []

    mutating func run() async throws {
        try renderDocument(
            backend: .html5,
            defaultExtension: "html",
            stdin: stdin,
            inputPath: inputPath,
            templateRoot: template,
            attributeAssignments: attributeAssignments,
            outputPath: output,
            enabledExtensions: extensions
        )
    }
}

struct DocBook: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "docbook",
        abstract: "Render AsciiDoc to DocBook 5 XML."
    )

    @Flag(help: "Read source from stdin. Otherwise provide a path argument.")
    var stdin: Bool = false

    @Option(help: "Path to the Stencil templates root directory.")
    var template: String = "Templates"

    @Option(
        name: [.customShort("a"), .customLong("attribute")],
        parsing: .unconditionalSingleValue,
        help: "Set document attribute (name[=value]). Repeatable."
    )
    var attributeAssignments: [String] = []

    @Option(name: .shortAndLong, help: "Write rendered output to this path.")
    var output: String?

    @Argument(help: "Path to the .adoc document (omit when using --stdin).")
    var inputPath: String?

    @Option(
        name: [.customShort("e"), .customLong("extension")],
        parsing: .upToNextOption,
        help: "Enable an extension by name (repeatable)."
    )
    var extensions: [String] = []

    mutating func run() async throws {
        try renderDocument(
            backend: .docbook5,
            defaultExtension: "xml",
            stdin: stdin,
            inputPath: inputPath,
            templateRoot: template,
            attributeAssignments: attributeAssignments,
            outputPath: output,
            enabledExtensions: extensions
        )
    }
}

struct Latex: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "latex",
        abstract: "Render AsciiDoc to LaTeX."
    )

    @Flag(help: "Read source from stdin. Otherwise provide a path argument.")
    var stdin: Bool = false

    @Option(help: "Path to the Stencil templates root directory.")
    var template: String = "Templates"

    @Option(
        name: [.customShort("a"), .customLong("attribute")],
        parsing: .unconditionalSingleValue,
        help: "Set document attribute (name[=value]). Repeatable."
    )
    var attributeAssignments: [String] = []

    @Option(name: .shortAndLong, help: "Write rendered output to this path.")
    var output: String?

    @Argument(help: "Path to the .adoc document (omit when using --stdin).")
    var inputPath: String?

    @Option(
        name: [.customShort("e"), .customLong("extension")],
        parsing: .upToNextOption,
        help: "Enable an extension by name (repeatable)."
    )
    var extensions: [String] = []

    mutating func run() async throws {
        try renderDocument(
            backend: .latex,
            defaultExtension: "tex",
            stdin: stdin,
            inputPath: inputPath,
            templateRoot: template,
            attributeAssignments: attributeAssignments,
            outputPath: output,
            enabledExtensions: extensions
        )
    }
}

struct Lint: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "lint",
        abstract: "Lint an AsciiDoc document for spelling and semantic line breaks."
    )

    @Flag(help: "Read source from stdin. Otherwise provide a path argument.")
    var stdin: Bool = false

    @Flag(name: .long, help: "Disable spell checking.")
    var noSpellcheck: Bool = false

    @Flag(name: .long, help: "Disable semantic break checks.")
    var noSemanticBreaks: Bool = false

    @Option(name: .long, help: "Language passed to the aspell spellchecker (default: en_US).")
    var spellLang: String = "en_US"

    @Argument(help: "Path to the .adoc document.")
    var inputPath: String?

    mutating func run() throws {
        let (source, path) = try readSource()
        let parser = AdocParser()
        let document = parser.parse(text: source)

        let options = LintOptions(
            enableSpellcheck: !noSpellcheck,
            enableSemanticBreaks: !noSemanticBreaks,
            spellLanguage: spellLang
        )
        let runner = LintRunner(document: document, sourceText: source, options: options)
        let warnings = runner.run()
        if warnings.isEmpty {
            print("No lint warnings.")
            return
        }

        let displayPath = path ?? "<stdin>"
        for warning in warnings {
            print("\(displayPath):\(warning.line):\(warning.column): warning: [\(warning.kind.rawValue)] \(warning.message)")
        }
        throw ExitCode(1)
    }

    private func readSource() throws -> (String, String?) {
        if stdin {
            let data = FileHandle.standardInput.readDataToEndOfFile()
            guard let text = String(data: data, encoding: .utf8) else {
                throw ValidationError("Source must be UTF-8.")
            }
            return (text, nil)
        }
        guard let path = inputPath else {
            throw ValidationError("Provide --stdin or a path to an .adoc file.")
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        guard let text = String(data: data, encoding: .utf8) else {
            throw ValidationError("Source must be UTF-8.")
        }
        return (text, path)
    }
}
struct Spellcheck: ParsableCommand { /* stream text → tool */ }
struct Filter: ParsableCommand { /* run scripts before/after parse */ }

// Rendering helpers
extension PlantUMLExtension.Format: ExpressibleByArgument {}

private func renderDocument(
    backend: Backend,
    defaultExtension: String,
    stdin: Bool,
    inputPath: String?,
    templateRoot: String,
    attributeAssignments: [String],
    outputPath: String?,
    enabledExtensions: [String]
) throws {
    let (source, sourcePath) = try readRenderSource(stdin: stdin, inputPath: inputPath)
    let documentDirectory = sourcePath.map { URL(fileURLWithPath: $0).deletingLastPathComponent() }
    var extensionHost = ExtensionHost()

    let now = Date()
    var seed = AttributeSeed()
    seed.merge(standardAttributeSeed(for: sourcePath, now: now))
    seed.merge(try parseAttributeOptions(attributeAssignments))

    let baseAttributes = seed.values.compactMapValues { $0 }

    registerExtensions(
        extensionHost: &extensionHost,
        attributes: baseAttributes,
        documentDirectory: documentDirectory,
        enabledExtensions: enabledExtensions
    )

    let (preprocessedSource, updatedAttributes) = extensionHost.runWillParse(
        source: source,
        attributes: baseAttributes
    )

    let parser = AdocParser()
    let preprocessorOptions = Preprocessor.Options(
        sourceURL: sourcePath.map { URL(fileURLWithPath: $0) }
    )
    var parserAttributes = seed.values
    for (key, value) in updatedAttributes {
        parserAttributes[key] = value
    }
    var doc = parser.parse(
        text: preprocessedSource,
        attributes: parserAttributes,
        lockedAttributeNames: seed.locked,
        preprocessorOptions: preprocessorOptions
    )

    doc = extensionHost.runDidParse(document: doc)

    let engine = StencilTemplateEngine(templateRoot: templateRoot)
    let renderer = DocumentRenderer(
        engine: engine,
        config: RenderConfig(backend: backend)
    )
    let rendered = try renderer.render(document: doc)
    try writeRenderedOutput(rendered, explicitPath: outputPath, sourcePath: sourcePath, defaultExtension: defaultExtension)
}

private func readRenderSource(stdin: Bool, inputPath: String?) throws -> (String, String?) {
    if stdin {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else {
            throw ValidationError("Source must be UTF-8.")
        }
        return (text, nil)
    }
    guard let path = inputPath else {
        throw ValidationError("Provide --stdin or a path to an .adoc file.")
    }
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    guard let text = String(data: data, encoding: .utf8) else {
        throw ValidationError("Source must be UTF-8.")
    }
    return (text, path)
}

private func writeRenderedOutput(_ contents: String, explicitPath: String?, sourcePath: String?, defaultExtension: String) throws {
    if let outputPath = explicitPath {
        try contents.write(to: URL(fileURLWithPath: outputPath), atomically: true, encoding: .utf8)
        FileHandle.standardError.write(Data("Wrote \(outputPath)\n".utf8))
        return
    }

    if let sourcePath {
        var url = URL(fileURLWithPath: sourcePath)
        url.deletePathExtension()
        url.appendPathExtension(defaultExtension)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        FileHandle.standardError.write(Data("Wrote \(url.path)\n".utf8))
        return
    }

    FileHandle.standardOutput.write(Data(contents.utf8))
    FileHandle.standardOutput.write(Data([0x0A]))
}

private func registerExtensions(
    extensionHost: inout ExtensionHost,
    attributes: [String: String],
    documentDirectory: URL?,
    enabledExtensions: [String]
) {
    if let plantumlExtension = makePlantumlExtension(
        attributes: attributes,
        documentDirectory: documentDirectory,
        enabledExtensions: enabledExtensions
    ) {
        extensionHost.register(plantumlExtension)
    }

    if let latexExtension = makeLatexExtension(enabledExtensions: enabledExtensions) {
        extensionHost.register(latexExtension)
    }
}

private func makePlantumlExtension(
    attributes: [String: String],
    documentDirectory: URL?,
    enabledExtensions: [String]
) -> PlantUMLExtension? {
    guard extensionRequested("plantuml", in: enabledExtensions) else {
        return nil
    }
    let executable = attributes["plantuml-executable"] ?? "plantuml"
    let formatAttr = attributes["plantuml-format"]?.lowercased()
    let format = PlantUMLExtension.Format(rawValue: formatAttr ?? "") ?? .png
    let directoryAttr = attributes["plantuml-output-dir"] ?? attributes["plantuml-dir"] ?? "diagrams"
    let outputDirectory = resolveDiagramDirectory(directoryAttr, documentDirectory: documentDirectory)

    return PlantUMLExtension(
        documentDirectory: documentDirectory,
        outputDirectory: outputDirectory,
        executable: executable,
        defaultFormat: format
    )
}

private func resolveDiagramDirectory(_ path: String, documentDirectory: URL?) -> URL {
    let url = URL(fileURLWithPath: path, relativeTo: documentDirectory ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
    return url.standardizedFileURL
}

private func extensionRequested(_ name: String, in enabledExtensions: [String]) -> Bool {
    enabledExtensions.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
}

private func makeLatexExtension(enabledExtensions: [String]) -> LatexEnvironmentExtension? {
    guard extensionRequested("latex", in: enabledExtensions) else {
        return nil
    }
    return LatexEnvironmentExtension()
}
