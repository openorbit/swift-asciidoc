//
// Copyright (c) 2025 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

import Foundation

public struct AntoraXrefTarget: Sendable, Equatable {
    public var component: String?
    public var module: String?
    public var version: String?
    public var family: String?
    public var resource: String
    public var fragment: String?

    public init(
        component: String? = nil,
        module: String? = nil,
        version: String? = nil,
        family: String? = nil,
        resource: String,
        fragment: String? = nil
    ) {
        self.component = component?.nonEmpty
        self.module = module?.nonEmpty
        self.version = version?.nonEmpty
        self.family = family?.nonEmpty
        self.resource = resource
        self.fragment = fragment?.nonEmpty
    }

    public static func parse(raw: String) -> AntoraXrefTarget? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var remainder = trimmed
        var fragment: String?

        if let hashIdx = remainder.firstIndex(of: "#") {
            fragment = String(remainder[remainder.index(after: hashIdx)...])
            remainder = String(remainder[..<hashIdx])
        }

        var coordinatePart = remainder
        var family: String?
        var resource: String?

        if let dollar = coordinatePart.firstIndex(of: "$") {
            let after = coordinatePart.index(after: dollar)
            resource = String(coordinatePart[after...])
            let before = String(coordinatePart[..<dollar])
            coordinatePart = before

            if let at = before.lastIndex(of: "@") {
                family = String(before[before.index(after: at)...])
                coordinatePart = String(before[..<at])
            } else if let colon = before.lastIndex(of: ":") {
                family = String(before[before.index(after: colon)...])
                coordinatePart = String(before[..<colon])
            } else if !before.isEmpty {
                family = before
                coordinatePart = ""
            }
        } else if let at = coordinatePart.firstIndex(of: "@") {
            let after = coordinatePart.index(after: at)
            resource = String(coordinatePart[after...])
            coordinatePart = String(coordinatePart[..<at])
        }

        if resource == nil {
            if let colon = coordinatePart.lastIndex(of: ":") {
                let after = coordinatePart.index(after: colon)
                resource = String(coordinatePart[after...])
                coordinatePart = String(coordinatePart[..<colon])
            } else {
                resource = coordinatePart
                coordinatePart = ""
            }
        }

        guard let resolvedResource = resource?.trimmingCharacters(in: .whitespacesAndNewlines),
              !resolvedResource.isEmpty else {
            return nil
        }

        family = family?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty

        let parts = coordinatePart
            .split(separator: ":", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }

        var component: String?
        var module: String?
        var version: String?

        if parts.count == 1, let value = parts.first, !value.isEmpty {
            module = value
        } else if parts.count == 2 {
            component = parts[0].nonEmpty
            module = parts[1].nonEmpty
        } else if parts.count >= 3 {
            component = parts[0].nonEmpty
            module = parts[1].nonEmpty
            let remainderVersion = parts[2...].joined(separator: ":").trimmingCharacters(in: .whitespacesAndNewlines)
            version = remainderVersion.nonEmpty
        }

        return AntoraXrefTarget(
            component: component,
            module: module,
            version: version,
            family: family,
            resource: resolvedResource,
            fragment: fragment?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

public struct AdocXrefTarget: Sendable, Equatable {
    public var raw: String
    public var antora: AntoraXrefTarget?

    public init(raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        self.raw = trimmed
        self.antora = AntoraXrefTarget.parse(raw: trimmed)
    }

    public func rewriting(raw newRaw: String) -> AdocXrefTarget {
        AdocXrefTarget(raw: newRaw)
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
