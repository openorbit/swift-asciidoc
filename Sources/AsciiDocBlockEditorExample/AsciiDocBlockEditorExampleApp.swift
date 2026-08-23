//
// Copyright (c) 2025 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

#if canImport(SwiftUI)
import AsciiDocBlockEditor
import SwiftUI

@main
struct AsciiDocBlockEditorExampleApp: App {
    @State private var document = AsciiDocEditorDocument.sample
    @State private var sourceText = AsciiDocEditorDocument.sample.asciiDocSource()

    var body: some Scene {
        WindowGroup {
            VStack(spacing: 0) {
                HStack {
                    Button("Load Sample") {
                        document = .sample
                        sourceText = document.asciiDocSource()
                    }

                    Button("Open Source") {
                        document = AsciiDocEditorDocument(asciiDoc: sourceText)
                    }

                    Button("Save to Source") {
                        sourceText = document.asciiDocSource()
                    }

                    Spacer()

                    Text("AsciiDoc Playground")
                        .font(.headline)

                    Spacer()

                    if !document.warnings.isEmpty {
                        Menu("Warnings (\(document.warnings.count))") {
                            ForEach(Array(document.warnings.enumerated()), id: \.offset) { _, warning in
                                Text(warning.message)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.bar)

                HSplitView {
                    sourceColumn
                    AsciiDocBlockEditor(document: $document)
                }
            }
        }
    }

    private var sourceColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("AsciiDoc Source")
                    .font(.headline)

                Spacer()

                Text("Realized on open/save")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextEditor(text: $sourceText)
                .font(.custom("SF Mono", size: 13, relativeTo: .body))
                .scrollContentBackground(.hidden)
                .padding(12)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(20)
        .frame(minWidth: 340, idealWidth: 420)
        .background(.background)
    }
}
#else
@main
struct AsciiDocBlockEditorExampleFallback {
    static func main() {
        print("AsciiDocBlockEditorExample requires an Apple platform with SwiftUI.")
    }
}
#endif
