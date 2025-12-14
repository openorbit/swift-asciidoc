//
// Copyright (c) 2025 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

extension AdocBlockMacro: AdocRenderable {
    public func renderAsAsciiDoc(into out: inout String) {
        // e.g. include::target[]
        // or image::target[attrs]
        let t = target ?? ""
        // TODO: render attributes
        out += "\(name)::\(t)[]\n\n"
    }
}
