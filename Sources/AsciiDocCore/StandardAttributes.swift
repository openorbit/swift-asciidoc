//
// Copyright (c) 2025 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

import Foundation

/// Compute the standard AsciiDoc document attributes that depend on the input source
/// path and timestamps.
public func collectStandardDocumentAttributes(
    sourcePath: String?,
    fileModificationDate: Date? = nil,
    now: Date = Date(),
    calendar inputCalendar: Calendar = Calendar.current
) -> [String: String?] {
    var attrs: [String: String?] = [:]

    if let sourcePath, !sourcePath.isEmpty {
        let url = URL(fileURLWithPath: sourcePath).standardizedFileURL
        let normalizedPath = url.path
        attrs["docfile"] = normalizedPath
        attrs["docpath"] = normalizedPath
        attrs["docdir"] = url.deletingLastPathComponent().path
        let stem = url.deletingPathExtension().lastPathComponent
        attrs["docname"] = stem
        attrs["docstem"] = stem
        let ext = url.pathExtension
        attrs["docfilesuffix"] = ext.isEmpty ? "" : ".\(ext)"
    }

    var calendar = inputCalendar
    // Ensure we always have a time zone to format timestamps.
    if calendar.timeZone == .autoupdatingCurrent {
        calendar.timeZone = TimeZone.current
    }
    let tz = calendar.timeZone

    let docTimestamp = fileModificationDate ?? now
    attrs.merge(
        dateAttributes(prefix: "doc", date: docTimestamp, timeZone: tz),
        uniquingKeysWith: { _, new in new }
    )
    attrs.merge(
        dateAttributes(prefix: "local", date: now, timeZone: tz),
        uniquingKeysWith: { _, new in new }
    )

    return attrs
}

private func dateAttributes(prefix: String, date: Date, timeZone: TimeZone) -> [String: String?] {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = timeZone

    formatter.dateFormat = "yyyy-MM-dd"
    let dateString = formatter.string(from: date)

    formatter.dateFormat = "HH:mm:ss z"
    let timeString = formatter.string(from: date)

    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss z"
    let datetimeString = formatter.string(from: date)

    formatter.dateFormat = "yyyy"
    let yearString = formatter.string(from: date)

    formatter.dateFormat = "MM"
    let monthString = formatter.string(from: date)

    formatter.dateFormat = "dd"
    let dayString = formatter.string(from: date)

    return [
        "\(prefix)date": dateString,
        "\(prefix)time": timeString,
        "\(prefix)datetime": datetimeString,
        "\(prefix)year": yearString,
        "\(prefix)month": monthString,
        "\(prefix)day": dayString
    ]
}
