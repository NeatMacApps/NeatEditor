import AppKit

/// Forwards `NSTextStorage` character edits to the gutter's incremental line
/// index. `NSView` subclasses are `@MainActor`-isolated in this SDK, but the
/// `NSTextStorageDelegate` witness must be nonisolated, so the conformance
/// lives on this plain `NSObject` instead of on `LineNumberGutterView`
/// (same split as `Coordinator` and its text view). Main-thread-only by
/// construction: AppKit invokes storage delegates on the editing thread
/// (guarded below), and the gutter link is set from the view's own
/// main-thread setup path, so the unchecked conformance is sound.
private final class GutterStorageDelegate: NSObject, NSTextStorageDelegate, @unchecked Sendable {
    weak var gutter: LineNumberGutterView?

    func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        // AppKit drives storage delegates on the main thread. If that ever
        // changes, skip the incremental path: the next `ensure` on the main
        // thread sees the length mismatch and falls back to a full rebuild.
        guard Thread.isMainThread else {
            return
        }
        let isCharacterEdit = editedMask.contains(.editedCharacters)
        MainActor.assumeIsolated {
            gutter?.handleStorageEdit(
                range: editedRange,
                changeInLength: delta,
                isCharacterEdit: isCharacterEdit
            )
        }
    }
}

final class LineNumberGutterView: NSView {
    enum Metrics {
        static let minimumDigits = 3
        static let leftPadding: CGFloat = 7
        static let rightPadding: CGFloat = 5
        static let fontScale: CGFloat = 0.85
        static let minimumFontSize: CGFloat = 10
    }

    private weak var scrollView: NSScrollView?
    private weak var textView: NSTextView?
    private var lineStartIndices = [0]
    private var cachedLineCount = 1
    // Incremental line-index bookkeeping. The gutter observes character edits
    // through the storage delegate and only rescans from the edited line,
    // resynchronizing onto the shifted suffix instead of walking the whole
    // document on every keystroke. `indexedLength` is the UTF-16 length the
    // index was built for; `observedStorage` detects a replaced storage so a
    // missed edit can never leave a stale index behind.
    private weak var observedStorage: NSTextStorage?
    private var indexedLength = 0

    override var isFlipped: Bool {
        true
    }

    var requiredWidth: CGFloat {
        let digits = max(Metrics.minimumDigits, String(cachedLineCount).count)
        let sample = String(repeating: "8", count: digits) as NSString
        let width = ceil(sample.size(withAttributes: textAttributes).width)
        return Metrics.leftPadding + width + Metrics.rightPadding
    }

