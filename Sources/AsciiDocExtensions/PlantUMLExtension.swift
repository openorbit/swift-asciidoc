//
// Copyright (c) 2025 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

import Foundation
import AsciiDocCore

public extension AsciiDocExtension {
    func willParse(source: String, attributes: [String: String]) -> (String, [String: String]) {
        (source, attributes)
    }

    func didParse(document: AdocDocument) -> AdocDocument {
        document
    }
}

public struct PlantUMLExtension: AsciiDocExtension {
    public let name = "plantuml"
    public enum Format: String, CaseIterable, Sendable {
        case png
        case svg

        var commandArgument: String { "-t\(rawValue)" }
        var fileExtension: String { rawValue }
    }

    private let documentDirectory: URL?
    private let outputDirectory: URL
    private let executable: String
    private let defaultFormat: Format
    private let fileManager = FileManager()
    private let workingDirectory: URL

    public init(
        documentDirectory: URL?,
        outputDirectory: URL,
        executable: String,
        defaultFormat: Format = .png
    ) {
        self.documentDirectory = documentDirectory?.standardizedFileURL
        self.outputDirectory = outputDirectory.standardizedFileURL
        self.executable = executable
        self.defaultFormat = defaultFormat
        self.workingDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
    }

    public func didParse(document: AdocDocument) -> AdocDocument {
        var copy = document
        copy.blocks = transform(blocks: document.blocks)
        return copy
    }

    private func transform(blocks: [AdocBlock]) -> [AdocBlock] {
        blocks.map(transform(block:))
    }

    private func transform(block: AdocBlock) -> AdocBlock {
        switch block {
        case .section(var section):
            section.blocks = transform(blocks: section.blocks)
            return .section(section)

        case .list(var list):
            list.items = list.items.map { item in
                var copy = item
                copy.blocks = transform(blocks: copy.blocks)
                return copy
            }
            return .list(list)

        case .dlist(var dlist):
            dlist.items = dlist.items.map { item in
                var copy = item
                copy.blocks = transform(blocks: copy.blocks)
                return copy
            }
            return .dlist(dlist)

        case .sidebar(var sidebar):
            sidebar.blocks = transform(blocks: sidebar.blocks)
            return .sidebar(sidebar)

        case .example(var example):
            example.blocks = transform(blocks: example.blocks)
            return .example(example)

        case .quote(var quote):
            quote.blocks = transform(blocks: quote.blocks)
            return .quote(quote)

        case .open(var open):
            open.blocks = transform(blocks: open.blocks)
            return .open(open)

        case .admonition(var admonition):
            admonition.blocks = transform(blocks: admonition.blocks)
            return .admonition(admonition)

        case .verse(var verse):
            verse.blocks = transform(blocks: verse.blocks)
            return .verse(verse)

        case .paragraph(let paragraph):
            if let converted = convertPlantUMLTextBlock(
                text: paragraph.text,
                title: paragraph.title,
                reftext: paragraph.reftext,
                meta: paragraph.meta,
                span: paragraph.span
            ) {
                return converted
            }
            return .paragraph(paragraph)

        case .listing(let listing):
            if let converted = convertPlantUMLTextBlock(
                text: listing.text,
                title: listing.title,
                reftext: listing.reftext,
                meta: listing.meta,
                span: listing.span
            ) {
                return converted
            }
            return .listing(listing)

        case .literalBlock(let literal):
            if let converted = convertPlantUMLTextBlock(
                text: literal.text,
                title: literal.title,
                reftext: literal.reftext,
                meta: literal.meta,
                span: literal.span
            ) {
                return converted
            }
            return .literalBlock(literal)

        case .math, .table, .discreteHeading:
            return block

        case .blockMacro(let macro):
            guard macro.name.lowercased() == "plantuml" else {
                return block
            }
            do {
                let converted = try convertPlantumlMacro(macro)
                return .blockMacro(converted)
            } catch {
                logWarning("PlantUML: \(error)")
                return block
            }
        }
    }

    private func convertPlantumlMacro(_ macro: AdocBlockMacro) throws -> AdocBlockMacro {
        guard let target = macro.target, !target.isEmpty else {
            throw PlantUMLError.missingTarget
        }

        let sourceURL = resolvePath(target)
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw PlantUMLError.missingSource(sourceURL.path)
        }

        let sourceData = try Data(contentsOf: sourceURL)
        guard let sourceText = String(data: sourceData, encoding: .utf8) else {
            throw PlantUMLError.unreadableSource(sourceURL.path)
        }

        let format = formatOverride(in: macro.meta)

        let outputName = inferredDiagramName(from: macro.meta, fallback: sourceURL)
        let destinationURL = outputDirectory.appendingPathComponent("\(outputName).\(format.fileExtension)")

        try renderDiagram(sourceText: sourceText, format: format, destination: destinationURL)

