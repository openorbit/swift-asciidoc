//
// Copyright (c) 2025 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

extension AdocParser {

    private func effectiveTableFormat(styleChar: Character,
                                      meta: AdocBlockMeta?) -> AdocTableFormat {
        if let fmt = meta?.attributes["format"]?.lowercased() {
            switch fmt {
            case "csv": return .csv
            case "tsv": return .tsv
            case "dsv": return .dsv
            case "psv": return .psv
            default: break // unknown → fall through to boundary char
            }
        }

        switch styleChar {
        case "|": return .psv
        case ",": return .csv
        case ";": return .dsv
        case "\t": return .tsv
        default:   return .psv
        }
    }


    /// Infer table format + separator from styleChar and optional block attributes.
    ///
    /// Priority:
    /// 1. format=... attribute (psv/csv/tsv/dsv)
    /// 2. table fence styleChar (| , : ;)
    /// 3. default separator per format:
    ///    psv → '|' , csv → ',' , tsv → '\t', dsv → ':'
    private func inferTableFormat(
        styleChar: Character,
        attributes: [String: String]? = nil
    ) -> (format: AdocTableFormat, separator: Character) {

        // Attribute-based format (future-proof; attributes will come from block meta)
        if let fmtRaw = attributes?["format"]?.lowercased() {
            switch fmtRaw {
            case "psv":
                let sep = separatorFromAttributes(attributes, defaultSep: "|")
                return (.psv, sep)
            case "csv":
                let sep = separatorFromAttributes(attributes, defaultSep: ",")
                return (.csv, sep)
            case "tsv":
                let sep = separatorFromAttributes(attributes, defaultSep: "\t")
                return (.tsv, sep)
            case "dsv":
                let sep = separatorFromAttributes(attributes, defaultSep: ":")
                return (.dsv, sep)
            default:
                break
            }
        }

        // Fallback to fence styleChar
        switch styleChar {
        case "|":
            // PSV with default '|' separator (can be overridden by attributes later)
            let sep = separatorFromAttributes(attributes, defaultSep: "|")
            return (.psv, sep)
        case ",":
            let sep = separatorFromAttributes(attributes, defaultSep: ",")
            return (.csv, sep)
        case ":":
            let sep = separatorFromAttributes(attributes, defaultSep: ":")
            return (.dsv, sep)
        case ";":
            // ';' is not standard, but we can treat it as DSV with ';' as default separator
            let sep = separatorFromAttributes(attributes, defaultSep: ";")
            return (.dsv, sep)
        default:
            // Fallback: assume PSV with '|' separator
            let sep = separatorFromAttributes(attributes, defaultSep: "|")
            return (.psv, sep)
        }
    }

    /// Helper: resolve separator from attributes, handling `\t` for tab.
    private func separatorFromAttributes(
        _ attributes: [String: String]?,
        defaultSep: Character
    ) -> Character {
        guard let raw = attributes?["separator"], !raw.isEmpty else {
            return defaultSep
        }
        if raw == "\\t" {
            return "\t"
        }
        return raw.first ?? defaultSep
    }

