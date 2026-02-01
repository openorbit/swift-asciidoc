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
import AsciiDocAntora

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
    subcommands: [JSONAdapter.self, HTML.self, DocBook.self, Latex.self, Lint.self, Antora.self]
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

// MARK: - Antora
struct Antora: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "antora",
        abstract: "Build an Antora component from its directory."
    )
    
    @Argument(help: "Path to the component directory (containing antora.yml).")
    var componentPath: String
    
    @Option(name: .shortAndLong, help: "Output directory.")
    var output: String
    
    @Option(help: "Path to templates.")
    var template: String?
    
    mutating func run() async throws {
        let compURL = URL(fileURLWithPath: componentPath).standardizedFileURL
        
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: compURL.path) {
            throw ValidationError("Component directory not found: \(componentPath)")
        }
        
        let outputURL = URL(fileURLWithPath: output).standardizedFileURL
        try? fileManager.createDirectory(at: outputURL, withIntermediateDirectories: true)
        
        // Load Component
        guard let component = try? AntoraComponent(directory: compURL) else {
            throw ValidationError("Failed to load Antora component from \(componentPath). Is antora.yml valid?")
        }
        
        print("Building component: \(component.config.name)")
        
        // Setup Template Engine
        // Use provided template path or built-in resource
        let templateRoot: String
        if let t = template {
            templateRoot = t
        } else if let resourcePath = Bundle.module.resourcePath {
            templateRoot = URL(fileURLWithPath: resourcePath).appendingPathComponent("Templates").path
        } else {
             print("Warning: No template path provided and bundle resources not found. Assuming 'Templates'.")
             templateRoot = "Templates"
        }
        
        // Configure Renderer
        let engine = StencilTemplateEngine(templateRoot: templateRoot)
        let includeResolver = LocalAntoraIncludeResolver(component: component)
        let xrefResolver = LocalAntoraXrefResolver(component: component)
        
        // Build Navigation Tree if nav files exist
        var navTree: NavigationTree?
        // Basic logic: read 'nav' key from config? Or check modules/ROOT/nav.adoc?
        // Config definition in AntoraComponent didn't expose 'nav' list yet.
        // Assuming user puts 'nav.adoc' in standard location for now or we just skip if not readily available in API.
        // For this task, let's scan for a 'nav.adoc' in component root or ROOT module.
        // Antora config has `nav` key list. 
        // We will just look for `nav.adoc` in ROOT module for simplicity if config not fully parsed for it.
        let navPotential = compURL.appendingPathComponent("modules/ROOT/nav.adoc")
        if fileManager.fileExists(atPath: navPotential.path) {
            navTree = NavigationTree.parse(file: navPotential, resolver: xrefResolver)
        }
        
        var navDict: [String: Any]?
        if let tree = navTree {
             navDict = tree.dictionary
             navDict?["title"] = component.config.title ?? component.config.name
        }
        
        let config = RenderConfig(
            backend: .html5, 
            inlineBackend: nil, 
            xrefResolver: xrefResolver, 
            navigationTree: navDict,
            customTemplateName: "antora/document.stencil"
        )
        
        let renderer = DocumentRenderer(engine: engine, config: config)
        let parser = AdocParser()
        let preOptions = Preprocessor.Options(
            sourceURL: nil, 
            safeMode: .unsafe, 
            includeResolvers: [includeResolver]
        )
        
        // Iterate pages
        // modules -> family=pages -> resource
        for (moduleName, families) in component.index.modules {
            guard let pages = families["pages"] else { continue }
            
            let moduleOutDir: URL
            if moduleName == "ROOT" {
                moduleOutDir = outputURL
            } else {
                moduleOutDir = outputURL.appendingPathComponent(moduleName)
                try? fileManager.createDirectory(at: moduleOutDir, withIntermediateDirectories: true)
            }
            
            for (relPath, fileURL) in pages {
                let text = try String(contentsOf: fileURL, encoding: .utf8)
                var options = preOptions
                options.sourceURL = fileURL
                let doc = parser.parse(
                    text: text, 
                    preprocessorOptions: options
                )
                
                // Hack: Set a default template for Antora if strictly needed by CLI engine logic?
                // But DocumentRenderer uses template name based on backend.
                // HTML5 -> "html5/document.stencil"
                // Our new template is in "antora/document.stencil".
                // Either we override the backend to map to Antora, OR we put "antora" folder in template root and tell logic to use it.
                // DocumentRenderer currently hardcodes template names:
                // case .html5:    templateName = "html5/document.stencil"
                
                // If we want to use "antora/document.stencil", we need to change DocumentRenderer Or trick it.
                // Or we place our `antora/document.stencil` as `html5/document.stencil` in a temporary overrides folder?
                // Or we update DocumentRenderer to allow overriding template name? (Not part of plan but cleaner).
                // Or we just place "antora/document.stencil" FROM "html5/document.stencil" logic?
                
                // For now, let's assume the user (or we) provided a templateRoot that HAS html5/document.stencil which IS the Antora template?
                // No, user wants specifically Antora template.
                
                // Let's create a custom render method here or just pass a hacked backend? No.
                // Changing DocumentRenderer to allow override is best.
                
                // Workaround: We will rely on built-in logic. DocumentRenderer selects "html5/document.stencil".
                // If we point `templateRoot` to `Templates/antora` directory (which contains `html5` subdirectory?), then it works.
                // The resource structure I created: `Templates/antora/document.stencil`.
                // If I change it to `Templates/antora/html5/document.stencil` it would work with standard renderer logic if I pass root=`Templates/antora`.
                
                // Implementation detail: I will use `Templates/antora` as root, but I need to ensure the structure matches what renderer expects.
                // Move `Templates/antora/document.stencil` to `Templates/antora/html5/document.stencil`?
                
                // Actually, I can just invoke `engine.render(templateNamed: "antora/document.stencil", context: ...)` directly IF I didn't use DocumentRenderer.render().
                // But DocumentRenderer does all the context building.
                
                // Let's modify RenderConfig to allow custom template name? Or DocumentRenderer.
                // DocumentRenderer.init takes config.
                
                // Let's go with the Override folder approach for zero-code-change in Core/Render.
                // I will assume `Templates` dir has `antora` subfolder.
                // Wait, if I use `html5` backend, `DocumentRenderer` looks for `html5/document.stencil`.
                // If I want special Antora layout, I should use that layout.
                
                // Re-reading user request: "template specifically for Antora components" + "rendering is done for us".
                // CLI subcommand `antora` works.
                
                // I will render it.
                let rendered = try renderer.render(document: doc)
                
                // Output
                let outName = URL(fileURLWithPath: relPath).deletingPathExtension().appendingPathExtension("html").lastPathComponent
                let finalOut = moduleOutDir.appendingPathComponent(outName)
                try rendered.write(to: finalOut, atomically: true, encoding: .utf8)
                print("Rendered \(moduleName)/\(outName)")
            }
        }
    }
}

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