        var imageMacro = macro
        imageMacro.name = "image"
        imageMacro.target = relativeTargetPath(for: destinationURL)
        imageMacro.meta = sanitizeMeta(imageMacro.meta)
        return imageMacro
    }

    private func outputName(for macro: AdocBlockMacro, fallback sourceURL: URL) -> String {
        if let explicit = macro.meta.attributes["target"], !explicit.trimmingCharacters(in: .whitespaces).isEmpty {
            return URL(fileURLWithPath: explicit).deletingPathExtension().lastPathComponent
        }
        let base = sourceURL.deletingPathExtension().lastPathComponent
        guard !base.isEmpty else {
            return "plantuml-\(UUID().uuidString.prefix(8))"
        }
        return base
    }

    private func resolvePath(_ path: String) -> URL {
        let url = URL(fileURLWithPath: path)
        if url.path.hasPrefix("/") {
            return url.standardizedFileURL
        }
        if let docDir = documentDirectory {
            return docDir.appendingPathComponent(path).standardizedFileURL
        }
        return workingDirectory.appendingPathComponent(path).standardizedFileURL
    }

    private func relativeTargetPath(for url: URL) -> String {
        guard let base = documentDirectory else {
            return url.path
        }
        let standardizedBase = base.standardizedFileURL.path
        let standardizedPath = url.standardizedFileURL.path
        if standardizedPath.hasPrefix(standardizedBase) {
            var relative = standardizedPath.dropFirst(standardizedBase.count)
            if relative.hasPrefix("/") { relative = relative.dropFirst() }
            return String(relative)
        }
        return url.path
    }

    private func convertPlantUMLTextBlock(
        text: AdocText,
        title: AdocText?,
        reftext: AdocText?,
        meta: AdocBlockMeta,
        span: AdocRange?
    ) -> AdocBlock? {
        guard isPlantumlStyle(meta) else {
            return nil
        }

        do {
            return try convertInlinePlantUMLSource(
                sourceText: text.plain,
                title: title,
                reftext: reftext,
                meta: meta,
                span: span
            )
        } catch {
            logWarning("PlantUML: \(error)")
            return nil
        }
    }

    private func convertInlinePlantUMLSource(
        sourceText: String,
        title: AdocText?,
        reftext: AdocText?,
        meta: AdocBlockMeta,
        span: AdocRange?
    ) throws -> AdocBlock {
        let format = formatOverride(in: meta)
        let outputName = inferredDiagramName(from: meta, fallback: nil)
        let destinationURL = outputDirectory.appendingPathComponent("\(outputName).\(format.fileExtension)")
        try renderDiagram(sourceText: sourceText, format: format, destination: destinationURL)

        let macro = AdocBlockMacro(
            name: "image",
            target: relativeTargetPath(for: destinationURL),
            id: meta.id,
            title: title,
            reftext: reftext,
            meta: sanitizeMeta(meta),
            span: span
        )
        return .blockMacro(macro)
    }

    private func sanitizeMeta(_ meta: AdocBlockMeta) -> AdocBlockMeta {
        var copy = meta
        copy.attributes.removeValue(forKey: "style")
        copy.attributes.removeValue(forKey: "1")
        return copy
    }

    private func isPlantumlStyle(_ meta: AdocBlockMeta) -> Bool {
        meta.attributes["style"]?.lowercased() == "plantuml"
    }

    private func formatOverride(in meta: AdocBlockMeta) -> Format {
        if let value = meta.attributes["format"]?.lowercased(), let fmt = Format(rawValue: value) {
            return fmt
        }
        if let value = meta.attributes["type"]?.lowercased(), let fmt = Format(rawValue: value) {
            return fmt
        }
        return defaultFormat
    }

    private func inferredDiagramName(from meta: AdocBlockMeta, fallback: URL?) -> String {
        if let explicit = meta.attributes["target"], !explicit.trimmingCharacters(in: .whitespaces).isEmpty {
            return URL(fileURLWithPath: explicit).deletingPathExtension().lastPathComponent
        }
        if let positional = meta.attributes["2"], !positional.trimmingCharacters(in: .whitespaces).isEmpty {
            return URL(fileURLWithPath: positional).deletingPathExtension().lastPathComponent
        }
        if let fallback {
            let base = fallback.deletingPathExtension().lastPathComponent
            if !base.isEmpty { return base }
        }
        if let id = meta.id, !id.isEmpty {
            return id
        }
        return "plantuml-\(UUID().uuidString.prefix(8))"
    }

    private func renderDiagram(sourceText: String, format: Format, destination: URL) throws {
        var arguments = ["-pipe", format.commandArgument]
        let process = Process()

        if executable.contains("/") {
            process.executableURL = URL(fileURLWithPath: executable)
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            arguments.insert(executable, at: 0)
        }

        process.arguments = arguments
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()

        if let data = sourceText.data(using: .utf8) {
            inputPipe.fileHandleForWriting.write(data)
        }
        inputPipe.fileHandleForWriting.closeFile()

        let diagramData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: errorData, encoding: .utf8) ?? "unknown error"
            throw PlantUMLError.renderFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let directory = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        try diagramData.write(to: destination, options: .atomic)
    }

    private func logWarning(_ message: String) {
        guard let data = ("\(message)\n").data(using: .utf8) else { return }
        FileHandle.standardError.write(data)
    }

    enum PlantUMLError: Error, CustomStringConvertible {
        case missingTarget
        case missingSource(String)
        case unreadableSource(String)
        case renderFailed(String)

        public var description: String {
            switch self {
            case .missingTarget:
                return "missing target for plantuml macro"
            case .missingSource(let path):
                return "source file not found: \(path)"
            case .unreadableSource(let path):
                return "unable to read source file: \(path)"
            case .renderFailed(let reason):
                return "plantuml process failed: \(reason)"
            }
        }
    }
}
