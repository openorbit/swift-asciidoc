//
// Copyright (c) 2025 Mattias Holm
// SPDX-License-Identifier: Apache-2.0
//

import Foundation

#if canImport(AppKit)
import AppKit

public final class AsciiDocNSTextEditorView: NSTextView, NSTextViewDelegate {
    public var editorDocument = AsciiDocEditorDocument() {
        didSet { if !isApplyingProjection { rebuildProjection() } }
    }

    public var onDocumentChange: ((AsciiDocEditorDocument) -> Void)?
    public var onSelectionChange: ((AsciiDocEditorSelection?) -> Void)?

    private var projection = AdocSemanticProjectionBuilder.make(document: .init())
    private var isApplyingProjection = false
    private var retainedContentStorage: NSTextContentStorage?

    public convenience init(textKit2Frame frameRect: NSRect) {
        let contentStorage = NSTextContentStorage()
        let layoutManager = NSTextLayoutManager()
        let container = NSTextContainer()
        contentStorage.addTextLayoutManager(layoutManager)
        layoutManager.textContainer = container
        self.init(frame: frameRect, textContainer: container)
        retainedContentStorage = contentStorage
    }

    public override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        configure()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        delegate = self
        isRichText = true
        isEditable = true
        isSelectable = true
        allowsUndo = true
        drawsBackground = false
        isVerticallyResizable = true
        isHorizontallyResizable = false
        minSize = .zero
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        autoresizingMask = [.width]
        textContainerInset = NSSize(width: 24, height: 20)
        textContainer?.widthTracksTextView = true
        textContainer?.lineFragmentPadding = 0
        rebuildProjection()
    }

    private func rebuildProjection(selection: AsciiDocEditorSelection? = nil) {
        let targetSelection: AsciiDocEditorSelection?
        if let selection {
            targetSelection = selection
        } else {
            let nativeRange = selectedRange()
            if let field = projection.field(containing: nativeRange) {
                targetSelection = AsciiDocEditorSelection(
                    field: field.key,
                    range: NSRange(location: nativeRange.location - field.range.location, length: nativeRange.length)
                )
            } else {
                targetSelection = nil
            }
        }

        projection = AdocSemanticProjectionBuilder.make(document: editorDocument)
        isApplyingProjection = true
        textStorage?.setAttributedString(projection.attributedString)
        isApplyingProjection = false

        if let targetSelection {
            applySelection(targetSelection)
        }
    }

    public func applySelection(_ selection: AsciiDocEditorSelection) {
        let fieldRange = projection.range(for: selection.field)
            ?? projection.firstRange(inBlock: selection.field.blockIndex)
        guard let fieldRange else { return }
        let location = min(fieldRange.location + selection.range.location, NSMaxRange(fieldRange))
        let maxLength = max(0, NSMaxRange(fieldRange) - location)
        let length = min(selection.range.length, maxLength)
        let nativeRange = NSRange(location: location, length: length)
        if selectedRange() != nativeRange {
            setSelectedRange(nativeRange)
        }
        if let field = projection.field(containing: nativeRange) {
            onSelectionChange?(AsciiDocEditorSelection(
                field: field.key,
                range: NSRange(location: nativeRange.location - field.range.location, length: nativeRange.length)
            ))
        }
    }

    public func textView(
        _ textView: NSTextView,
        shouldChangeTextIn affectedCharRange: NSRange,
        replacementString: String?
    ) -> Bool {
        guard !isApplyingProjection else {
            NSSound.beep()
            return false
        }

        let replacement = replacementString ?? ""

        if let field = projection.field(containing: affectedCharRange) {
            let localRange = NSRange(
                location: affectedCharRange.location - field.range.location,
                length: affectedCharRange.length
            )
            let currentLength = field.range.length
            guard NSMaxRange(localRange) <= currentLength else { return false }

            let previousDocument = editorDocument
            if let nextSelection = editorDocument.applyEdit(in: field.key, range: localRange, replacement: replacement) {
                registerUndo(previousDocument)
                onDocumentChange?(editorDocument)
                rebuildProjection(selection: nextSelection)
                return false
            }
        } else if replacement.isEmpty,
                  affectedCharRange.length == 1,
                  selectedRange().length == 0,
                  let field = projection.field(containing: selectedRange()),
                  selectedRange().location == field.range.location,
                  NSMaxRange(affectedCharRange) == field.range.location {
            let previousDocument = editorDocument
            if let nextSelection = editorDocument.deleteBackwardAtStart(of: field.key) {
                registerUndo(previousDocument)
                onDocumentChange?(editorDocument)
                rebuildProjection(selection: nextSelection)
                return false
            }
        }

        NSSound.beep()
        return false
    }

    public func textViewDidChangeSelection(_ notification: Notification) {
        guard !isApplyingProjection else { return }
        let nativeRange = selectedRange()
        guard let field = projection.field(containing: nativeRange) else {
            onSelectionChange?(nil)
            return
        }
        onSelectionChange?(AsciiDocEditorSelection(
            field: field.key,
            range: NSRange(location: nativeRange.location - field.range.location, length: nativeRange.length)
        ))
    }

    private func registerUndo(_ previousDocument: AsciiDocEditorDocument) {
        undoManager?.registerUndo(withTarget: self) { target in
            let redoDocument = target.editorDocument
            target.editorDocument = previousDocument
            target.onDocumentChange?(previousDocument)
            target.registerUndo(redoDocument)
        }
    }
}

