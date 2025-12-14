//
// Copyright (c) 2025 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

import Foundation
import SwiftHunspell

public protocol Spellchecker: Sendable {
    func isCorrect(_ word: String) -> Bool
}

public final class HunspellSpellchecker: Spellchecker, @unchecked Sendable {
    private let hunspell: Hunspell

    public init?(language: String) {
        guard let (aff, dic) = Self.locateDictionary(for: language) else {
            FileHandle.standardError.write(Data("warning: hunspell dictionary for '\(language)' not found. Install via brew/apt and/or set HUNSPELL_DICT_DIR.\n".utf8))
            return nil
        }

        guard let h = Hunspell(affixPath: aff, dictionaryPath: dic) else {
            FileHandle.standardError.write(Data("warning: hunspell failed to open dictionary '\(language)'.\n".utf8))
            return nil
        }

        self.hunspell = h
    }

    public func isCorrect(_ word: String) -> Bool {
        return hunspell.spell(word)
    }

    private static func locateDictionary(for language: String) -> (String, String)? {
        let fm = FileManager.default
        let codes = candidateCodes(for: language)
        let directories = dictionaryDirectories()

        for dir in directories {
            for code in codes {
                let aff = (dir as NSString).appendingPathComponent("\(code).aff")
                let dic = (dir as NSString).appendingPathComponent("\(code).dic")
                if fm.fileExists(atPath: aff) && fm.fileExists(atPath: dic) {
                    return (aff, dic)
                }
            }
        }
        return nil
    }

    private static func candidateCodes(for language: String) -> [String] {
        let trimmed = language.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ["en_US"] }
        var set = LinkedOrderedSet<String>()
        set.append(trimmed)
        if trimmed.contains("-") {
            set.append(trimmed.replacingOccurrences(of: "-", with: "_"))
            set.append(trimmed.replacingOccurrences(of: "-", with: "").lowercased())
        } else if trimmed.contains("_") {
            set.append(trimmed.replacingOccurrences(of: "_", with: "-"))
        } else {
            set.append("\(trimmed)_\(trimmed.uppercased())")
        }
        set.append(trimmed.lowercased())
        set.append(trimmed.uppercased())
        return set.values
    }

    private static func dictionaryDirectories() -> [String] {
        var dirs: LinkedOrderedSet<String> = .init()
        if let env = ProcessInfo.processInfo.environment["HUNSPELL_DICT_DIR"] {
            env.split(whereSeparator: { $0 == ":" || $0 == ";" }).forEach { raw in
                let path = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !path.isEmpty { dirs.append(path) }
            }
        }
        let defaults = [
            "/usr/share/hunspell",
            "/usr/local/share/hunspell",
            "/opt/homebrew/share/hunspell",
            "/opt/homebrew/opt/hunspell/share/hunspell",
            "/usr/share/myspell",
            "/Library/Spelling"
        ]
        defaults.forEach { dirs.append($0) }
        return dirs.values
    }
}

// Simple ordered set helper for unique-but-ordered collection building
private struct LinkedOrderedSet<Element: Hashable> {
    private var order: [Element] = []
    private var set: Set<Element> = []

    mutating func append(_ element: Element) {
        guard !set.contains(element) else { return }
        set.insert(element)
        order.append(element)
    }

    var values: [Element] { order }
}
