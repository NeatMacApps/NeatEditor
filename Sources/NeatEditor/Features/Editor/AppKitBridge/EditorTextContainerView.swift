import AppKit

enum EditorSearchOutcome: Equatable, Sendable {
    case matches([NSRange])
    case timedOut
    case cancelled
}

/// The deadline includes time spent waiting behind the previous evaluation.
typealias EditorSearchEvaluator = @Sendable (
    _ pattern: String, _ text: String, _ deadline: ContinuousClock.Instant
) async -> EditorSearchOutcome

private func evaluateRegularExpressionOffMain(
    _ pattern: String,
    _ text: String,
    _ deadline: ContinuousClock.Instant
) async -> EditorSearchOutcome {
    guard !Task.isCancelled else { return .cancelled }
    guard ContinuousClock.now < deadline else { return .timedOut }
    guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
        return .matches([])
    }
    var ranges: [NSRange] = []
    var stopped: EditorSearchOutcome?
    // Progress callbacks run even during a single backtracking match, unlike
    // checking cancellation only between completed matches.
    regex.enumerateMatches(
        in: text, options: .reportProgress,
        range: NSRange(location: 0, length: text.utf16.count)
    ) { match, _, stop in
        if Task.isCancelled {
            stopped = .cancelled
        } else if ContinuousClock.now >= deadline {
            stopped = .timedOut
        }
        if stopped != nil {
            stop.pointee = true
        } else if let match {
            ranges.append(match.range)
        }
    }
    return stopped ?? .matches(ranges)
}

final class EditorTextContainerView: NSView {
    let textView: ZoomableTextView

    var theme: EditorTheme = .defaultValue {
        didSet {
            guard theme != oldValue else { return }
            updateTextViewColors()
            lineNumberView.theme = theme
        }
    }

    private static let editorLineHeightMultiple: CGFloat = 1.08
    private static let searchHighlightColor = NSColor.controlAccentColor.withAlphaComponent(0.22)
    private var currentEditorFontSize: CGFloat = NSFont.systemFontSize
    var textSoftness = WorkspacePreferences.EditorTextSoftnessConfiguration() {
        didSet {
            guard textSoftness != oldValue else {
                return
            }

            updateTextViewColors()
            applyDefaultTypingAttributes(using: editorMonospacedFont())
        }
    }

    var onIncreaseFontSize: () -> Void {
        didSet {
            textView.onIncreaseFontSize = onIncreaseFontSize
        }
    }

    var onDecreaseFontSize: () -> Void {
        didSet {
            textView.onDecreaseFontSize = onDecreaseFontSize
        }
    }

    /// Published when the current regular-expression evaluation times out
    /// (`true`) or completes (`false`); the search bar shows a short status on
    /// timeout instead of freezing.
    var onSearchTimeoutChange: (Bool) -> Void = { _ in }

    /// Off-main evaluator used for regular-expression searches. Tests inject
    /// instant, slow or externally controlled evaluators here.
    var searchEvaluator: EditorSearchEvaluator = evaluateRegularExpressionOffMain

    private let scrollView: EditorScrollView
    private let lineNumberView: LineNumberGutterView
    private let separatorView = NSView()
    private var gutterWidthConstraint: NSLayoutConstraint?

    // Cached "last applied" values short-circuit the high-frequency SwiftUI
    // updateNSView path. Reassigning NSTextView.textColor or rewriting
    // typingAttributes triggers a full text-storage re-attribution and
    // dictionary copy-on-write — repeating that on every redraw was a
    // significant CPU/allocation source under sustained load.
    private var appliedTypingAttributesFont: NSFont?
    private var appliedTypingAttributesForegroundColor: NSColor?
    private var appliedTextColor: NSColor?
    private var appliedBackgroundColor: NSColor?
    private var appliedInsertionPointColor: NSColor?
    // Last-applied gutter width. The gutter posts `refreshLineNumbers` on
    // every keystroke (and the coordinator posts it again for the same edit);
    // rewriting an unchanged width constraint would dirty layout each time.
    private var appliedGutterWidth: CGFloat?

    /// Deadline for one off-main regex evaluation. 250 ms keeps keystroke
    /// feedback responsive while still covering ordinary patterns on large
    /// documents.
    private static let regularExpressionSearchDeadline: Duration = .milliseconds(250)

