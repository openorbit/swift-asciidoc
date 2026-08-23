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

    public init(document: Binding<AsciiDocEditorDocument>) {
        _document = document
    }

    public var body: some View {
        PlatformSemanticTextView(document: $document)
            .background(.background)
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

    func makeNSView(context: Context) -> NSScrollView {
        let textView = AsciiDocNSTextEditorView(textKit2Frame: .zero)
        textView.editorDocument = document
        textView.onDocumentChange = { updated in
            document = updated
        }

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
        if textView.editorDocument != document {
            textView.editorDocument = document
        }
    }
}

#elseif canImport(UIKit)
import UIKit

private struct PlatformSemanticTextView: UIViewRepresentable {
    @Binding var document: AsciiDocEditorDocument

    func makeUIView(context: Context) -> AsciiDocUITextEditorView {
        let textView = AsciiDocUITextEditorView(textKit2Frame: .zero)
        textView.editorDocument = document
        textView.onDocumentChange = { updated in
            document = updated
        }
        return textView
    }

    func updateUIView(_ textView: AsciiDocUITextEditorView, context: Context) {
        textView.onDocumentChange = { updated in
            document = updated
        }
        if textView.editorDocument != document {
            textView.editorDocument = document
        }
    }
}
#endif
#endif
