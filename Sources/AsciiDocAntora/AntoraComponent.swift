//
// Copyright (c) 2025 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

import Foundation
import Yams

public struct AntoraComponent: Sendable {
    public struct Config: Decodable, Sendable {
        public var name: String
        public var version: String?
        public var title: String?
        // Navigation not yet parsed here from config, usually just 'nav' key list
    }
    
    public var config: Config
    public var directory: URL
    
    // Family -> [Module -> [RelativePath -> FileURL]]
    // Or simplified: Just store the structure.
    // Antora structure:
    // modules/<module>/<family>/<resource>
    
    public struct ResourceIndex: Sendable {
        // map: module -> (family -> [resourceName : URL])
        public var modules: [String: [String: [String: URL]]] = [:]
    }
    
    public var index: ResourceIndex
    
    public init(directory: URL) throws {
        self.directory = directory
        
        // Parse antora.yml
        let configFile = directory.appendingPathComponent("antora.yml")
        let configData = try Data(contentsOf: configFile)
        let decoder = YAMLDecoder()
        self.config = try decoder.decode(Config.self, from: configData)
        
        self.index = AntoraComponent.scan(directory: directory)
    }
    
    private static func scan(directory: URL) -> ResourceIndex {
        var index = ResourceIndex()
        let modulesDir = directory.appendingPathComponent("modules")
        
        let fileManager = FileManager.default
        guard let modules = try? fileManager.contentsOfDirectory(at: modulesDir, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return index
        }
        
        for moduleURL in modules {
            let moduleName = moduleURL.lastPathComponent
            var families: [String: [String: URL]] = [:]
            
            // Scan families: pages, partials, images, attachments, examples
            let knownFamilies = ["pages", "partials", "images", "attachments", "examples"]
            
            for family in knownFamilies {
                let familyDir = moduleURL.appendingPathComponent(family)
                if let resources = recursiveScan(dir: familyDir) {
                    families[family] = resources
                }
            }
            
            index.modules[moduleName] = families
        }
        
        return index
    }
    
    private static func recursiveScan(dir: URL) -> [String: URL]? {
        let fileManager = FileManager.default
        var results: [String: URL] = [:]
        
        guard let enumerator = fileManager.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            return nil
        }
        
        for case let fileURL as URL in enumerator {
            guard let isFile = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile, isFile else {
                continue
            }
            
            // Rel path from family dir
            let path = fileURL.path 
            let prefix = dir.path
            if path.hasPrefix(prefix) {
                var rel = String(path.dropFirst(prefix.count))
                if rel.hasPrefix("/") { rel.removeFirst() }
                results[rel] = fileURL
            }
        }
        
        return results.isEmpty ? nil : results
    }
}
