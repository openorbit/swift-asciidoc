//
// Copyright (c) 2025 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

func combinedSpan(metaSpan: AdocRange?, innerSpan: AdocRange?) -> AdocRange? {
    switch (metaSpan, innerSpan) {
    case (nil, nil):
        return nil
    case (let m?, nil):
        return m
    case (nil, let i?):
        return i
    case (let m?, let i?):
        // earliest start
        let start: AdocPos
        if (m.start.line, m.start.column) <= (i.start.line, i.start.column) {
            start = m.start
        } else {
            start = i.start
        }

        // latest end
        let end: AdocPos
        if (m.end.line, m.end.column) >= (i.end.line, i.end.column) {
            end = m.end
        } else {
            end = i.end
        }

        return AdocRange(start: start, end: end)
    }
}
