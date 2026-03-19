//
// Copyright (c) 2026 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

public struct XADOptions: Sendable, Equatable {
    public var enabled: Bool
    public var strict: Bool
    public var pagedJS: Bool
    public var templatePath: String?
    public var layoutTemplate: String?
    public var layoutTemplateBase: String?
    public var layoutTemplateSearchPaths: [String]

    public init(
        enabled: Bool = false,
        strict: Bool = false,
        pagedJS: Bool = false,
        templatePath: String? = nil,
        layoutTemplate: String? = nil,
        layoutTemplateBase: String? = nil,
        layoutTemplateSearchPaths: [String] = []
    ) {
        self.enabled = enabled
        self.strict = strict
        self.pagedJS = pagedJS
        self.templatePath = templatePath
        self.layoutTemplate = layoutTemplate
        self.layoutTemplateBase = layoutTemplateBase
        self.layoutTemplateSearchPaths = layoutTemplateSearchPaths
    }
}
