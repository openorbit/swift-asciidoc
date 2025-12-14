//
//  ASGDiff.swift
//  AsciiDoc-Swift
//
//  Created by Mattias Holm on 2025-11-01.
//

import Foundation
import Testing
import AsciiDocCore

/// Compares two ASGDocument values structurally (no JSON), and reports up to `maxDiffs` mismatches.
public func expectASGStructurallyEqual(_ actual: Any, _ expected: Any, maxDiffs: Int = 3, file: StaticString = #file, line: UInt = #line) -> Bool {
    var diffs: [String] = []
    _diff(actual, expected, path: "$", out: &diffs, limit: max(1, maxDiffs))
    if diffs.isEmpty { return true }

    print("ASG structural diff:\n" + diffs.joined(separator: "\n"))
    return false;
}

/// Convenience for ASGDocument specifically.
public func expectASGEqual(_ actual: ASGDocument, _ expected: ASGDocument, maxDiffs: Int = 3, file: StaticString = #file, line: UInt = #line) {
    expectASGStructurallyEqual(actual, expected, maxDiffs: maxDiffs, file: file, line: line)
}

public func expectASGEqual(_ actual: ASGInlines, _ expected: ASGInlines, maxDiffs: Int = 3, file: StaticString = #file, line: UInt = #line) {
    expectASGStructurallyEqual(actual, expected, maxDiffs: maxDiffs, file: file, line: line)
}

private func _diff(_ lhs: Any, _ rhs: Any, path: String, out: inout [String], limit: Int) {
  guard out.count < limit else { return }
  
  // Nil handling for optionals (with special-case: nil ≅ empty for attributes/options/roles)
  let lIsNil = _isNil(lhs)
  let rIsNil = _isNil(rhs)
  if lIsNil || rIsNil {
    if lIsNil != rIsNil {
      // If one side is nil and the other is an empty collection AND the path allows it, treat as equal
      if pathAllowsNilEqualsEmpty(path) {
        let nonNil = _unwrap(lIsNil ? rhs : lhs)
        if isEmptyCollection(nonNil) {
          return
        }
      }
      out.append("\(path): optional mismatch (nil vs non-nil)")
    }
    return
  }
  
  // Unwrap optionals
  let l = _unwrap(lhs)
  let r = _unwrap(rhs)
  
  // If both are Equatable of the same concrete type, fast-path equality
  if _fastEqual(l, r) { return }
  
  // Arrays
  if let la = l as? [Any], let ra = r as? [Any] {
    if la.count != ra.count { out.append("\(path): array length \(la.count) vs \(ra.count)"); return }
    for i in 0..<la.count {
      _diff(la[i], ra[i], path: "\(path)[\(i)]", out: &out, limit: limit)
      if out.count >= limit { return }
    }
    return
  }
  
  // Dictionaries with String keys (common in metadata/attributes)
  if let ld = l as? [String: Any], let rd = r as? [String: Any] {
    let lkeys = Set(ld.keys), rkeys = Set(rd.keys)
    for k in lkeys.subtracting(rkeys) {
      out.append("\(path): extra key '\(k)'"); if out.count >= limit { return }
    }
    for k in rkeys.subtracting(lkeys) {
      out.append("\(path): missing key '\(k)'"); if out.count >= limit { return }
    }
    for k in lkeys.intersection(rkeys).sorted() {
      _diff(ld[k]!, rd[k]!, path: "\(path).\(k)", out: &out, limit: limit)
      if out.count >= limit { return }
    }
    return
  }
  
  // Enums (including those with associated payloads)
  if _isEnum(l) && _isEnum(r) {
    let (lcase, lpayload) = _enumCaseAndPayload(l)
    let (rcase, rpayload) = _enumCaseAndPayload(r)
    if lcase != rcase { out.append("\(path): enum case \(lcase) vs \(rcase)"); return }
    if let lp = lpayload, let rp = rpayload {
      // Payload could be tuple or single
      _diff(lp, rp, path: "\(path).\(lcase)", out: &out, limit: limit)
    }
    return
  }
  
  // Structs / classes: recurse via Mirror fields
  if _isObject(l) && _isObject(r) {
    let lm = Mirror(reflecting: l)
    let rm = Mirror(reflecting: r)
    // Compare fields in order; also fall back to labels when available
    let lChildren = Array(lm.children)
    let rChildren = Array(rm.children)
    if lChildren.count != rChildren.count {
      out.append("\(path): field count \(lChildren.count) vs \(rChildren.count)")
      return
    }
    for (idx, pair) in zip(lChildren.indices, zip(lChildren, rChildren)) {
      let (lc, rc) = pair
      let label = lc.label ?? "#\(idx)"
      _diff(lc.value, rc.value, path: "\(path).\(label)", out: &out, limit: limit)
      if out.count >= limit { return }
    }
    return
  }
  
  // Fallback: plain value mismatch with types
  out.append("\(path): value mismatch \(String(describing: l)) (\(type(of: l))) vs \(String(describing: r)) (\(type(of: r)))")
}

