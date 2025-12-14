//
// Copyright (c) 2025 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

public struct AdocBlockMacro: Sendable, Equatable {
    public var name: String // "include", "image", etc
    public var target: String?
    public var id: String?
    public var title: AdocText?
    public var reftext: AdocText?
    public var meta: AdocBlockMeta = .init()
    public var span: AdocRange?

    public init(
        name: String,
        target: String? = nil,
        id: String? = nil,
        title: AdocText? = nil,
        reftext: AdocText? = nil,
        meta: AdocBlockMeta = AdocBlockMeta(),
        span: AdocRange? = nil) {
        self.name = name
        self.target = target
        self.id = id
        self.title = title
        self.reftext = reftext
        self.meta = meta
        self.span = span
    }
}
