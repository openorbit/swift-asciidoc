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

    private func rebuildProjection(selection: (AsciiDocEditorFieldKey, Int)? = nil) {
        projection = AdocSemanticProjectionBuilder.make(document: editorDocument)
        isApplyingProjection = true
        textStorage?.setAttributedString(projection.attributedString)
        isApplyingProjection = false

        if let selection, let fieldRange = projection.range(for: selection.0) {
            let location = min(fieldRange.location + selection.1, NSMaxRange(fieldRange))
            setSelectedRange(NSRange(location: location, length: 0))
        }
    }

    public func textView(
        _ textView: NSTextView,
        shouldChangeTextIn affectedCharRange: NSRange,
        replacementString: String?
    ) -> Bool {
        guard !isApplyingProjection,
              let field = projection.field(containing: affectedCharRange) else {
            NSSound.beep()
            return false
        }

        let current = (projection.attributedString.string as NSString).substring(with: field.range)

        let localRange = NSRange(
            location: affectedCharRange.location - field.range.location,
            length: affectedCharRange.length
        )
        guard NSMaxRange(localRange) <= (current as NSString).length else { return false }

        let replacement = replacementString ?? ""
        let previousDocument = editorDocument
        let updated = (current as NSString).replacingCharacters(in: localRange, with: replacement)
        if editorDocument.semanticText(for: field.key) != nil {
            _ = editorDocument.replaceSemanticText(for: field.key, in: localRange, with: replacement)
        } else {
            editorDocument.updateText(updated, for: field.key)
        }
        registerUndo(previousDocument)
        onDocumentChange?(editorDocument)
        rebuildProjection(selection: (field.key, localRange.location + (replacement as NSString).length))
        return false
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

    private func rebuildProjection(selection: (AsciiDocEditorFieldKey, Int)? = nil) {
        projection = AdocSemanticProjectionBuilder.make(document: editorDocument)
        isApplyingProjection = true
        attributedText = projection.attributedString
        isApplyingProjection = false

        if let selection, let fieldRange = projection.range(for: selection.0) {
            let location = min(fieldRange.location + selection.1, NSMaxRange(fieldRange))
            selectedRange = NSRange(location: location, length: 0)
        }
    }

    public func textView(
        _ textView: UITextView,
        shouldChangeTextIn range: NSRange,
        replacementText text: String
    ) -> Bool {
        guard !isApplyingProjection,
              markedTextRange == nil,
              let field = projection.field(containing: range) else {
            return markedTextRange != nil
        }


        let current = (projection.attributedString.string as NSString).substring(with: field.range)

        let localRange = NSRange(location: range.location - field.range.location, length: range.length)
        guard NSMaxRange(localRange) <= (current as NSString).length else { return false }

        let previousDocument = editorDocument
        let updated = (current as NSString).replacingCharacters(in: localRange, with: text)
        if editorDocument.semanticText(for: field.key) != nil {
            _ = editorDocument.replaceSemanticText(for: field.key, in: localRange, with: text)
        } else {
            editorDocument.updateText(updated, for: field.key)
        }
        registerUndo(previousDocument)
        onDocumentChange?(editorDocument)
        rebuildProjection(selection: (field.key, localRange.location + (text as NSString).length))
        return false
    }

    public func textViewDidChange(_ textView: UITextView) {
        // Marked text is left under UIKit's control. Reconciliation of composed
        // text into semantic fields is the next input-pipeline milestone.
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
