//
// Copyright (c) 2025 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

import Foundation

private struct HeaderAuthorInfo {
    var fullname: String
    var firstname: String?
    var middlename: String?
    var lastname: String?
    var initials: String?
    var email: String?
}

private struct HeaderRevisionInfo {
    var number: String?
    var date: String?
    var remark: String?
}

extension AdocParser {

    func detectHeader(
        into header: inout AdocHeader?,
        attrs docAttrs: inout [String: String?],
        it: inout TokenIter,
        env: inout AttrEnv,
        lockedAttributes: Set<String>,
        includeDerivedAttributes: Bool
    ) {
        // ——— Header parsing (no blank lines allowed within header) ———
        // Header grammar at top of document:
        //   1) Optional title (ATX level-1 line "= Title")
        //   2) Optional author/revision line (single text line)
        //   3) Optional list of attribute entries (:name: value / :name!:) – zero or more
        // The header must start on the first line; if the first line is blank, there is no header.
        if let firstTok = it.peek(), case .blank = firstTok.kind {
            // No header if file starts with a blank line
        } else {
            var headerStartTok: Token? = it.peek()
            var lastHeaderTok: Token? = nil
            var headerSeen = false
            var parsedAuthors: [HeaderAuthorInfo]? = nil
            var revisionInfo: HeaderRevisionInfo? = nil

            // Optional title
            if let tok = it.peek(), case .atxSection(let lvl, let titleRel) = tok.kind, lvl == 0 {
                let titlePlain = it.textFromRelative(range: titleRel, token: tok)
                let titleSpan  = it.spanForContent(range: titleRel, token: tok)
                let lineSpan   = it.spanForLine(tok)
                var titleText = AdocText(plain: titlePlain, span: titleSpan)
                // Apply attributes to the section title inline tree
                titleText = titleText.applyingAttributes(using: env)

                header = AdocHeader(
                    title: titleText,
                    authors: nil,
                    location: rangeToLocation(lineSpan)
                )
                it.consume() // consume title
                headerStartTok = headerStartTok ?? tok
                lastHeaderTok = tok
                headerSeen = true
            }

            // Optional author/revision line (must be immediately next, no blank in between)
            var consumedAuthorLine = false
            if let tok = it.peek(), case .blank = tok.kind {
                // blank → header ends; do nothing
            } else if headerSeen, let tok = it.peek(), case .text(let r) = tok.kind {
                let authorLineRaw = it.textFromRelative(range: r, token: tok)
                let line = env.expand(authorLineRaw).trimmingCharacters(in: .whitespacesAndNewlines)
                if !line.isEmpty {
                    var handled = false
                    if parsedAuthors == nil && header?.title != nil {
                        if let revisionCandidate = parseRevisionLine(line) {
                            // Only treat as revision if there wasn't an author line and it clearly matches a revision pattern.
                            revisionInfo = revisionCandidate
                            it.consume()
                            lastHeaderTok = tok
                            headerSeen = true
                            handled = true
                        }
                    }
                    if !handled {
                        let authors = parseAuthorsLine(line)
                        parsedAuthors = authors
                        consumedAuthorLine = true
                        let mappedAuthors: [AdocAuthor] = authors.map {
                            AdocAuthor(
                                fullname: $0.fullname,
                                initials: $0.initials,
                                firstname: $0.firstname,
                                middlename: $0.middlename,
                                lastname: $0.lastname,
                                address: nil
                            )
                        }
                        if header == nil {
                            let lineSpan = it.spanForLine(tok)
                            header = AdocHeader(title: nil, authors: mappedAuthors, location: rangeToLocation(lineSpan))
                        } else {
                            header!.authors = mappedAuthors
                        }
                        it.consume() // consume author line
                        lastHeaderTok = tok
                        headerSeen = true
                    }
                }
            }

            if consumedAuthorLine {
                if let tok = it.peek(), case .blank = tok.kind {
                    // nothing
                } else if headerSeen, let tok = it.peek(), case .text(let r) = tok.kind {
                    let revisionLineRaw = it.textFromRelative(range: r, token: tok)
                    let revisionLine = env.expand(revisionLineRaw).trimmingCharacters(in: .whitespacesAndNewlines)
                    if let revision = parseRevisionLine(revisionLine) {
                        revisionInfo = revision
                        it.consume()
                        lastHeaderTok = tok
                        headerSeen = true
                    }
                }
            } else if revisionInfo == nil, let tok = it.peek(), case .text(let r) = tok.kind, headerSeen {
                let revisionLineRaw = it.textFromRelative(range: r, token: tok)
                let revisionLine = env.expand(revisionLineRaw).trimmingCharacters(in: .whitespacesAndNewlines)
                if let revision = parseRevisionLine(revisionLine) {
                    revisionInfo = revision
                    it.consume()
                    lastHeaderTok = tok
                    headerSeen = true
                }
            }

            // Optional list of attributes (no blank lines allowed within header)
            
            attrsLoop: while let tok = it.peek() {
                switch tok.kind {
                case .attrSet(let nameR, let valueR):
                    let name = it.textFromRelative(range: nameR, token: tok)
                    let value = valueR.map { it.textFromRelative(range: $0, token: tok) }
                    if !lockedAttributes.contains(name) {
                        docAttrs[name] = value
                        env.set(name, to: value)
                    }
                    it.consume();
                    lastHeaderTok = tok
                    
                    headerSeen = true
                    continue attrsLoop
                case .attrUnset(let nameR):
                    let name = it.textFromRelative(range: nameR, token: tok)
                    if !lockedAttributes.contains(name) {
                        docAttrs[name] = nil
                        env.set(name, to: nil)
                    }

                    it.consume();
                    lastHeaderTok = tok
                    
                    headerSeen = true
                    continue attrsLoop
                case .blank:
                    // A blank line terminates header; consume it and break
                    it.consume()
                    break attrsLoop
                default:
                    break attrsLoop
                }
            }

            // If we produced any part of the header, ensure attributes map is non-nil
            if headerSeen {
                if docAttrs.isEmpty { docAttrs = [:] }
                // Ensure we have a header object even if it was attributes-only
                if header == nil {
                    header = AdocHeader(title: nil, authors: nil, location: nil)
                }
                // Extend header location to cover the entire header range (title/author/attributes)
                if let sTok = headerStartTok ?? lastHeaderTok, let eTok = lastHeaderTok {
                    let span = spanFromTokens(start: sTok, end: eTok, it: it)
                    header!.location = rangeToLocation(span)
                } else if let onlyTok = headerStartTok ?? lastHeaderTok {
                    header!.location = rangeToLocation(it.spanForLine(onlyTok))
                } else if let onlyTok = headerStartTok {
                    header!.location = rangeToLocation(it.spanForLine(onlyTok))
                }

                if includeDerivedAttributes {
                    applyHeaderDerivedAttributes(
                        header: header,
                        authors: parsedAuthors,
                        revision: revisionInfo,
                        attrs: &docAttrs,
                        lockedAttributes: lockedAttributes
                    )
                }
            }
        }
    }

}