    init(scrollView: NSScrollView, textView: NSTextView) {
        self.scrollView = scrollView
        self.textView = textView
        super.init(frame: .zero)
        wantsLayer = true
        rebuildLineMetrics()
        updateColors()
        registerObservers(scrollView: scrollView, textView: textView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    override func scrollWheel(with event: NSEvent) {
        guard let scrollView else {
            super.scrollWheel(with: event)
            return
        }

        scrollView.scrollWheel(with: event)
    }

    struct RenderedLine: Equatable {
        let number: Int
        let y: CGFloat
        let height: CGFloat
    }

    override func draw(_ dirtyRect: NSRect) {
        EditorChrome.editorSurfaceColor.setFill()
        dirtyRect.fill()

        guard let scrollView else {
            return
        }

        for line in renderedLines(in: scrollView.contentView.bounds) {
            drawLineNumber(line.number, atY: line.y, lineHeight: line.height)
        }
    }

    /// Resolve the gutter entries for the current viewport using modern text
    /// layout fragments. Logical line starts come from the existing line index,
    /// so wrapped continuations do not receive their own numbers.
    func renderedLines(in visibleRect: NSRect) -> [RenderedLine] {
        guard let textView,
              let textLayoutManager = textView.textLayoutManager,
              let contentManager = textLayoutManager.textContentManager else {
            return []
        }

        let origin = textView.textContainerOrigin
        guard (textView.string as NSString).length > 0 else {
            return [
                RenderedLine(
                    number: 1,
                    y: origin.y,
                    height: editorLineHeight(for: textView)
                )
            ]
        }

        let containerTop = max(0, visibleRect.minY - origin.y)
        let containerBounds = CGRect(
            x: 0,
            y: containerTop,
            width: max(1, textView.bounds.width - origin.x * 2),
            height: max(1, visibleRect.height)
        )
        textLayoutManager.ensureLayout(for: containerBounds)

        let startLocation = textLayoutManager.textLayoutFragment(
            for: CGPoint(x: 0, y: containerTop)
        )?.rangeInElement.location ?? contentManager.documentRange.location

        var renderedLines: [RenderedLine] = []

        textLayoutManager.enumerateTextLayoutFragments(
            from: startLocation,
            options: [.ensuresLayout, .ensuresExtraLineFragment]
        ) { fragment in
            let fragmentFrame = fragment.layoutFragmentFrame.offsetBy(
                dx: origin.x,
                dy: origin.y
            )
            guard fragmentFrame.minY <= visibleRect.maxY else {
                return false
            }

            let fragmentStart = contentManager.offset(
                from: contentManager.documentRange.location,
                to: fragment.rangeInElement.location
            )

            for textLineFragment in fragment.textLineFragments {
                let lineFrame = textLineFragment.typographicBounds.offsetBy(
                    dx: fragmentFrame.minX,
                    dy: fragmentFrame.minY
                )
                guard lineFrame.minY <= visibleRect.maxY else {
                    break
                }
                guard lineFrame.maxY >= visibleRect.minY else {
                    continue
                }

                let lineStart = fragmentStart + textLineFragment.characterRange.location
                guard let number = lineNumberIfStart(at: lineStart) else {
                    continue
                }

                renderedLines.append(
                    RenderedLine(
                        number: number,
                        y: lineFrame.minY - visibleRect.minY,
                        height: lineFrame.height
                    )
                )
            }

            return true
        }

        return renderedLines
    }

    @objc
    private func handleTextDidChange() {
        ensureLineMetricsCurrent()
        needsDisplay = true
        superview.flatMap { $0 as? EditorTextContainerView }?.refreshLineNumbers()
    }

    @objc
    private func handleScrollBoundsDidChange() {
        needsDisplay = true
    }

    func updateColors() {
        layer?.backgroundColor = EditorChrome.resolvedColor(
            EditorChrome.editorSurfaceColor, for: effectiveAppearance
        ).cgColor
        needsDisplay = true
    }

    func synchronizeLineMetrics() {
        ensureLineMetricsCurrent()
        needsDisplay = true
    }

    static var separatorColor: NSColor {
        EditorChrome.borderColor
    }

    private func registerObservers(scrollView: NSScrollView, textView: NSTextView) {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTextDidChange),
            name: NSText.didChangeNotification,
            object: textView
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScrollBoundsDidChange),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        attachStorageDelegate()
    }

    // MARK: - Incremental line index

    private let storageDelegate = GutterStorageDelegate()

    /// Character edits arrive here synchronously, before
    /// `NSText.didChangeNotification`. Attribute-only edits (search
    /// highlights) carry no character change and leave line structure
    /// untouched, so they are ignored.
    func handleStorageEdit(
        range editedRange: NSRange,
        changeInLength delta: Int,
        isCharacterEdit: Bool
    ) {
        guard isCharacterEdit else {
            return
        }
        if let storage = textView?.textStorage {
            observedStorage = storage
        }
        if !applyIncrementalLineEdit(editedRange: editedRange, changeInLength: delta) {
            rebuildLineMetrics()
        }
    }

