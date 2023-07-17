//
//  TextViewController.swift
//  
//
//  Created by Khan Winter on 6/25/23.
//

import AppKit
import CodeEditLanguages
import SwiftUI
import SwiftTreeSitter

public class TextViewController: NSViewController {
    var scrollView: NSScrollView!
    var textView: TextView!

    public var string: Binding<String>
    public var language: CodeLanguage
    public var font: NSFont
    public var theme: EditorTheme
    public var lineHeight: CGFloat
    public var wrapLines: Bool
    public var cursorPosition: Binding<(Int, Int)>
    public var editorOverscroll: CGFloat
    public var useThemeBackground: Bool
    public var highlightProvider: HighlightProviding?
    public var contentInsets: NSEdgeInsets?
    public var isEditable: Bool
    public var letterSpacing: Double
    public var bracketPairHighlight: BracketPairHighlight?

    private var storageDelegate: MultiStorageDelegate!
    private var highlighter: Highlighter?

    init(
        string: Binding<String>,
        language: CodeLanguage,
        font: NSFont,
        theme: EditorTheme,
        tabWidth: Int,
        indentOption: IndentOption,
        lineHeight: CGFloat,
        wrapLines: Bool,
        cursorPosition: Binding<(Int, Int)>,
        editorOverscroll: CGFloat,
        useThemeBackground: Bool,
        highlightProvider: HighlightProviding?,
        contentInsets: NSEdgeInsets?,
        isEditable: Bool,
        letterSpacing: Double,
        bracketPairHighlight: BracketPairHighlight?
    ) {
        self.string = string
        self.language = language
        self.font = font
        self.theme = theme
        self.lineHeight = lineHeight
        self.wrapLines = wrapLines
        self.cursorPosition = cursorPosition
        self.editorOverscroll = editorOverscroll
        self.useThemeBackground = useThemeBackground
        self.highlightProvider = highlightProvider
        self.contentInsets = contentInsets
        self.isEditable = isEditable
        self.letterSpacing = letterSpacing
        self.bracketPairHighlight = bracketPairHighlight

        self.storageDelegate = MultiStorageDelegate()

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func loadView() {
        scrollView = NSScrollView()
        textView = TextView(
            string: string.wrappedValue,
            font: font,
            lineHeight: lineHeight,
            wrapLines: wrapLines,
            editorOverscroll: editorOverscroll,
            isEditable: isEditable,
            letterSpacing: letterSpacing,
            storageDelegate: storageDelegate
        )
        textView.translatesAutoresizingMaskIntoConstraints = false

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.contentView.postsFrameChangedNotifications = true
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalRuler = true
        scrollView.documentView = textView
        if let contentInsets {
            scrollView.automaticallyAdjustsContentInsets = false
            scrollView.contentInsets = contentInsets
        }

        self.view = scrollView

        setUpHighlighter()

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { _ in
            self.textView.updateFrameIfNeeded()
        }
    }

    override public func viewWillAppear() {
        highlighter?.invalidate()
    }
}

extension TextViewController: ThemeAttributesProviding {
    public func attributesFor(_ capture: CaptureName?) -> [NSAttributedString.Key: Any] {
        [
            .font: font,
            .foregroundColor: theme.colorFor(capture),
//            .baselineOffset: baselineOffset,
//            .paragraphStyle: paragraphStyle,
//            .kern: kern
        ]
    }
}

extension TextViewController {
    private func setUpHighlighter() {
        self.highlighter = Highlighter(
            textView: textView,
            highlightProvider: highlightProvider,
            theme: theme,
            attributeProvider: self,
            language: language
        )
        storageDelegate.addDelegate(highlighter!)
        setHighlightProvider(self.highlightProvider)
    }

    internal func setHighlightProvider(_ highlightProvider: HighlightProviding? = nil) {
        var provider: HighlightProviding?

        if let highlightProvider = highlightProvider {
            provider = highlightProvider
        } else {
            let textProvider: ResolvingQueryCursor.TextProvider = { [weak self] range, _ -> String? in
                return self?.textView.textStorage.mutableString.substring(with: range)
            }

            provider = TreeSitterClient(textProvider: textProvider)
        }

        if let provider = provider {
            self.highlightProvider = provider
            highlighter?.setHighlightProvider(provider)
        }
    }
}
