//
// Copyright (c) 2025 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//


package extension AdocBlockMacro {
    mutating func apply(meta m: AdocBlockMeta) {
        if let id = m.id { self.id = self.id ?? id }
        if let t  = m.title { self.title = self.title ?? t }

        self.meta.mergeNonStructural(from: m)
    }
}
