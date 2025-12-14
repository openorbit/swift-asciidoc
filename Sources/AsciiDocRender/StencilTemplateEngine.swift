//
// Copyright (c) 2025 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

import Foundation
import Stencil
import PathKit

public final class StencilTemplateEngine: TemplateEngine {
    private let environment: Environment

    /// templateRoot: root directory containing html5/, docbook5/, latex/ subdirs.
    public init(templateRoot: String) {
        let loader = FileSystemLoader(paths: [Path(templateRoot)])
        self.environment = Environment(loader: loader)
    }

    public func render(templateNamed name: String, context: [String: Any]) throws -> String {
        // name is something like "html5/document.stencil"
        return try environment.renderTemplate(name: name, context: context)
    }
}

