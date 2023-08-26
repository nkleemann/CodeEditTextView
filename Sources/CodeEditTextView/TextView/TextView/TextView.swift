//
//  TextView.swift
//  
//
//  Created by Khan Winter on 6/21/23.
//

import AppKit
import STTextView
import TextStory

/**

```
 TextView
 |-> TextLayoutManager          Creates, manages, and lays out text lines from a line storage
 |  |-> [TextLine]              Represents a text line
 |  |   |-> Typesetter          Lays out and calculates line fragments
 |  |   |-> [LineFragment]      Represents a visual text line, stored in a line storage for long lines
 |  |-> [LineFragmentView]      Reusable line fragment view that draws a line fragment.
 |
 |-> TextSelectionManager       Maintains, modifies, and renders text selections
 |  |-> [TextSelection]
 ```
 */
class TextView: NSView, NSTextContent {
    // MARK: - Configuration

    func setString(_ string: String) {
        textStorage.setAttributedString(.init(string: string))
    }

    public var font: NSFont {
        didSet {
            setNeedsDisplay()
            layoutManager.setNeedsLayout()
        }
    }
    public var lineHeight: CGFloat
    public var wrapLines: Bool
    public var editorOverscroll: CGFloat
    public var isEditable: Bool
    @Invalidating(.display)
    public var isSelectable: Bool = true
    public var letterSpacing: Double

    open var contentType: NSTextContentType?

    // MARK: - Internal Properties

    private(set) var textStorage: NSTextStorage!
    private(set) var layoutManager: TextLayoutManager!
    private(set) var selectionManager: TextSelectionManager!

    internal var isFirstResponder: Bool = false

    var _undoManager: CEUndoManager?
    @objc dynamic open var allowsUndo: Bool

    var scrollView: NSScrollView? {
        guard let enclosingScrollView, enclosingScrollView.documentView == self else { return nil }
        return enclosingScrollView
    }

    // MARK: - Init