private func _isNil(_ x: Any) -> Bool {
    let mirror = Mirror(reflecting: x)
    return mirror.displayStyle == .optional && mirror.children.count == 0
}

private func _unwrap(_ x: Any) -> Any {
    let mirror = Mirror(reflecting: x)
    if mirror.displayStyle == .optional, let child = mirror.children.first { return child.value }
    return x
}

private func _isEnum(_ x: Any) -> Bool {
    Mirror(reflecting: x).displayStyle == .enum
}
private func _isObject(_ x: Any) -> Bool {
    let s = Mirror(reflecting: x).displayStyle
    return s == .struct || s == .class
}

/// Fast equality for common scalar types to avoid deep walks.
private func _fastEqual(_ a: Any, _ b: Any) -> Bool {
    switch (a, b) {
    case let (l as String, r as String): return l == r
    case let (l as Int,    r as Int):    return l == r
    case let (l as Int8,   r as Int8):   return l == r
    case let (l as Int16,  r as Int16):  return l == r
    case let (l as Int32,  r as Int32):  return l == r
    case let (l as Int64,  r as Int64):  return l == r
    case let (l as UInt,   r as UInt):   return l == r
    case let (l as UInt8,  r as UInt8):  return l == r
    case let (l as UInt16, r as UInt16): return l == r
    case let (l as UInt32, r as UInt32): return l == r
    case let (l as UInt64, r as UInt64): return l == r
    case let (l as Bool,   r as Bool):   return l == r
    case let (l as Double, r as Double): return l == r
    case let (l as Float,  r as Float):  return l == r

    // Common ASG leaf structs that are Equatable — do a dynamic cast and compare.
    case let (l as ASGDocument, r as ASGDocument): return l == r
    case let (l as ASGLocation, r as ASGLocation): return l == r
    case let (l as ASGLocationBoundary, r as ASGLocationBoundary): return l == r
    case let (l as ASGInlineLiteral, r as ASGInlineLiteral): return l == r
    case let (l as ASGInlineSpan, r as ASGInlineSpan): return l == r
    case let (l as ASGInlineRef, r as ASGInlineRef): return l == r
    case let (l as ASGBlockMetadata, r as ASGBlockMetadata): return l == r
    default:
        return false
    }
}

/// Pulls out enum case name and a "payload" that we can diff recursively.
/// For single associated values, payload is that value; for multi, payload is a tuple mirror.
private func _enumCaseAndPayload(_ x: Any) -> (String, Any?) {
    let m = Mirror(reflecting: x)
    guard m.displayStyle == .enum else { return ("<not-enum>", nil) }
    if let child = m.children.first {
        let name = child.label ?? "<associated>"
        return (name, child.value)
    }
    // no associated values
    let caseName = String(describing: x)
    return (caseName, nil)
}

// Add near the top of ASGDiff.swift
private func pathAllowsNilEqualsEmpty(_ path: String) -> Bool {
    path.hasSuffix(".attributes") || path.hasSuffix(".options") || path.hasSuffix(".roles")
}

private func isEmptyCollection(_ value: Any) -> Bool {
    if let a = value as? [Any] { return a.isEmpty }
    if let d = value as? [String: Any] { return d.isEmpty }
    // Handle typed dictionaries/arrays common in ASG:
    if Mirror(reflecting: value).displayStyle == .collection {
        // generic collection length check
        let m = Mirror(reflecting: value)
        return m.children.isEmpty
    }
    if Mirror(reflecting: value).displayStyle == .dictionary {
        let m = Mirror(reflecting: value)
        return m.children.isEmpty
    }
    return false
}
