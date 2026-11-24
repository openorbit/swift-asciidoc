//
// Copyright (c) 2025 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

#if canImport(SwiftUI)
import SwiftUI

/// The continuous semantic AsciiDoc editing surface.
///
/// The native text view displays a TextKit projection of the ISM and commits
/// edits directly to `AsciiDocEditorDocument`. It does not edit serialized
/// AsciiDoc source.
public struct AsciiDocEditorView: View {
    @Binding private var document: AsciiDocEditorDocument
    @State private var selection: AsciiDocEditorSelection?

    public init(document: Binding<AsciiDocEditorDocument>) {
        _document = document
    }

    public var body: some View {
        VStack(spacing: 0) {
            semanticToolbar
            Divider()
            PlatformSemanticTextView(document: $document, selection: $selection)
        }
        .background(.background)
    }

    private var semanticToolbar: some View {
        HStack(spacing: 8) {
            Menu(blockStyleTitle) {
                if selectedBlockIndex == nil {
                    Text(selection?.field.path == "title" ? "Document Title" : "Select text")
                } else {
                    Menu("Heading") {
                        ForEach(1...5, id: \.self) { level in
                            Button("Heading \(level)") { setBlockStyle(.heading, headingLevel: level) }
                        }
                    }
                    .disabled(!canSetBlockStyle(.heading))
                    ForEach(AsciiDocEditorBlockKind.allCases.filter { $0 != .heading }) { kind in
                        Button(kind.title) { setBlockStyle(kind, headingLevel: nil) }
                            .disabled(!canSetBlockStyle(kind))
                    }
                }
            }
            .help("Semantic paragraph or block style")

            Divider().frame(height: 20)

            ForEach(AsciiDocInlineMarkup.allCases) { markup in
                Button {
                    applyInline(markup)
                } label: {
                    Image(systemName: markup.symbol)
                }
                .buttonStyle(.borderless)
                .help(markup.title)
                .accessibilityLabel(markup.title)
                .disabled(!canApplyInline)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.bar)
    }

    private var selectedBlockIndex: Int? {
        guard let index = selection?.field.blockIndex, document.blocks.indices.contains(index) else { return nil }
        return index
    }

    private var blockStyleTitle: String {
        guard let selection else { return "Style" }
        if selection.field.blockIndex == -1 { return "Title" }
        guard let index = selectedBlockIndex, let kind = document.blockKind(at: index) else { return "Style" }
        if kind == .heading { return "Heading \(document.headingLevel(at: index) ?? 1)" }
        return kind.title
    }

    private var canApplyInline: Bool {
        guard let selection, selection.range.length > 0 else { return false }
        return document.semanticText(for: selection.field) != nil
    }

    private func applyInline(_ markup: AsciiDocInlineMarkup) {
        guard let selection else { return }
        _ = document.applySemanticInline(markup, to: selection.field, visibleRange: selection.range)
    }

    private func canSetBlockStyle(_ kind: AsciiDocEditorBlockKind) -> Bool {
        guard let index = selectedBlockIndex else { return false }
        return document.blockKind(at: index) == kind || document.canTransformBlock(at: index, to: kind)
    }

    private func setBlockStyle(_ kind: AsciiDocEditorBlockKind, headingLevel: Int?) {
        guard let selection, selectedBlockIndex != nil else { return }
        let updatedSelection = document.setBlockStyle(kind, headingLevel: headingLevel, at: selection)
        self.selection = updatedSelection
    }
}

/// Compatibility name retained for the existing product and demo app.
public struct AsciiDocBlockEditor: View {
    @Binding private var document: AsciiDocEditorDocument

    public init(document: Binding<AsciiDocEditorDocument>) {
        _document = document
    }

    public var body: some View {
        AsciiDocEditorView(document: $document)
    }
}

#if os(macOS)
import AppKit

private struct PlatformSemanticTextView: NSViewRepresentable {
    @Binding var document: AsciiDocEditorDocument
    @Binding var selection: AsciiDocEditorSelection?

    func makeNSView(context: Context) -> NSScrollView {
        let textView = AsciiDocNSTextEditorView(textKit2Frame: .zero)
        textView.editorDocument = document
        textView.onDocumentChange = { updated in
            document = updated
        }
        textView.onSelectionChange = { selection = $0 }

        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? AsciiDocNSTextEditorView else { return }
        textView.onDocumentChange = { updated in
            document = updated
        }
        textView.onSelectionChange = { selection = $0 }
        if textView.editorDocument != document {
            textView.editorDocument = document
            if let selection {
                textView.applySelection(selection)
            }
        }
    }
}

#elseif canImport(UIKit)
import UIKit

private struct PlatformSemanticTextView: UIViewRepresentable {
    @Binding var document: AsciiDocEditorDocument
    @Binding var selection: AsciiDocEditorSelection?

    func makeUIView(context: Context) -> AsciiDocUITextEditorView {
        let textView = AsciiDocUITextEditorView(textKit2Frame: .zero)
        textView.editorDocument = document
        textView.onDocumentChange = { updated in
            document = updated
        }
        textView.onSelectionChange = { selection = $0 }
        return textView
    }

    func updateUIView(_ textView: AsciiDocUITextEditorView, context: Context) {
        textView.onDocumentChange = { updated in
            document = updated
        }
        textView.onSelectionChange = { selection = $0 }
        if textView.editorDocument != document {
            textView.editorDocument = document
            if let selection {
                textView.applySelection(selection)
            }
        }
    }
}
#endif
#endif