    /// Limit painting, never navigation through the complete match set.
    private static let maximumAppliedMatchCount = 2000

    private struct SearchRequest: Sendable {
        let pattern: String
        let text: String
        let navigate: Bool
        let generation: Int
        let deadline: ContinuousClock.Instant
        let evaluator: EditorSearchEvaluator
    }

    /// Keep the running handle until its evaluator really ends. Replacing only
    /// the pending slot bounds retained work even if cancellation is ignored.
    private var searchTask: Task<Void, Never>?
    private var searchDeadlineTask: Task<Void, Never>?
    private var pendingSearch: SearchRequest?
    private var searchRequestGeneration = 0

    var retainedRegularExpressionRequestCount: Int {
        (searchTask == nil ? 0 : 1) + (pendingSearch == nil ? 0 : 1)
    }

    override var isFlipped: Bool {
        true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateTextViewColors()
        applyDefaultTypingAttributes(using: editorMonospacedFont())
        updateSeparatorColor()
        lineNumberView.updateColors()
    }

    init(
        onIncreaseFontSize: @escaping () -> Void = {},
        onDecreaseFontSize: @escaping () -> Void = {}
    ) {
        // TextKit 1 leaves stale last-line pixels during incremental edits.
        // Build the native TextKit 2 network instead; never read the legacy
        // `layoutManager` getter, which would silently switch this view back.
        let textView = ZoomableTextView(usingTextLayoutManager: true)
        let scrollView = EditorScrollView(frame: .zero)
        let contentView = NSClipView()

        contentView.drawsBackground = false
        scrollView.contentView = contentView
        scrollView.documentView = textView
        self.scrollView = scrollView
        self.textView = textView
        self.lineNumberView = LineNumberGutterView(scrollView: scrollView, textView: textView)
        self.onIncreaseFontSize = onIncreaseFontSize
        self.onDecreaseFontSize = onDecreaseFontSize

        super.init(frame: .zero)
        self.focusRingType = .none

        configureTextView()
        configureScrollView()
        configureLayout()
        self.textView.onIncreaseFontSize = onIncreaseFontSize
        self.textView.onDecreaseFontSize = onDecreaseFontSize
        refreshLineNumbers()
        LaunchProfiler.recordEditorReady()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        searchTask?.cancel()
        searchDeadlineTask?.cancel()
    }

    func refreshLineNumbers() {
        let gutterWidth = lineNumberView.requiredWidth
        if appliedGutterWidth != gutterWidth {
            gutterWidthConstraint?.constant = gutterWidth
            appliedGutterWidth = gutterWidth
        }
        lineNumberView.needsDisplay = true
    }

    func synchronizeLineNumbersToCurrentText() {
        lineNumberView.synchronizeLineMetrics()
        refreshLineNumbers()
    }

    func applyFontSize(_ fontSize: CGFloat) {
        currentEditorFontSize = fontSize
        let font = editorMonospacedFont()
        let didChangeFont = textView.font?.fontName != font.fontName
            || textView.font?.pointSize != font.pointSize

        if didChangeFont {
            textView.font = font
            refreshLineNumbers()
        }

        applyDefaultTypingAttributes(using: font)
    }

    func applyEditorTextAttributes() {
        textView.font = editorMonospacedFont()
        updateTextViewColors()
        applyDefaultTypingAttributes(using: editorMonospacedFont())
        refreshLineNumbers()
    }

    func prepareTypingAttributes(for replacementString: String?) {
        _ = replacementString
        applyDefaultTypingAttributes(using: editorMonospacedFont())
    }