    init(
        string: String,
        font: NSFont,
        lineHeight: CGFloat,
        wrapLines: Bool,
        editorOverscroll: CGFloat,
        isEditable: Bool,
        letterSpacing: Double,
        storageDelegate: MultiStorageDelegate!
    ) {
        self.textStorage = NSTextStorage(string: string)

        self.font = font
        self.lineHeight = lineHeight
        self.wrapLines = wrapLines
        self.editorOverscroll = editorOverscroll
        self.isEditable = isEditable
        self.letterSpacing = letterSpacing
        self.allowsUndo = true

        super.init(frame: .zero)

        wantsLayer = true
        postsFrameChangedNotifications = true
        postsBoundsChangedNotifications = true
        autoresizingMask = [.width, .height]

        // TODO: Implement typing/default attributes
        textStorage.addAttributes([.font: font], range: documentRange)

        layoutManager = TextLayoutManager(
            textStorage: textStorage,
            typingAttributes: [
                .font: font,
            ],
            lineHeightMultiplier: lineHeight,
            wrapLines: wrapLines,
            textView: self, // TODO: This is an odd syntax... consider reworking this
            delegate: self
        )
        textStorage.delegate = storageDelegate
        storageDelegate.addDelegate(layoutManager)

        selectionManager = TextSelectionManager(
            layoutManager: layoutManager,
            textStorage: textStorage,
            layoutView: self, // TODO: This is an odd syntax... consider reworking this
            delegate: self
        )
        storageDelegate.addDelegate(selectionManager)

        _undoManager = CEUndoManager(textView: self)

        layoutManager.layoutLines()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - First Responder

    open override func becomeFirstResponder() -> Bool {
        isFirstResponder = true
        return super.becomeFirstResponder()
    }

    open override func resignFirstResponder() -> Bool {
        isFirstResponder = false
        selectionManager.removeCursors()
        return super.resignFirstResponder()
    }

    open override var canBecomeKeyView: Bool {
        super.canBecomeKeyView && acceptsFirstResponder && !isHiddenOrHasHiddenAncestor
    }

    open override var needsPanelToBecomeKey: Bool {
        isSelectable || isEditable
    }

    open override var acceptsFirstResponder: Bool {
        isSelectable
    }

    open override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    open override func resetCursorRects() {
        super.resetCursorRects()
        if isSelectable {
            addCursorRect(visibleRect, cursor: .iBeam)
        }
    }

    // MARK: - View Lifecycle

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        layoutManager.layoutLines()
    }

    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        updateFrameIfNeeded()
    }

    // MARK: - Interaction

    override func keyDown(with event: NSEvent) {
        guard isEditable else {
            super.keyDown(with: event)
            return
        }

        NSCursor.setHiddenUntilMouseMoves(true)

        if !(inputContext?.handleEvent(event) ?? false) {
            interpretKeyEvents([event])
        } else {
            // Handle key events?
        }
    }

    override func mouseDown(with event: NSEvent) {
        // Set cursor
        guard let offset = layoutManager.textOffsetAtPoint(self.convert(event.locationInWindow, from: nil)) else {
            super.mouseDown(with: event)
            return
        }
        if isSelectable {
            selectionManager.setSelectedRange(NSRange(location: offset, length: 0))
        }

        if !self.isFirstResponder {
            self.window?.makeFirstResponder(self)
        }
    }

    public func replaceCharacters(in ranges: [NSRange], with string: String) {
        guard isEditable else { return }
        layoutManager.beginTransaction()
        textStorage.beginEditing()
        // Can't insert an empty string into an empty range. One must be not empty
        for range in ranges where !range.isEmpty || !string.isEmpty {
            replaceCharactersNoCheck(in: range, with: string)
            _undoManager?.registerMutation(
                TextMutation(string: string as String, range: range, limit: textStorage.length)
            )
        }
        textStorage.endEditing()
        layoutManager.endTransaction()
    }

    public func replaceCharacters(in range: NSRange, with string: String) {
        replaceCharacters(in: [range], with: string)
    }

    private func replaceCharactersNoCheck(in range: NSRange, with string: String) {
        textStorage.replaceCharacters(in: range, with: string)
    }

    // MARK: - Layout

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if isSelectable {
            selectionManager.drawSelections(in: dirtyRect)
        }
    }

    override open var isFlipped: Bool {
        true
    }

    override var visibleRect: NSRect {
        if let scrollView = scrollView {
            var rect = scrollView.documentVisibleRect
            rect.origin.y += scrollView.contentInsets.top
            rect.size.height -= scrollView.contentInsets.top + scrollView.contentInsets.bottom
            return rect
        } else {
            return super.visibleRect
        }
    }

    var visibleTextRange: NSRange? {
        let minY = max(visibleRect.minY, 0)
        let maxY = min(visibleRect.maxY, layoutManager.estimatedHeight())
        guard let minYLine = layoutManager.textLineForPosition(minY),
              let maxYLine = layoutManager.textLineForPosition(maxY) else {
            return nil
        }
        return NSRange(
            location: minYLine.range.location,
            length: (maxYLine.range.location - minYLine.range.location) + maxYLine.range.length
        )
    }

    public func updatedViewport(_ newRect: CGRect) {
        if !updateFrameIfNeeded() {
            layoutManager.layoutLines()
        }
        inputContext?.invalidateCharacterCoordinates()
    }

    @discardableResult
    public func updateFrameIfNeeded() -> Bool {
        var availableSize = scrollView?.contentSize ?? .zero
        availableSize.height -= (scrollView?.contentInsets.top ?? 0) + (scrollView?.contentInsets.bottom ?? 0)
        let newHeight = layoutManager.estimatedHeight()
        let newWidth = layoutManager.estimatedWidth()

        var didUpdate = false

        if newHeight + editorOverscroll >= availableSize.height && frame.size.height != newHeight + editorOverscroll {
            frame.size.height = newHeight + editorOverscroll
            // No need to update layout after height adjustment
        }

        if wrapLines && frame.size.width != availableSize.width {
            frame.size.width = availableSize.width
            didUpdate = true
        } else if !wrapLines && frame.size.width != max(newWidth, availableSize.width) {
            frame.size.width = max(newWidth, availableSize.width)
            didUpdate = true
        }

        if didUpdate {
            needsLayout = true
            needsDisplay = true
            layoutManager.layoutLines()
        }

        if isSelectable {
            selectionManager?.updateSelectionViews()
        }

        return didUpdate
    }

    deinit {
        layoutManager = nil
        selectionManager = nil
        textStorage = nil
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - TextLayoutManagerDelegate

extension TextView: TextLayoutManagerDelegate {
    func layoutManagerHeightDidUpdate(newHeight: CGFloat) {
        updateFrameIfNeeded()
    }

    func layoutManagerMaxWidthDidChange(newWidth: CGFloat) {
        updateFrameIfNeeded()
    }

    func textViewSize() -> CGSize {
        if let scrollView = scrollView {
            var size = scrollView.contentSize
            size.height -= scrollView.contentInsets.top + scrollView.contentInsets.bottom
            return size
        } else {
            return CGSize(width: CGFloat.infinity, height: CGFloat.infinity)
        }
    }

    func textLayoutSetNeedsDisplay() {
        needsDisplay = true
        needsLayout = true
    }

    func layoutManagerYAdjustment(_ yAdjustment: CGFloat) {
        var point = scrollView?.documentVisibleRect.origin ?? .zero
        point.y += yAdjustment
        scrollView?.documentView?.scroll(point)
    }
}

// MARK: - TextSelectionManagerDelegate

extension TextView: TextSelectionManagerDelegate {
    func setNeedsDisplay() {
        self.setNeedsDisplay(visibleRect)
    }

    func estimatedLineHeight() -> CGFloat {
        layoutManager.estimateLineHeight()
    }
}
