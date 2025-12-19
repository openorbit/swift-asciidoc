//
// Copyright (c) 2025 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

import Foundation

public struct IncludeResult: Sendable {
    public var content: String
    public var directory: URL?
    public var filePath: String?
    
    public init(content: String, directory: URL?, filePath: String?) {
        self.content = content
        self.directory = directory
        self.filePath = filePath
    }
}

public protocol IncludeResolver: Sendable {
    func resolve(target: String, from source: URL?) -> IncludeResult?
}
