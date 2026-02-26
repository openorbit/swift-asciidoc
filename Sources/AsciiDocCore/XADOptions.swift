//
// Copyright (c) 2026 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

public struct XADOptions: Sendable, Equatable {
    public var enabled: Bool
    public var strict: Bool
    public var pagedJS: Bool
    public var templatePath: String?

    public init(
        enabled: Bool = false,
        strict: Bool = false,
        pagedJS: Bool = false,
        templatePath: String? = nil
    ) {
        self.enabled = enabled
        self.strict = strict
        self.pagedJS = pagedJS
        self.templatePath = templatePath
    }
}
