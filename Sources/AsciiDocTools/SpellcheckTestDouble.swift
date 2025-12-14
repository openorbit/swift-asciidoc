//
// Copyright (c) 2025 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

struct SpellcheckTestDouble: Spellchecker {
    var misspelledWords: Set<String>

    func isCorrect(_ word: String) -> Bool {
        !misspelledWords.contains(word.lowercased())
    }
}