private func parseAuthorsLine(_ line: String) -> [HeaderAuthorInfo] {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return [] }
    let segments = trimmed
        .split(separator: ";")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    let parts = segments.isEmpty ? [trimmed] : segments
    return parts.map { segment in
        parseSingleAuthor(String(segment))
    }
}

private func parseSingleAuthor(_ raw: String) -> HeaderAuthorInfo {
    var namePortion = raw
    var email: String?
    if let start = namePortion.firstIndex(of: "<"),
       let end = namePortion[start...].firstIndex(of: ">"),
       start < end {
        let valueRange = namePortion.index(after: start)..<end
        email = String(namePortion[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        namePortion.removeSubrange(start...end)
    }
    let trimmedName = namePortion.trimmingCharacters(in: .whitespacesAndNewlines)
    let componentStrings = trimmedName
        .split(whereSeparator: { $0 == " " || $0 == "\t" })
        .map { String($0) }

    let firstname = componentStrings.first
    let lastname = componentStrings.count > 1 ? componentStrings.last : nil
    let middlename: String? = componentStrings.count > 2
        ? componentStrings[1..<(componentStrings.count - 1)].joined(separator: " ")
        : nil

    let initials = componentStrings
        .compactMap { $0.first }
        .map { String($0).uppercased() }
        .joined()

    let fallbackName = trimmedName.isEmpty ? raw.trimmingCharacters(in: .whitespacesAndNewlines) : trimmedName
    return HeaderAuthorInfo(
        fullname: fallbackName,
        firstname: firstname,
        middlename: middlename,
        lastname: lastname,
        initials: initials.isEmpty ? nil : initials,
        email: email
    )
}

private func parseRevisionLine(_ rawLine: String) -> HeaderRevisionInfo? {
    if rawLine.contains("<") || rawLine.contains("@") { return nil }
    let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    var remainder = trimmed
    var remark: String?
    if let colon = remainder.firstIndex(of: ":") {
        let afterColon = remainder.index(after: colon)
        let remarkPart = remainder[afterColon...].trimmingCharacters(in: .whitespacesAndNewlines)
        if !remarkPart.isEmpty {
            remark = remarkPart
        }
        remainder = String(remainder[..<colon]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var recognized = false
    var number: String?
    var date: String?
    if let comma = remainder.firstIndex(of: ",") {
        let numberPart = remainder[..<comma].trimmingCharacters(in: .whitespacesAndNewlines)
        let datePart = remainder[remainder.index(after: comma)...].trimmingCharacters(in: .whitespacesAndNewlines)
        if looksLikeRevisionNumber(numberPart) {
            number = numberPart
            recognized = true
        }
        if looksLikeDateString(datePart) {
            date = datePart
            recognized = true
        }
        if number == nil && !numberPart.isEmpty {
            number = numberPart
            recognized = true
        }
        if date == nil && !datePart.isEmpty {
            date = datePart
            recognized = true
        }
    } else if !remainder.isEmpty {
        if looksLikeDateString(remainder) {
            date = remainder
            recognized = true
        } else if looksLikeRevisionNumber(remainder) {
            number = remainder
            recognized = true
        }
    }

    if remark != nil && (number != nil || date != nil) {
        recognized = true
    }

    if !recognized {
        return nil
    }

    return HeaderRevisionInfo(number: number, date: date, remark: remark)
}

private func looksLikeRevisionNumber(_ s: String) -> Bool {
    var trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }
    if trimmed.first == "v" || trimmed.first == "V" {
        trimmed = String(trimmed.dropFirst())
    }
    guard let first = trimmed.first, first.isNumber else { return false }
    for ch in trimmed {
        if !(ch.isNumber || ch.isLetter || ch == "." || ch == "-" || ch == "_") {
            return false
        }
    }
    return true
}

private func looksLikeDateString(_ s: String) -> Bool {
    let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }
    let patterns = [
        #"^\d{4}[-/]\d{1,2}[-/]\d{1,2}$"#,
        #"^\d{1,2}[-/]\d{1,2}[-/]\d{2,4}$"#,
        #"^[A-Za-z]{3,}\s+\d{1,2},\s*\d{2,4}$"#,
        #"^\d{1,2}\s+[A-Za-z]{3,}\s+\d{2,4}$"#
    ]
    for pattern in patterns {
        if trimmed.range(of: pattern, options: .regularExpression) != nil {
            return true
        }
    }
    return false
}

private func applyHeaderDerivedAttributes(
    header: AdocHeader?,
    authors: [HeaderAuthorInfo]?,
    revision: HeaderRevisionInfo?,
    attrs: inout [String: String?],
    lockedAttributes: Set<String>
) {
    func assign(_ key: String, _ value: String?) {
        guard let value, !value.isEmpty else { return }
        guard !lockedAttributes.contains(key) else { return }
        attrs[key] = value
    }

    if let title = header?.title?.plain, !title.isEmpty {
        assign("doctitle", title)
    }

    if let authors, !authors.isEmpty {
        let fullNames = authors.map { $0.fullname }.joined(separator: "; ")
        assign("authors", fullNames)
        let first = authors[0]
        assign("author", first.fullname)
        assign("firstname", first.firstname)
        assign("middlename", first.middlename)
        assign("lastname", first.lastname)
        assign("authorinitials", first.initials)
        assign("email", first.email)
    }

    if let revision {
        assign("revnumber", revision.number)
        assign("revdate", revision.date)
        assign("revremark", revision.remark)
    }
}
