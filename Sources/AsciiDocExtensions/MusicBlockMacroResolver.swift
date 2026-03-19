//
// Copyright (c) 2025 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

import Foundation
import AsciiDocCore

public struct MusicBlockMacroResolver: BlockMacroResolver {
    private struct ChordVoicing: Sendable {
        let frets: String
        let fingers: String?
        let position: String?
        let barre: String?
        let tuning: String
        let strings: String
        let label: String?
    }

    private typealias ChordLibrary = [String: [String: [String: ChordVoicing]]]

    private static let chordLibrary: ChordLibrary = [
        "guitar": [
            "standard": [
                "c": ChordVoicing(frets: "x 3 2 0 1 0", fingers: "x 3 2 0 1 0", position: nil, barre: nil, tuning: "E A D G B E", strings: "6", label: nil),
                "d": ChordVoicing(frets: "x x 0 2 3 2", fingers: "x x 0 1 3 2", position: nil, barre: nil, tuning: "E A D G B E", strings: "6", label: nil),
                "dm": ChordVoicing(frets: "x x 0 2 3 1", fingers: "x x 0 2 3 1", position: nil, barre: nil, tuning: "E A D G B E", strings: "6", label: nil),
                "e": ChordVoicing(frets: "0 2 2 1 0 0", fingers: "0 2 3 1 0 0", position: nil, barre: nil, tuning: "E A D G B E", strings: "6", label: nil),
                "em": ChordVoicing(frets: "0 2 2 0 0 0", fingers: "0 2 3 0 0 0", position: nil, barre: nil, tuning: "E A D G B E", strings: "6", label: nil),
                "f": ChordVoicing(frets: "1 3 3 2 1 1", fingers: "1 3 4 2 1 1", position: "1", barre: "1 6 1 1", tuning: "E A D G B E", strings: "6", label: nil),
                "g": ChordVoicing(frets: "3 2 0 0 0 3", fingers: "2 1 0 0 0 3", position: nil, barre: nil, tuning: "E A D G B E", strings: "6", label: nil),
                "a": ChordVoicing(frets: "x 0 2 2 2 0", fingers: "x 0 1 2 3 0", position: nil, barre: nil, tuning: "E A D G B E", strings: "6", label: nil),
                "am": ChordVoicing(frets: "x 0 2 2 1 0", fingers: "x 0 2 3 1 0", position: nil, barre: nil, tuning: "E A D G B E", strings: "6", label: nil),
                "cm": ChordVoicing(frets: "x 3 5 5 4 3", fingers: "x 1 3 4 2 1", position: "3", barre: "3 5 1 1", tuning: "E A D G B E", strings: "6", label: nil),
            ],
            "drop-d": [
                "d": ChordVoicing(frets: "0 0 0 2 3 2", fingers: "0 0 0 1 3 2", position: nil, barre: nil, tuning: "D A D G B E", strings: "6", label: nil),
                "d5": ChordVoicing(frets: "0 0 0 x x x", fingers: "0 0 0 x x x", position: nil, barre: nil, tuning: "D A D G B E", strings: "6", label: nil),
                "g": ChordVoicing(frets: "5 5 5 4 3 3", fingers: "3 4 4 2 1 1", position: "3", barre: "3 2 1 1", tuning: "D A D G B E", strings: "6", label: nil),
                "a": ChordVoicing(frets: "7 7 7 6 5 5", fingers: "3 4 4 2 1 1", position: "5", barre: "5 2 1 1", tuning: "D A D G B E", strings: "6", label: nil),
            ],
            "dadgad": [
                "d": ChordVoicing(frets: "0 0 0 2 3 0", fingers: "0 0 0 1 2 0", position: nil, barre: nil, tuning: "D A D G A D", strings: "6", label: nil),
                "dsus4": ChordVoicing(frets: "0 0 0 2 3 3", fingers: "0 0 0 1 2 3", position: nil, barre: nil, tuning: "D A D G A D", strings: "6", label: nil),
                "g": ChordVoicing(frets: "5 5 0 0 0 5", fingers: "2 3 0 0 0 4", position: nil, barre: nil, tuning: "D A D G A D", strings: "6", label: nil),
                "em7": ChordVoicing(frets: "2 2 0 0 0 2", fingers: "1 2 0 0 0 3", position: nil, barre: nil, tuning: "D A D G A D", strings: "6", label: nil),
            ],
        ],
    ]

    public init() {}

    public func resolve(blockMacro: AdocBlockMacro, attributes: [String : String]) -> [String : Any]? {
        guard blockMacro.name == "chord" else {
            return nil
        }
        return [
            "attributes": resolveChordAttributes(target: blockMacro.target ?? "", attributes: attributes)
        ]
    }

    private func resolveChordAttributes(target: String, attributes: [String: String]) -> [String: String] {
        let instrumentKey = normalizedChordInstrument(attributes["instrument"])
        let tuningKey = normalizedChordTuning(attributes["tuning"], instrument: instrumentKey)
        let lookupKey = normalizedChordName(target)

        var resolved: [String: String] = [:]

        if let voicing = Self.chordLibrary[instrumentKey]?[tuningKey]?[lookupKey] {
            resolved["instrument"] = instrumentKey
            resolved["tuning"] = voicing.tuning
            resolved["strings"] = voicing.strings
            resolved["frets"] = voicing.frets
            if let fingers = voicing.fingers { resolved["fingers"] = fingers }
            if let position = voicing.position { resolved["position"] = position }
            if let barre = voicing.barre { resolved["barre"] = barre }
            if let label = voicing.label { resolved["label"] = label }
        } else {
            resolved["instrument"] = instrumentKey
            resolved["tuning"] = chordTuningString(for: tuningKey, instrument: instrumentKey)
            if resolved["tuning"] == nil, let rawTuning = attributes["tuning"]?.trimmingCharacters(in: .whitespacesAndNewlines), !rawTuning.isEmpty {
                resolved["tuning"] = rawTuning
            }
        }

        for (key, value) in attributes {
            resolved[key] = value
        }

        resolved["instrument"] = normalizedChordInstrument(resolved["instrument"])
        if let tuning = resolved["tuning"] {
            let normalized = normalizedChordTuning(tuning, instrument: instrumentKey)
            resolved["tuning"] = chordTuningString(for: normalized, instrument: instrumentKey) ?? tuning
        }

        return resolved
    }

    private func normalizedChordInstrument(_ value: String?) -> String {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case nil, "":
            return "guitar"
        default:
            return normalized!
        }
    }

    private func normalizedChordTuning(_ value: String?, instrument: String) -> String {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if normalized.isEmpty {
            return "standard"
        }

        switch instrument {
        case "guitar":
            switch normalized.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "_", with: "-") {
            case "standard", "eadgbe":
                return "standard"
            case "drop-d", "dropd", "dadgbe":
                return "drop-d"
            case "dadgad":
                return "dadgad"
            default:
                return normalized
            }
        default:
            return normalized
        }
    }

    private func chordTuningString(for tuning: String, instrument: String) -> String? {
        switch (instrument, tuning) {
        case ("guitar", "standard"):
            return "E A D G B E"
        case ("guitar", "drop-d"):
            return "D A D G B E"
        case ("guitar", "dadgad"):
            return "D A D G A D"
        default:
            return nil
        }
    }

    private func normalizedChordName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
