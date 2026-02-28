//
// Copyright (c) 2026 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

public struct XADProcessor: Sendable {
    public init() {}

    public func apply(document: AdocDocument) -> AdocDocument {
        // AST-phase expansion will be wired here.
        return document
    }
}
