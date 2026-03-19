//
// Copyright (c) 2025 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

import Foundation

public protocol BlockMacroResolver: Sendable {
    func resolve(blockMacro: AdocBlockMacro, attributes: [String: String]) -> [String: Any]?
}