    /// Fast path shared by the keystroke notification and the push/rebind
    /// entry point. The delegate already keeps the index current, so both
    /// only fall back to a full scan when the storage was replaced or an
    /// edit was missed (length mismatch).
    private func ensureLineMetricsCurrent() {
        attachStorageDelegate()
        guard let textView else {
            lineStartIndices = [0]
            cachedLineCount = 1
            indexedLength = 0
            return
        }
        guard let storage = textView.textStorage,
              observedStorage === storage,
              (storage.delegate as? GutterStorageDelegate) === storageDelegate else {
            rebuildLineMetrics()
            return
        }
        if storage.length != indexedLength {
            rebuildLineMetrics()
        }
    }

    private func attachStorageDelegate() {
        storageDelegate.gutter = self
        guard let storage = textView?.textStorage else {
            return
        }
        if observedStorage !== storage || (storage.delegate as? GutterStorageDelegate) !== storageDelegate {
            storage.delegate = storageDelegate
            observedStorage = storage
        }
    }

    /// Rebuild only the index entries at and after the edited line. Entries
    /// before the edit are byte-identical, so they are kept; the rescan stops
    /// as soon as a regenerated line start realigns with a shifted old
    /// entry, and the remaining suffix is carried over with the length delta
    /// instead of being rescanned. Returns false when the old index cannot
    /// be trusted, letting the caller fall back to a full rebuild.
    private func applyIncrementalLineEdit(editedRange: NSRange, changeInLength delta: Int) -> Bool {
        guard let storage = textView?.textStorage else {
            return false
        }
        let string = storage.string as NSString
        let newLength = string.length
        guard newLength > 0 else {
            lineStartIndices = [0]
            cachedLineCount = 1
            indexedLength = 0
            return true
        }
        let editLocation = editedRange.location
        let editLength = editedRange.length
        guard editLocation >= 0,
              editLength >= 0,
              editLocation + editLength <= newLength else {
            return false
        }
        let oldEditEnd = editLocation + editLength - delta
        guard oldEditEnd >= 0, oldEditEnd <= indexedLength else {
            return false
        }
        guard lineStartIndices.first == 0 else {
            return false
        }

        var low = 0
        var high = lineStartIndices.count
        while low < high {
            let mid = (low + high) / 2
            if lineStartIndices[mid] <= editLocation {
                low = mid + 1
            } else {
                high = mid
            }
        }
        let prefixCount = low
        guard prefixCount > 0 else {
            return false
        }

        var suffixLow = 0
        var suffixHigh = lineStartIndices.count
        while suffixLow < suffixHigh {
            let mid = (suffixLow + suffixHigh) / 2
            if lineStartIndices[mid] <= oldEditEnd {
                suffixLow = mid + 1
            } else {
                suffixHigh = mid
            }
        }
        let suffixStart = suffixLow

        var updatedLineStartIndices = Array(lineStartIndices.prefix(prefixCount))
        var lineStart = lineStartIndices[prefixCount - 1]
        let editEnd = editLocation + editLength
        while lineStart < newLength {
            var lineEnd = lineStart
            var contentsEnd = lineStart
            string.getLineStart(
                nil,
                end: &lineEnd,
                contentsEnd: &contentsEnd,
                for: NSRange(location: lineStart, length: 0)
            )
            guard lineEnd > contentsEnd else { break }
            updatedLineStartIndices.append(lineEnd)
            lineStart = lineEnd
            if lineStart > editEnd, suffixStart < lineStartIndices.count {
                if let match = shiftedSuffixIndex(for: lineStart - delta, from: suffixStart) {
                    for oldIndex in (match + 1)..<lineStartIndices.count {
                        updatedLineStartIndices.append(lineStartIndices[oldIndex] + delta)
                    }
                    break
                }
            }
        }

        lineStartIndices = updatedLineStartIndices
        cachedLineCount = max(1, updatedLineStartIndices.count)
        indexedLength = newLength
        return true
    }

