//
// Copyright (c) 2026 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

import AsciiDocCore

public struct XADExtension: AsciiDocExtension {
    public let name: String = "xad"
    private let processor: XADProcessor

    public init(processor: XADProcessor = XADProcessor()) {
        self.processor = processor
    }

    public func willParse(source: String, attributes: [String:String]) -> (String, [String:String]) {
        (source, attributes)
    }

    public func didParse(document: AdocDocument) -> AdocDocument {
        processor.apply(document: document)
    }
}
