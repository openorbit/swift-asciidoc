//
// Copyright (c) 2025 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

import AsciiDocCore

public protocol AsciiDocExtension {
    var name: String { get }
    func willParse(source: String, attributes: [String:String]) -> (String, [String:String])
    func didParse(document: AdocDocument) -> AdocDocument
}

public struct ExtensionHost {
    private var exts: [AsciiDocExtension] = []

    public init() {
        
    }
    public mutating func register(_ e: AsciiDocExtension) { exts.append(e) }

    public func runWillParse(source: String, attributes: [String:String]) -> (String, [String:String]) {
        exts.reduce((source, attributes)) { acc, e in e.willParse(source: acc.0, attributes: acc.1) }
    }
    public func runDidParse(document: AdocDocument) -> AdocDocument {
        exts.reduce(document) { doc, e in e.didParse(document: doc) }
    }
}
