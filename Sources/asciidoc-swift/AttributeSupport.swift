//
// Copyright (c) 2025 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

import Foundation
import ArgumentParser
import AsciiDocCore

struct AttributeSeed {
  var values: [String: String?] = [:]
  var locked: Set<String> = []

  mutating func merge(_ other: AttributeSeed) {
    for (k, v) in other.values {
      values[k] = v
    }
    locked.formUnion(other.locked)
  }
}

func parseAttributeOptions(_ specs: [String]) throws -> AttributeSeed {
  var seed = AttributeSeed()
  for raw in specs {
    guard !raw.isEmpty else {
      throw ValidationError("Attribute must not be empty.")
    }
    if raw.hasSuffix("!") {
      let name = raw.dropLast().trimmingCharacters(in: .whitespacesAndNewlines)
      guard !name.isEmpty else { throw ValidationError("Attribute name missing before '!'.") }
      seed.values[name] = nil
      seed.locked.insert(name)
      continue
    }

    if let eq = raw.firstIndex(of: "=") {
      let name = raw[..<eq].trimmingCharacters(in: .whitespacesAndNewlines)
      guard !name.isEmpty else { throw ValidationError("Attribute name missing before '=' in \(raw).") }
      let valueStart = raw.index(after: eq)
      let rawValue = raw[valueStart...]
      let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
      seed.values[name] = value
      seed.locked.insert(name)
    } else {
      let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !name.isEmpty else {
        throw ValidationError("Attribute name cannot be empty.")
      }
      seed.values[name] = ""
      seed.locked.insert(name)
    }
  }
  return seed
}

func seedFromAdapterAttributes(_ attrs: [String: String?]?) -> AttributeSeed {
  guard let attrs else { return AttributeSeed() }
  var seed = AttributeSeed()
  for (k, v) in attrs {
    seed.values[k] = v
    seed.locked.insert(k)
  }
  return seed
}

func standardAttributeSeed(
  for path: String?,
  now: Date = Date(),
  calendar: Calendar = Calendar.current
) -> AttributeSeed {
  let modDate = path.flatMap(fileModificationDate)
  let values = collectStandardDocumentAttributes(
    sourcePath: path,
    fileModificationDate: modDate,
    now: now,
    calendar: calendar
  )
  return AttributeSeed(values: values, locked: [])
}

private func fileModificationDate(_ path: String) -> Date? {
  let fm = FileManager.default
  guard fm.fileExists(atPath: path) else { return nil }
  let attrs = try? fm.attributesOfItem(atPath: path)
  return attrs?[.modificationDate] as? Date
}