    /// Binary search for an old line start at or after `start`, returning its
    /// position only on an exact match.
    private func shiftedSuffixIndex(for target: Int, from start: Int) -> Int? {
        var low = start
        var high = lineStartIndices.count
        while low < high {
            let mid = (low + high) / 2
            if lineStartIndices[mid] < target {
                low = mid + 1
            } else {
                high = mid
            }
        }
        guard low < lineStartIndices.count, lineStartIndices[low] == target else {
            return nil
        }
        return low
    }

    private func rebuildLineMetrics() {
        guard let textView else {
            lineStartIndices = [0]
            cachedLineCount = 1
            indexedLength = 0
            return
        }

        let string = textView.string as NSString
        guard string.length > 0 else {
            lineStartIndices = [0]
            cachedLineCount = 1
            indexedLength = 0
            return
        }

        var updatedLineStartIndices = [0]
        var lineStart = 0
        while lineStart < string.length {
            var lineEnd = lineStart
            var contentsEnd = lineStart
            string.getLineStart(
                nil,
                end: &lineEnd,
                contentsEnd: &contentsEnd,
                for: NSRange(location: lineStart, length: 0)
            )
            guard lineEnd > contentsEnd else { break }
            updatedLineStartIndices.append(lineEnd)
            lineStart = lineEnd
        }

        lineStartIndices = updatedLineStartIndices
        cachedLineCount = max(1, updatedLineStartIndices.count)
        indexedLength = string.length
    }

    private var textAttributes: [NSAttributedString.Key: Any] {
        guard let textView else {
            return [:]
        }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .right

        return [
            .font: font(for: textView),
            .foregroundColor: Self.gutterColor,
            .paragraphStyle: paragraphStyle
        ]
    }

    private static var gutterColor: NSColor {
        NSColor.quaternaryLabelColor.blended(
            withFraction: 0.5,
            of: NSColor.tertiaryLabelColor.withAlphaComponent(0.75)
        ) ?? NSColor.tertiaryLabelColor.withAlphaComponent(0.6)
    }

    private func font(for textView: NSTextView) -> NSFont {
        let pointSize = textView.font?.pointSize ?? NSFont.systemFontSize
        let gutterPointSize = max(Metrics.minimumFontSize, pointSize * Metrics.fontScale)
        return .monospacedDigitSystemFont(ofSize: gutterPointSize, weight: .regular)
    }

    private func drawLineNumber(_ lineNumber: Int, atY y: CGFloat, lineHeight: CGFloat) {
        let label = String(lineNumber) as NSString
        let labelSize = label.size(withAttributes: textAttributes)
        let rect = NSRect(
            x: Metrics.leftPadding,
            y: y + max(0, lineHeight - labelSize.height),
            width: bounds.width - Metrics.leftPadding - Metrics.rightPadding,
            height: labelSize.height
        )
        label.draw(in: rect, withAttributes: textAttributes)
    }

    private func editorLineHeight(for textView: NSTextView) -> CGFloat {
        let font = textView.font
            ?? .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        let naturalHeight = font.ascender - font.descender + font.leading
        let lineHeightMultiple = textView.defaultParagraphStyle?.lineHeightMultiple ?? 0
        return naturalHeight * (lineHeightMultiple > 0 ? lineHeightMultiple : 1)
    }

    /// Returns a line number only when `characterIndex` starts a logical line.
    /// Wrapped continuation fragments share their paragraph's start offset and
    /// therefore stay unnumbered.
    private func lineNumberIfStart(at characterIndex: Int) -> Int? {
        var low = 0
        var high = lineStartIndices.count

        while low < high {
            let mid = (low + high) / 2
            if lineStartIndices[mid] <= characterIndex {
                low = mid + 1
            } else {
                high = mid
            }
        }

        let index = low - 1
        guard index >= 0, lineStartIndices[index] == characterIndex else {
            return nil
        }

        return index + 1
    }
}
