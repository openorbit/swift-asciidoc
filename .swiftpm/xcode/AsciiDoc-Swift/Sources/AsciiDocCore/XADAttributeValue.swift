//
// Copyright (c) 2026 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

import Foundation

public enum XADAttributeValue: Sendable, Equatable {
    case dictionary([String: XADAttributeValue])
    case array([XADAttributeValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    static func parse(from raw: String, xadOptions: XADOptions) -> XADAttributeValue? {
        guard xadOptions.enabled else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first, first == "{" || first == "[" else { return nil }
        guard let data = trimmed.data(using: .utf8) else { return nil }

        var options: JSONSerialization.ReadingOptions = []
        if #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *) {
            options.insert(.json5Allowed)
        }

        do {
            let obj = try JSONSerialization.jsonObject(with: data, options: options)
            return XADAttributeValue.fromJSON(obj)
        } catch {
            return nil
        }
    }

    static func fromJSON(_ value: Any) -> XADAttributeValue? {
        switch value {
        case let dict as [String: Any]:
            var mapped: [String: XADAttributeValue] = [:]
            for (key, val) in dict {
                if let converted = fromJSON(val) {
                    mapped[key] = converted
                } else {
                    return nil
                }
            }
            return .dictionary(mapped)
        case let array as [Any]:
            var mapped: [XADAttributeValue] = []
            mapped.reserveCapacity(array.count)
            for val in array {
                guard let converted = fromJSON(val) else { return nil }
                mapped.append(converted)
            }
            return .array(mapped)
        case let str as String:
            return .string(str)
        case let num as NSNumber:
            if CFGetTypeID(num) == CFBooleanGetTypeID() {
                return .bool(num.boolValue)
            }
            return .number(num.doubleValue)
        case _ as NSNull:
            return .null
        default:
            return nil
        }
    }

    func toJSONCompatible() -> Any {
        switch self {
        case .dictionary(let dict):
            var out: [String: Any] = [:]
            for (key, value) in dict {
                out[key] = value.toJSONCompatible()
            }
            return out
        case .array(let array):
            return array.map { $0.toJSONCompatible() }
        case .string(let value):
            return value
        case .number(let value):
            return value
        case .bool(let value):
            return value
        case .null:
            return NSNull()
        }
    }
}