#elseif canImport(UIKit)
import UIKit

public final class AsciiDocUITextEditorView: UITextView, UITextViewDelegate {
    public var editorDocument = AsciiDocEditorDocument() {
        didSet { if !isApplyingProjection { rebuildProjection() } }
    }

    public var onDocumentChange: ((AsciiDocEditorDocument) -> Void)?
    public var onSelectionChange: ((AsciiDocEditorSelection?) -> Void)?

    private var projection = AdocSemanticProjectionBuilder.make(document: .init())
    private var isApplyingProjection = false
    private var retainedContentStorage: NSTextContentStorage?

    public convenience init(textKit2Frame frame: CGRect) {
        let contentStorage = NSTextContentStorage()
        let layoutManager = NSTextLayoutManager()
        let container = NSTextContainer()
        contentStorage.addTextLayoutManager(layoutManager)
        layoutManager.textContainer = container
        self.init(frame: frame, textContainer: container)
        retainedContentStorage = contentStorage
    }

    public override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        configure()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        delegate = self
        backgroundColor = .clear
        isEditable = true
        isSelectable = true
        allowsEditingTextAttributes = true
        adjustsFontForContentSizeCategory = true
        textContainerInset = UIEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)
        textContainer.lineFragmentPadding = 0
        rebuildProjection()
    }

    private func rebuildProjection(selection: AsciiDocEditorSelection? = nil) {
        let targetSelection: AsciiDocEditorSelection?
        if let selection {
            targetSelection = selection
        } else {
            let nativeRange = selectedRange
            if let field = projection.field(containing: nativeRange) {
                targetSelection = AsciiDocEditorSelection(
                    field: field.key,
                    range: NSRange(location: nativeRange.location - field.range.location, length: nativeRange.length)
                )
            } else {
                targetSelection = nil
            }
        }

        projection = AdocSemanticProjectionBuilder.make(document: editorDocument)
        isApplyingProjection = true
        attributedText = projection.attributedString
        isApplyingProjection = false

        if let targetSelection {
            applySelection(targetSelection)
        }
    }

    public func applySelection(_ selection: AsciiDocEditorSelection) {
        let fieldRange = projection.range(for: selection.field)
            ?? projection.firstRange(inBlock: selection.field.blockIndex)
        guard let fieldRange else { return }
        let location = min(fieldRange.location + selection.range.location, NSMaxRange(fieldRange))
        let maxLength = max(0, NSMaxRange(fieldRange) - location)
        let length = min(selection.range.length, maxLength)
        let nativeRange = NSRange(location: location, length: length)
        if selectedRange != nativeRange {
            selectedRange = nativeRange
        }
        if let field = projection.field(containing: nativeRange) {
            onSelectionChange?(AsciiDocEditorSelection(
                field: field.key,
                range: NSRange(location: nativeRange.location - field.range.location, length: nativeRange.length)
            ))
        }
    }

    public func textView(
        _ textView: UITextView,
        shouldChangeTextIn range: NSRange,
        replacementText text: String
    ) -> Bool {
        guard !isApplyingProjection, markedTextRange == nil else {
            return markedTextRange != nil
        }

        if let field = projection.field(containing: range) {
            let localRange = NSRange(location: range.location - field.range.location, length: range.length)
            guard NSMaxRange(localRange) <= field.range.length else { return false }

            let previousDocument = editorDocument
            if let nextSelection = editorDocument.applyEdit(in: field.key, range: localRange, replacement: text) {
                registerUndo(previousDocument)
                onDocumentChange?(editorDocument)
                rebuildProjection(selection: nextSelection)
                return false
            }
        } else if text.isEmpty,
                  range.length == 1,
                  selectedRange.length == 0,
                  let field = projection.field(containing: selectedRange),
                  selectedRange.location == field.range.location,
                  NSMaxRange(range) == field.range.location {
            let previousDocument = editorDocument
            if let nextSelection = editorDocument.deleteBackwardAtStart(of: field.key) {
                registerUndo(previousDocument)
                onDocumentChange?(editorDocument)
                rebuildProjection(selection: nextSelection)
                return false
            }
        }

        return false
    }

    public func textViewDidChange(_ textView: UITextView) {
        // Marked text is left under UIKit's control. Reconciliation of composed
        // text into semantic fields is the next input-pipeline milestone.
    }

    public func textViewDidChangeSelection(_ textView: UITextView) {
        guard !isApplyingProjection else { return }
        let nativeRange = selectedRange
        guard let field = projection.field(containing: nativeRange) else {
            onSelectionChange?(nil)
            return
        }
        onSelectionChange?(AsciiDocEditorSelection(
            field: field.key,
            range: NSRange(location: nativeRange.location - field.range.location, length: nativeRange.length)
        ))
    }

    private func registerUndo(_ previousDocument: AsciiDocEditorDocument) {
        undoManager?.registerUndo(withTarget: self) { target in
            let redoDocument = target.editorDocument
            target.editorDocument = previousDocument
            target.onDocumentChange?(previousDocument)
            target.registerUndo(redoDocument)
        }
    }
}
#endif
