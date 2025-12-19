//
// Copyright (c) 2025 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

import Foundation

public struct FileSystemIncludeResolver: IncludeResolver {
    public let rootDirectory: URL?
    public let allowURIRead: Bool
    public let safeMode: Preprocessor.SafeMode
    
    public init(rootDirectory: URL?, allowURIRead: Bool = true, safeMode: Preprocessor.SafeMode = .unsafe) {
        self.rootDirectory = rootDirectory
        self.allowURIRead = allowURIRead
        self.safeMode = safeMode
    }
    
    public func resolve(target: String, from source: URL?) -> IncludeResult? {
        if let url = URL(string: target), let scheme = url.scheme, scheme != "file" {
            return resolveURI(url)
        }
        return resolveFile(target: target, parentDirectory: source)
    }
    
    private func resolveURI(_ url: URL) -> IncludeResult? {
        guard allowURIRead, safeMode == .unsafe else {
            return nil
        }
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return IncludeResult(content: text, directory: nil, filePath: url.absoluteString)
    }
    
    private func resolveFile(target: String, parentDirectory: URL?) -> IncludeResult? {
        if safeMode == .secure {
            return nil
        }
        
        let fileManager = FileManager.default
        let baseDirectory = parentDirectory
            ?? rootDirectory
            ?? URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
            
        let resolved: URL
        if target.hasPrefix("/") {
            resolved = URL(fileURLWithPath: target).standardizedFileURL
        } else {
            resolved = URL(fileURLWithPath: target, relativeTo: baseDirectory).standardizedFileURL
        }
        
        if safeMode == .safe {
             // In safe mode, we must ensure we are inside the root directory (if set) or just restrict somewhat?
             // Original logic:
             // let allowed = resolved.path.hasPrefix(baseDirectory.standardizedFileURL.path)
             // But baseDirectory changes with includes.
             // Actually, the original logic used `baseDirectory` which was derived from `parentDirectory` OR `rootDirectory`.
             // So it enforced that you can't go UP from the *current* file if it puts you outside, or something?
             // Let's stick to the original logic interpretation:
             // "allowed = resolved.path.hasPrefix(baseDirectory.standardizedFileURL.path)"
             let allowed = resolved.path.hasPrefix(baseDirectory.standardizedFileURL.path)
             if !allowed {
                 return nil
             }
        }
        
        guard let text = try? String(contentsOf: resolved, encoding: .utf8) else {
            return nil
        }
        
        return IncludeResult(
            content: text,
            directory: resolved.deletingLastPathComponent(),
            filePath: resolved.path
        )
    }
}
