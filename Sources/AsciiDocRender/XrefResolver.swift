//
// Copyright (c) 2025 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

import Foundation
import AsciiDocCore

public protocol XrefResolver: Sendable {
    func resolve(target: AdocXrefTarget) -> String?
}
