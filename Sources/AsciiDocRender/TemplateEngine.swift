//
// Copyright (c) 2025 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

import Foundation

public protocol TemplateEngine {
    func render(templateNamed name: String, context: [String: Any]) throws -> String
}