    func parseTable(
        styleChar: Character,
        it: inout TokenIter,
        env: AttrEnv,
        meta: AdocBlockMeta? = nil
    ) -> AdocTable? {
        // Current token must be the opening table boundary
        guard let open = it.peek(),
              case .tableBoundary(let ch) = open.kind,
              ch == styleChar
        else {
            return nil
        }

        // Consume opening fence, e.g. "|===", ",===", ":==="
        it.consume()

        // Decide format + logical separator based on fence char + attributes
        // Use meta?.attributes to infer format + separator
        let (format, separator) = inferTableFormat(
            styleChar: styleChar,
            attributes: meta?.attributes
        )

        var rows: [String] = []
        var firstBodyTok: Token? = nil
        var lastBodyTok: Token? = nil
        var closeTok: Token? = nil
        var headerBreakIndex: Int?

        // Collect content lines until matching closing boundary
        while let t = it.peek() {
            switch t.kind {
            case .tableBoundary(let ch) where ch == styleChar:
                // Closing fence
                closeTok = t
                it.consume()
                break

            case .blank:
                if headerBreakIndex == nil {
                    headerBreakIndex = rows.count
                }
                rows.append("")
                firstBodyTok = firstBodyTok ?? t
                lastBodyTok = t
                it.consume()

            case .text, .directive:
                // Inside a table we keep the raw line (no trimming),
                // so that PSV/CSV/TSV/DSV parsing can be done later.
                let line = it.rawLineText(of: t)
                rows.append(line)
                firstBodyTok = firstBodyTok ?? t
                lastBodyTok = t
                it.consume()

            default:
                // Unexpected structural token inside table → stop table here,
                // let caller handle the token.
                closeTok = nil
                break
            }

            if closeTok != nil {
                break
            }
        }

        // Compute span: from opening fence to closing fence (if any),
        // otherwise to end of last content row, or just the opening fence.
        let span: AdocRange? = {
            if let close = closeTok {
                return AdocRange(start: open.range.start, end: close.range.end)
            }
            if let last = lastBodyTok {
                return AdocRange(start: open.range.start, end: last.range.end)
            }
            return open.range
        }()

        let headerRowCountFromBlank = countRowGroupsBeforeBreak(rows: rows, breakIndex: headerBreakIndex)
        var headerRowCount = headerRowCountFromBlank
        let attributesOptions: [String] = {
            guard let raw = meta?.attributes["options"] else { return [] }
            return raw.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }()
        let hasHeaderOption = (
            meta?.options.contains(where: {
                $0.caseInsensitiveCompare("header") == .orderedSame
            }) ?? false
        ) || attributesOptions.contains(where: {
            $0.caseInsensitiveCompare("header") == .orderedSame
        })
        if headerRowCount == 0, hasHeaderOption, rows.contains(where: { !$0.isEmpty }) {
            headerRowCount = 1
        }

        let columnAlignments = meta?.attributes["cols"]
            .flatMap { parseColumnAlignments($0) }

        var table = AdocTable(
            format: format,
            separator: separator,
            styleChar: styleChar,
            rows: rows,
            id: nil,
            title: nil,
            reftext: nil,
            meta: .init(),
            span: span
        )
        table.headerRowCount = headerRowCount
        table.columnAlignments = columnAlignments
        return table
    }

    private func countRowGroupsBeforeBreak(rows: [String], breakIndex: Int?) -> Int {
        guard let breakIndex else { return 0 }
        let limit = min(breakIndex, rows.count)
        var count = 0
        var idx = 0
        while idx < limit {
            if rows[idx].isEmpty {
                idx += 1
                continue
            }
            count += 1
            idx += 1
            while idx < limit, !rows[idx].isEmpty {
                idx += 1
            }
        }
        return count
    }

    private func parseColumnAlignments(_ rawSpec: String) -> [AdocTableColumnAlignment] {
        let parts = rawSpec.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        var alignments: [AdocTableColumnAlignment] = []

        for part in parts where !part.isEmpty {
            var token = part
            var repeatCount = 1
            if let star = token.firstIndex(of: "*") {
                let countSlice = token[..<star]
                let countText = String(countSlice).trimmingCharacters(in: .whitespaces)
                if let count = Int(countText), count > 0 {
                    repeatCount = count
                }
                token = String(token[token.index(after: star)...])
            }

            guard let alignChar = token.first else { continue }
            guard let alignment = alignmentFromSpecifier(alignChar) else { continue }
            for _ in 0..<repeatCount {
                alignments.append(alignment)
            }
        }

        return alignments
    }

    private func alignmentFromSpecifier(_ char: Character) -> AdocTableColumnAlignment? {
        let lower = Character(String(char).lowercased())
        switch lower {
        case "l", "<": return .left
        case "c", "^": return .center
        case "r", ">": return .right
        default: return nil
        }
    }
}
