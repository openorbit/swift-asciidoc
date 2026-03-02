//
// Copyright (c) 2026 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

import Foundation
import AsciiDocCore

public struct XADTemplateDescriptor: Sendable, Equatable {
    public var name: String
    public var baseURL: URL
    public var layoutURL: URL
    public var program: LayoutProgram

    public init(name: String, baseURL: URL, layoutURL: URL, program: LayoutProgram) {
        self.name = name
        self.baseURL = baseURL
        self.layoutURL = layoutURL
        self.program = program
    }
}

public struct XADTemplateRegistry: Sendable {
    public var searchPaths: [URL]

    public init(searchPaths: [URL] = []) {
        self.searchPaths = searchPaths
    }

    public mutating func addSearchPath(_ url: URL) {
        let normalized = url.standardizedFileURL
        if !searchPaths.contains(where: { $0.standardizedFileURL == normalized }) {
            searchPaths.append(normalized)
        }
    }

    public func listTemplates(fileManager: FileManager = .default) -> [String] {
        var names = Set<String>()
        for root in searchPaths {
            let xadDir = root.appendingPathComponent("xad", isDirectory: true)
            guard let entries = try? fileManager.contentsOfDirectory(
                at: xadDir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for entry in entries {
                guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                    continue
                }
                let layoutURL = entry.appendingPathComponent("layout.xad")
                if fileManager.fileExists(atPath: layoutURL.path) {
                    names.insert(entry.lastPathComponent)
                }
            }
        }
        return names.sorted()
    }

    public func loadTemplate(
        named name: String,
        baseURL: URL? = nil,
        fileManager: FileManager = .default
    ) -> (XADTemplateDescriptor?, [AdocWarning]) {
        var warnings: [AdocWarning] = []
        guard let layoutURL = resolveTemplateLayoutURL(named: name, fileManager: fileManager) else {
            warnings.append(AdocWarning(message: "template not found: \(name)", span: nil))
            return (nil, warnings)
        }
        return loadTemplate(at: layoutURL, templateName: name, baseURL: baseURL, fileManager: fileManager)
    }

    public func loadTemplate(
        at url: URL,
        templateName: String? = nil,
        baseURL: URL? = nil,
        fileManager: FileManager = .default
    ) -> (XADTemplateDescriptor?, [AdocWarning]) {
        var warnings: [AdocWarning] = []
        let layoutURL: URL
        var name = templateName ?? url.deletingPathExtension().lastPathComponent

        if url.hasDirectoryPath {
            layoutURL = url.appendingPathComponent("layout.xad")
            name = url.lastPathComponent
        } else {
            layoutURL = url
        }

        guard fileManager.fileExists(atPath: layoutURL.path) else {
            warnings.append(AdocWarning(message: "layout.xad not found at \(layoutURL.path)", span: nil))
            return (nil, warnings)
        }

        let data: Data
        do {
            data = try Data(contentsOf: layoutURL)
        } catch {
            warnings.append(AdocWarning(message: "failed to read template: \(error.localizedDescription)", span: nil))
            return (nil, warnings)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            warnings.append(AdocWarning(message: "template must be UTF-8", span: nil))
            return (nil, warnings)
        }

        let parser = LayoutDSLParser()
        let (program, parserWarnings) = parser.parse(text: text)
        warnings.append(contentsOf: parserWarnings)

        guard let program else {
            warnings.append(AdocWarning(message: "template did not produce a layout program", span: nil))
            return (nil, warnings)
        }

        let base = baseURL ?? layoutURL.deletingLastPathComponent()
        let template = XADTemplateDescriptor(name: name, baseURL: base, layoutURL: layoutURL, program: program)
        return (template, warnings)
    }

    private func resolveTemplateLayoutURL(named name: String, fileManager: FileManager) -> URL? {
        for root in searchPaths {
            let candidate = root
                .appendingPathComponent("xad", isDirectory: true)
                .appendingPathComponent(name, isDirectory: true)
                .appendingPathComponent("layout.xad")
            if fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }
}