    func performSearch(for query: String, usesRegularExpression: Bool, navigate: Bool = true) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            clearSearchHighlights()
            return
        }

        let fullText = textView.string
        guard !fullText.isEmpty else {
            clearSearchHighlights()
            scheduleTimeoutStatusReset()
            if navigate { NSSound.beep() }
            return
        }

        guard usesRegularExpression else {
            // Literal search is a cheap native scan; keep it synchronous.
            cancelPendingSearch()
            finishSearch(
                with: literalSearchRanges(for: trimmedQuery, in: fullText),
                navigate: navigate
            )
            return
        }

        beginRegularExpressionSearch(pattern: trimmedQuery, text: fullText, navigate: navigate)
    }

    private func beginRegularExpressionSearch(pattern: String, text: String, navigate: Bool) {
        cancelPendingSearch()
        let generation = searchRequestGeneration
        let deadline = ContinuousClock.now.advanced(by: Self.regularExpressionSearchDeadline)
        pendingSearch = SearchRequest(
            pattern: pattern, text: text, navigate: navigate,
            generation: generation, deadline: deadline, evaluator: searchEvaluator
        )
        searchDeadlineTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(until: deadline, clock: .continuous)
            } catch {
                return
            }
            guard !Task.isCancelled, let self,
                  self.searchRequestGeneration == generation else { return }
            self.applySearchOutcome(.timedOut, navigate: false)
        }
        startPendingSearchIfNeeded()
    }

    private func startPendingSearchIfNeeded() {
        guard searchTask == nil, let request = pendingSearch else { return }
        pendingSearch = nil
        searchTask = Task { @MainActor [weak self] in
            let evaluation = Task.detached(priority: .userInitiated) {
                await request.evaluator(request.pattern, request.text, request.deadline)
            }
            let outcome = await withTaskCancellationHandler {
                await evaluation.value
            } onCancel: {
                evaluation.cancel()
            }
            guard let self else { return }
            self.searchTask = nil
            if !Task.isCancelled, self.searchRequestGeneration == request.generation {
                self.searchDeadlineTask?.cancel()
                self.searchDeadlineTask = nil
                self.applySearchOutcome(outcome, navigate: request.navigate)
            }
            self.startPendingSearchIfNeeded()
        }
    }

    private func cancelPendingSearch() {
        searchRequestGeneration &+= 1
        pendingSearch = nil
        searchDeadlineTask?.cancel()
        searchDeadlineTask = nil
        searchTask?.cancel()
    }

    /// Clears a reported timeout once no evaluation can match anything. The
    /// status lives in observable workspace state, so it is reset off the
    /// current view update rather than during one.
    private func scheduleTimeoutStatusReset() {
        Task { @MainActor [weak self] in
            self?.onSearchTimeoutChange(false)
        }
    }

    private func applySearchOutcome(_ outcome: EditorSearchOutcome, navigate: Bool) {
        switch outcome {
        case .timedOut:
            // A pathological pattern is not a missing match: clear stale
            // highlights, skip the beep, and let the search bar report it.
            clearSearchHighlights()
            onSearchTimeoutChange(true)
        case .matches(let matchRanges):
            onSearchTimeoutChange(false)
            finishSearch(with: matchRanges, navigate: navigate)
        case .cancelled:
            break
        }
    }

    private func finishSearch(with matchRanges: [NSRange], navigate: Bool) {
        guard !matchRanges.isEmpty else {
            clearSearchHighlights()
            if navigate { NSSound.beep() }
            return
        }

        let appliedRanges = Array(matchRanges.prefix(Self.maximumAppliedMatchCount))
        applySearchHighlights(for: appliedRanges)

        guard navigate else { return }

        let textLength = (textView.string as NSString).length
        let selectedRange = textView.selectedRange()
        let selectionEnd = selectedRange.location == NSNotFound
            ? 0
            : min(NSMaxRange(selectedRange), textLength)
        let matchRange = NSIntersectionRange(
            nextMatchRange(from: matchRanges, selectionEnd: selectionEnd),
            NSRange(location: 0, length: textLength)
        )

        textView.window?.makeFirstResponder(textView)
        textView.setSelectedRange(matchRange)
        textView.scrollRangeToVisible(matchRange)
    }

    private func literalSearchRanges(
        for query: String,
        in fullText: String
    ) -> [NSRange] {
        let nsText = fullText as NSString
        let searchOptions: NSString.CompareOptions = [.caseInsensitive]
        var searchRange = NSRange(location: 0, length: nsText.length)
        var matchRanges: [NSRange] = []

        while searchRange.length > 0 {
            let matchRange = nsText.range(
                of: query,
                options: searchOptions,
                range: searchRange
            )

            guard matchRange.location != NSNotFound else {
                break
            }

            matchRanges.append(matchRange)

            let nextLocation = NSMaxRange(matchRange)
            guard nextLocation < nsText.length else {
                break
            }

            searchRange = NSRange(
                location: nextLocation,
                length: nsText.length - nextLocation
            )
        }

        return matchRanges
    }

    private func nextMatchRange(from matchRanges: [NSRange], selectionEnd: Int) -> NSRange {
        if let nextMatch = matchRanges.first(where: { $0.location >= selectionEnd }) {
            return nextMatch
        }

        return matchRanges[0]
    }

    private func applySearchHighlights(for matchRanges: [NSRange]) {
        guard let textStorage = textView.textStorage else {
            return
        }

        // TextKit 2 rendering attributes do not repaint reliably
        // (FB9692714), so store the transient search colors as regular text
        // attributes. The editor is plain text; the string is what gets saved,
        // and attribute-only edits are not registered with the undo manager.
        textStorage.beginEditing()
        textStorage.removeAttribute(
            .backgroundColor,
            range: NSRange(location: 0, length: textStorage.length)
        )

        for matchRange in matchRanges {
            let clampedRange = NSIntersectionRange(
                matchRange,
                NSRange(location: 0, length: textStorage.length)
            )
            guard clampedRange.length > 0 else {
                continue
            }

            textStorage.addAttribute(
                .backgroundColor,
                value: Self.searchHighlightColor,
                range: clampedRange
            )
        }
        textStorage.endEditing()
        textView.needsDisplay = true
    }

    func clearSearchHighlights() {
        // Dismissing the bar, switching tabs or an empty result supersedes any
        // in-flight regex evaluation; its late ranges must not repaint.
        cancelPendingSearch()
        guard let textStorage = textView.textStorage else {
            return
        }

        textStorage.beginEditing()
        textStorage.removeAttribute(
            .backgroundColor,
            range: NSRange(location: 0, length: textStorage.length)
        )
        textStorage.endEditing()
        textView.needsDisplay = true
    }

    /// Re-apply the current search highlights after the buffer changed
    /// (typing, composition commit, external push) without moving the
    /// selection. Edits shift match ranges, so stale temporary attributes
    /// would otherwise highlight the wrong text.
    func reapplySearchHighlightsIfNeeded(
        query: String,
        usesRegularExpression: Bool,
        isPresented: Bool
    ) {
        guard isPresented,
              !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        performSearch(
            for: query,
            usesRegularExpression: usesRegularExpression,
            navigate: false
        )
    }

    private func configureTextView() {
        currentEditorFontSize = NSFont.systemFontSize
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFindPanel = true
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.font = editorMonospacedFont()
        textView.drawsBackground = true
        textView.bottomScrollPadding = EditorCharacterCountLayout.scrollableBottomInset
        textView.textContainerInset = NSSize(
            width: 8, height: 8 + textView.bottomScrollPadding / 2
        )
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.minSize = NSSize(width: 0, height: 0)
        textView.autoresizingMask = [.width]
        textView.focusRingType = .none
        updateTextViewColors()
        applyDefaultTypingAttributes(using: editorMonospacedFont())

        if let textContainer = textView.textContainer {
            textContainer.widthTracksTextView = true
            textContainer.containerSize = NSSize(
                width: 0,
                height: CGFloat.greatestFiniteMagnitude
            )
        }
    }

    private static func editorFont(ofSize size: CGFloat) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    private func editorMonospacedFont() -> NSFont {
        Self.editorFont(ofSize: currentEditorFontSize)
    }

    private func applyDefaultTypingAttributes(using font: NSFont) {
        // A caret inside a search match must not start inheriting the
        // transient background color for newly typed characters.
        textView.typingAttributes.removeValue(forKey: .backgroundColor)

        let foregroundColor = editorForegroundColor()
        if appliedTypingAttributesFont == font,
           appliedTypingAttributesForegroundColor == foregroundColor {
            return
        }

        let paragraphStyle = Self.sharedEditorParagraphStyle
        textView.defaultParagraphStyle = paragraphStyle
        textView.typingAttributes[.font] = font
        textView.typingAttributes[.paragraphStyle] = paragraphStyle
        textView.typingAttributes[.foregroundColor] = foregroundColor

        appliedTypingAttributesFont = font
        appliedTypingAttributesForegroundColor = foregroundColor
    }

    private static let sharedEditorParagraphStyle: NSParagraphStyle = {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineHeightMultiple = editorLineHeightMultiple
        return paragraphStyle
    }()

    private func editorForegroundColor() -> NSColor {
        Self.editorForegroundColor(
            for: effectiveAppearance,
            textSoftness: textSoftness
        )
    }

    private static func editorForegroundColor(
        for appearance: NSAppearance,
        textSoftness: WorkspacePreferences.EditorTextSoftnessConfiguration
    ) -> NSColor {
        let blendFraction: CGFloat

        switch appearance.bestMatch(from: [
            .accessibilityHighContrastDarkAqua,
            .darkAqua,
            .accessibilityHighContrastAqua,
            .aqua
        ]) {
        case .accessibilityHighContrastDarkAqua, .accessibilityHighContrastAqua:
            blendFraction = textSoftness.highContrastTextSoftness.clamped(to: 0...1)
        case .darkAqua:
            blendFraction = textSoftness.darkModeTextSoftness.clamped(to: 0...1)
        default:
            blendFraction = textSoftness.lightModeTextSoftness.clamped(to: 0...1)
        }

        var blendedColor = NSColor.labelColor
        appearance.performAsCurrentDrawingAppearance {
            let baseColor = NSColor.labelColor
            let softenedColor = NSColor.secondaryLabelColor
            blendedColor = baseColor.blended(withFraction: blendFraction, of: softenedColor) ?? baseColor
        }

        return blendedColor
    }

    private func configureScrollView() {
        wantsLayer = true
        layer?.masksToBounds = true

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        // Keep the thin, auto-hiding knob even if the system prefers legacy
        // scrollers; the editor must not reserve a permanent scrollbar column.
        scrollView.scrollerStyle = .overlay
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.focusRingType = .none
    }

    private func configureLayout() {
        lineNumberView.translatesAutoresizingMaskIntoConstraints = false
        separatorView.translatesAutoresizingMaskIntoConstraints = false
        separatorView.wantsLayer = true
        updateSeparatorColor()

        addSubview(lineNumberView)
        addSubview(separatorView)
        addSubview(scrollView)

        let gutterWidthConstraint = lineNumberView.widthAnchor.constraint(
            equalToConstant: lineNumberView.requiredWidth
        )
        self.gutterWidthConstraint = gutterWidthConstraint
        self.appliedGutterWidth = lineNumberView.requiredWidth

        NSLayoutConstraint.activate([
            lineNumberView.leadingAnchor.constraint(equalTo: leadingAnchor),
            lineNumberView.topAnchor.constraint(equalTo: topAnchor),
            lineNumberView.bottomAnchor.constraint(equalTo: bottomAnchor),
            gutterWidthConstraint,

            separatorView.leadingAnchor.constraint(equalTo: lineNumberView.trailingAnchor),
            separatorView.topAnchor.constraint(equalTo: topAnchor),
            separatorView.bottomAnchor.constraint(equalTo: bottomAnchor),
            separatorView.widthAnchor.constraint(equalToConstant: EditorChrome.lineWidth),

            scrollView.leadingAnchor.constraint(equalTo: separatorView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func updateSeparatorColor() {
        separatorView.layer?.backgroundColor = LineNumberGutterView.separatorColor.cgColor
    }

    private func updateTextViewColors() {
        let foregroundColor = Self.editorForegroundColor(
            for: effectiveAppearance,
            textSoftness: textSoftness
        )
        let backgroundColor = EditorChrome.resolvedColor(EditorChrome.editorSurfaceColor(for: theme), for: effectiveAppearance)
        let insertionPointColor = NSColor.labelColor

        // Reassigning textColor walks the entire NSTextStorage to re-attribute
        // every glyph. Skip the round-trip when the value is unchanged.
        if appliedTextColor != foregroundColor {
            textView.textColor = foregroundColor
            appliedTextColor = foregroundColor
        }
        if appliedBackgroundColor != backgroundColor {
            textView.backgroundColor = backgroundColor
            appliedBackgroundColor = backgroundColor
        }
        if appliedInsertionPointColor != insertionPointColor {
            textView.insertionPointColor = insertionPointColor
            appliedInsertionPointColor = insertionPointColor
        }
    }
}
