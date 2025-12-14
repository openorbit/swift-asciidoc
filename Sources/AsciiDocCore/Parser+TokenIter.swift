//
// Copyright (c) 2025 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

package struct TokenIter {
    let tokens: [Token]
    let text: String
    var index: Int = 0

    init(tokens: [Token], text: String) {
        self.tokens = tokens
        self.text = text
    }

    func peek() -> Token? {
        return index < tokens.count ? tokens[index] : nil
    }

    mutating func consume() {
        index += 1
    }

    mutating func next() -> Token? {
        guard index < tokens.count else { return nil }
        let t = tokens[index]
        index += 1
        return t
    }

    // Trim horizontal spaces (space / tab) from left+right of the token's line content.
    // Result is expressed as a range inside tok.string.
    func contentRange(of tok: Token) -> Range<String.Index> {
        let s = tok.string
        var i = s.startIndex
        var j = s.endIndex

        while i < j, s[i] == " " || s[i] == "\t" {
            i = s.index(after: i)
        }
        while j > i {
            let before = s.index(before: j)
            if s[before] == " " || s[before] == "\t" {
                j = before
            } else {
                break
            }
        }
        return i..<j
    }

    func contentText(of tok: Token) -> String {
        let r = contentRange(of: tok)
        return String(tok.string[r])
    }

    // Raw line = full token string (no trimming, no terminator in the new scanner model)
    func rawLineRange(of tok: Token) -> Range<String.Index> {
        tok.string.startIndex..<tok.string.endIndex
    }

    func rawLineText(of tok: Token) -> String {
        String(tok.string)
    }

    // In the old model "relative" meant negative Int ranges; now it simply means
    // "a range inside tok.string". We trust the scanner to give a valid range.
    func textFromRelative(range rel: Range<String.Index>, token tok: Token) -> String {
        let s = tok.string
        guard rel.lowerBound >= s.startIndex, rel.upperBound <= s.endIndex else {
            return ""
        }
        return String(s[rel])
    }

    /// Span for the entire physical line of this token.
    ///
    /// - Uses `tok.string` (a Substring into `text`) to compute offsets.
    /// - Offsets are UTF-8 byte offsets in the full `text`.
    /// - Columns are 1-based, inclusive.
    func spanForLine(_ tok: Token) -> AdocRange {
        let lineSlice = tok.string
        let lineStartIndex = lineSlice.startIndex
        let lineEndIndex   = lineSlice.endIndex
        let fileStack = tok.range.start.fileStack

        // Columns: start at 1; end at last character on the line (if any)
        let startPos = AdocPos(offset: lineStartIndex, line: tok.line, column: 1, fileStack: fileStack)

        let endCol: Int = {
            if lineStartIndex == lineEndIndex {
                // empty line: column 1 for both start and end
                return 1
            } else {
                let lastCharIndex = text.index(before: lineEndIndex)
                return text.utf16.distance(from: lineStartIndex, to: lastCharIndex) + 1
            }
        }()

        let endPos = AdocPos(offset: lineEndIndex, line: tok.line, column: endCol, fileStack: fileStack)
        return AdocRange(start: startPos, end: endPos)
    }

    /// Span for a *slice* of the token's line (`rel` is inside `tok.string`).
    /// Used for things like section titles and list principals.
    func spanForContent(range rel: Range<String.Index>, token tok: Token) -> AdocRange? {
        let s = tok.string
        guard !s.isEmpty else { return nil }
        guard rel.lowerBound >= s.startIndex, rel.upperBound <= s.endIndex else { return nil }

        let lineStart = s.startIndex

        // Columns relative to start of this line (1-based, inclusive)
        let startCol = text.distance(from: lineStart, to: rel.lowerBound) + 1

        let lastCharIndex = (rel.upperBound > rel.lowerBound)
            ? text.index(before: rel.upperBound)
            : rel.lowerBound
        let endCol = text.utf16.distance(from: lineStart, to: lastCharIndex) + 1

        let fileStack = tok.range.start.fileStack
        let sPos = AdocPos(offset: rel.lowerBound, line: tok.line, column: startCol, fileStack: fileStack)
        let ePos = AdocPos(offset: rel.upperBound, line: tok.line, column: endCol, fileStack: fileStack)
        return AdocRange(start: sPos, end: ePos)
    }
}
