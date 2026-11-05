import AppKit
import SwiftUI
import Testing

@testable import NeatEditor

@MainActor
struct EditorNewlineTests {
    @Test("document switches retain content until the destination is ready")
    func documentSwitchContinuity() async throws {
        let suite = "NeatEditorSwitchTests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = WorkspaceStore(
            persistenceService: DocumentPersistenceService(
                defaultDirectory: directory,
                appLibraryDirectory: directory.appendingPathComponent("legacy"),
                recoveryDirectory: directory.appendingPathComponent("recovery")
            ),
            userDefaults: defaults
        )
        defer {
            store.pendingSaveStateTask?.cancel()
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let documents = [
            EditorTab(title: "Short.txt", content: "SHORT DOCUMENT\nsecond line"),
            EditorTab(title: "Long.txt", content: String(repeating: "LONG DOCUMENT 中文🙂 wrapped text\n", count: 300)),
            EditorTab(title: "Wrapped.txt", content: String(repeating: "WRAPPED 中文🙂 ", count: 100))
        ]
        store.tabs = documents
        store.selectedTabID = documents[0].id
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 500),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: WorkspaceView()
            .frame(minWidth: 700, minHeight: 470).environment(store))
        window.setContentSize(NSSize(width: 900, height: 500))
        window.orderFront(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(200))
        let original = try #require(findEditor(in: window.contentView))
        for tab in [documents[1], documents[0], documents[2], documents[1], documents[0]] {
            original.scrollRangeToVisible(NSRange(location: original.string.utf16.count, length: 0))
            store.selectTab(tab.id)
            try await Task.sleep(for: .milliseconds(16))
            let editor = try #require(findEditor(in: window.contentView))
            #expect(editor === original)
            #expect(editor.string == tab.content)
            #expect(editor.textLayoutManager?.textViewportLayoutController.viewportRange?.isEmpty == false,
                    "tab=\(tab.title), visible=\(editor.visibleRect), frame=\(editor.frame), selected=\(editor.selectedRange())")
            #expect(editor.visibleRect.width > 0 && editor.visibleRect.height > 0)
        }

        let pending = EditorTab(title: "Pending.txt", isContentLoaded: false)
        store.tabs.append(pending)
        store.loadingTabIDs.insert(pending.id)
        store.selectTab(pending.id)
        try await Task.sleep(for: .milliseconds(40))
        #expect(original.string == documents[0].content)
        #expect(!original.isEditable && !original.isSelectable)
        #expect(!containsProgressIndicator(in: window.contentView))
        #expect(store.tabs.last?.content == "")
        store.commitEditorChanges?(pending.id)
        #expect(store.tabs.last?.content == "")

        // A stale load must not own a later selection; returning to the
        // outgoing document restores native editing without a blank push.
        store.selectTab(documents[0].id)
        try await Task.sleep(for: .milliseconds(40))
        #expect(original.string == documents[0].content)
        #expect(original.isEditable && original.isSelectable)

        original.setSelectedRange(NSRange(location: 0, length: 0))
        original.setMarkedText("pinyin", selectedRange: NSRange(location: 6, length: 0),
                               replacementRange: NSRange(location: 0, length: 0))
        #expect(original.hasMarkedText())
        store.selectTab(pending.id)
        try await Task.sleep(for: .milliseconds(40))
        #expect(!original.hasMarkedText())
        #expect(original.string == documents[0].content)
        #expect(store.tabs.last?.content == "")

        let index = try #require(store.tabs.firstIndex(where: { $0.id == pending.id }))
        store.loadingTabIDs.remove(pending.id)
        store.tabs[index].content = "READY DOCUMENT 中文🙂"
        store.tabs[index].isContentLoaded = true
        try await Task.sleep(for: .milliseconds(40))
        #expect(findEditor(in: window.contentView) === original)
        #expect(original.string == "READY DOCUMENT 中文🙂")
        #expect(original.isEditable && original.isSelectable)
        #expect(original.textLayoutManager != nil)

        let otherPending = EditorTab(title: "Other.txt", isContentLoaded: false)
        let newestPending = EditorTab(title: "Newest.txt", isContentLoaded: false)
        store.tabs += [otherPending, newestPending]
        store.selectTab(otherPending.id)
        try await Task.sleep(for: .milliseconds(40))
        store.selectTab(newestPending.id)
        try await Task.sleep(for: .milliseconds(40))
        let otherIndex = try #require(store.tabs.firstIndex(where: { $0.id == otherPending.id }))
        store.tabs[otherIndex].content = "STALE LOAD"
        store.tabs[otherIndex].isContentLoaded = true
        try await Task.sleep(for: .milliseconds(40))
        #expect(original.string == "READY DOCUMENT 中文🙂")
        #expect(!original.isEditable && !original.isSelectable)
        #expect(original.undoManager?.canUndo != true)
        store.closeDocument(id: newestPending.id)
        try await Task.sleep(for: .milliseconds(40))
        #expect(original.string == "STALE LOAD")
        #expect(original.isEditable && original.isSelectable)
    }

    private func containsProgressIndicator(in view: NSView?) -> Bool {
        guard let view else { return false }
        return view is NSProgressIndicator || view.subviews.contains { containsProgressIndicator(in: $0) }
    }

    private func findEditor(in view: NSView?) -> ZoomableTextView? {
        guard let view else { return nil }
        if let editor = view as? ZoomableTextView { return editor }
        return view.subviews.lazy.compactMap { findEditor(in: $0) }.first
    }

    private func shiftReturn() throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .shift,
            timestamp: 0, windowNumber: 0, context: nil,
            characters: "\r", charactersIgnoringModifiers: "\r",
            isARepeat: false, keyCode: 36
        ))
    }

    @Test("Shift+Enter preserves every native line terminator", arguments: [
        "\n", "\r", "\r\n", "\u{0085}", "\u{2028}", "\u{2029}",
    ])
    func preservesLineTerminator(_ terminator: String) throws {
        let editor = EditorTextContainerView().textView
        let prefix = "a中🙂b"
        editor.string = prefix + terminator + "tail"
        editor.setSelectedRange(NSRange(location: 1, length: 0))

        editor.keyDown(with: try shiftReturn())

        #expect(editor.string == prefix + "\n" + terminator + "tail")
        #expect(editor.selectedRange() == NSRange(location: (prefix as NSString).length + 1, length: 0))
    }

    @Test("Shift+Enter handles empty and unterminated buffers", arguments: ["", "a中🙂b"])
    func handlesLastLine(_ original: String) throws {
        let editor = EditorTextContainerView().textView
        editor.string = original
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        editor.keyDown(with: try shiftReturn())
        #expect(editor.string == original + "\n")
    }

    @Test("Shift+Enter remains one native undoable insertion")
    func insertionCanBeUndone() throws {
        let container = EditorTextContainerView()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentView = container
        let editor = container.textView
        let original = "first\r\nsecond"
        editor.string = original
        editor.setSelectedRange(NSRange(location: 2, length: 0))
        let undoManager = try #require(editor.undoManager)
        undoManager.beginUndoGrouping()
        editor.keyDown(with: try shiftReturn())
        undoManager.endUndoGrouping()

        #expect(editor.string == "first\n\r\nsecond")
        #expect(undoManager.canUndo)
        undoManager.undo()
        #expect(editor.string == original)
    }

    @Test("gutter width counts native logical lines", arguments: [
        "\n", "\r", "\r\n", "\u{0085}", "\u{2028}", "\u{2029}",
    ])
    func gutterCountsLineTerminators(_ terminator: String) throws {
        let container = EditorTextContainerView()
        let gutter = try #require(container.subviews.compactMap { $0 as? LineNumberGutterView }.first)
        let initialWidth = gutter.requiredWidth

        // A final terminator makes 999 nonempty lines plus the empty 1000th line.
        container.textView.string = String(repeating: "中🙂" + terminator, count: 999)
        container.synchronizeLineNumbersToCurrentText()
        #expect(gutter.requiredWidth > initialWidth)

        let terminatedWidth = gutter.requiredWidth
        container.textView.string = String(repeating: "中🙂" + terminator, count: 998) + "last"
        container.synchronizeLineNumbersToCurrentText()
        #expect(gutter.requiredWidth == initialWidth)
        #expect(gutter.requiredWidth < terminatedWidth)
    }

    @Test("editor keeps TextKit 2 through editing, search and zoom")
    func keepsModernTextEngine() {
        let container = EditorTextContainerView()
        let editor = container.textView

        #expect(editor.textLayoutManager != nil)
        #expect(editor.textContainer?.textLayoutManager != nil)

        editor.string = "\naaaaa\nbbbbbb"
        #expect(editor.textLayoutManager != nil)

        container.applyEditorTextAttributes()
        container.applyFontSize(28)
        container.applyFontSize(14)
        #expect(editor.textLayoutManager != nil)

        container.performSearch(for: "bbbbbb", usesRegularExpression: false, navigate: false)
        #expect(editor.textLayoutManager != nil)

        editor.setSelectedRange(NSRange(location: 0, length: 0))
        editor.insertText("\n", replacementRange: editor.selectedRange())
        editor.insertText("", replacementRange: NSRange(location: 0, length: 1))
        container.synchronizeLineNumbersToCurrentText()
        #expect(editor.textLayoutManager != nil)

        container.clearSearchHighlights()
        #expect(editor.textLayoutManager != nil)
    }

    @Test("gutter keeps every logical line through insert and delete")
    func gutterTracksIncrementalLineEdits() throws {
        let (container, gutter, scrollView) = try makeLaidOutEditor()
        let editor = container.textView
        editor.string = "\naaaaa\nbbbbbb"
        container.synchronizeLineNumbersToCurrentText()
        editor.layoutSubtreeIfNeeded()

        let initialLines = gutter.renderedLines(in: scrollView.contentView.bounds)
        #expect(initialLines.map(\.number) == [1, 2, 3])
        #expect(initialLines[1].y < initialLines[2].y)

        editor.setSelectedRange(NSRange(location: 0, length: 0))
        editor.insertText("\n", replacementRange: editor.selectedRange())
        container.synchronizeLineNumbersToCurrentText()
        let insertedLines = gutter.renderedLines(in: scrollView.contentView.bounds)
        #expect(insertedLines.map(\.number) == [1, 2, 3, 4])
        #expect(Set(insertedLines.map(\.number)).count == insertedLines.count)

        editor.insertText("", replacementRange: NSRange(location: 0, length: 1))
        container.synchronizeLineNumbersToCurrentText()
        let deletedLines = gutter.renderedLines(in: scrollView.contentView.bounds)
        #expect(deletedLines.map(\.number) == [1, 2, 3])
        #expect(Set(deletedLines.map(\.number)).count == deletedLines.count)
        #expect(editor.textLayoutManager != nil)
    }

    @Test("gutter line starts survive terminator edits that involve CR", arguments: [
        // (initial text, pre-edit range, replacement, expected starts)
        ("a\rb", NSRange(location: 2, length: 0), "\n", [0, 3]),
        ("a\r\nb", NSRange(location: 1, length: 1), "", [0, 2]),
        ("a\r\nb", NSRange(location: 2, length: 1), "", [0, 2]),
        ("one\r\ntwo\nthree", NSRange(location: 3, length: 4), "X", [0, 6]),
        ("one\ntwo", NSRange(location: 3, length: 0), "\n", [0, 4, 5]),
    ])
    func gutterKeepsLineStartsAcrossTerminatorEdits(
        _ testCase: (initial: String, editRange: NSRange, replacement: String, expected: [Int])
    ) throws {
        let (container, gutter, _) = try makeLaidOutEditor()
        let editor = container.textView
        editor.string = testCase.initial
        container.synchronizeLineNumbersToCurrentText()
        let storage = try #require(editor.textStorage)

        storage.replaceCharacters(in: testCase.editRange, with: testCase.replacement)
        // The storage delegate updates the index synchronously; reading it
        // before any rebuild is what proves the incremental path itself
        // produced the right starts.
        let incrementalStarts = gutter.lineStartIndices
        gutter.rebuildLineMetrics()

        #expect(incrementalStarts == gutter.lineStartIndices)
        #expect(gutter.lineStartIndices == testCase.expected)
    }

    @Test("only CRLF-ambiguous edits fall back to a full rebuild")
    func crlfAmbiguityDetection() throws {
        let cases: [(newText: String, editedRange: NSRange, isAmbiguous: Bool)] = [
            // CR + inserted LF become one break (reproduced desync).
            ("a\r\nb", NSRange(location: 2, length: 1), true),
            // A CR inserted in front of an LF becomes one break.
            ("a\r\nb", NSRange(location: 1, length: 1), true),
            // A whole CRLF inserted: the contained pair is handled by rebuild.
            ("a\r\nb", NSRange(location: 1, length: 2), true),
            // Deleting the gap merges two breaks into one pair.
            ("a\r\nb", NSRange(location: 2, length: 0), true),
            // Ordinary LF insertion keeps the incremental path.
            ("one\n\ntwo", NSRange(location: 4, length: 1), false),
            // A CR deleted from a CRLF leaves a lone LF: no new pairing.
            ("a\nb", NSRange(location: 1, length: 0), false),
            // An LF deleted from a CRLF leaves a lone CR: no new pairing.
            ("a\rb", NSRange(location: 2, length: 0), false),
            // Splitting a pair does not create a new adjacent CRLF.
            ("a\rx\nb", NSRange(location: 2, length: 1), false),
        ]

        for testCase in cases {
            let isAmbiguous = LineNumberGutterView.editChangesCRLFGrouping(
                in: testCase.newText as NSString,
                editedRange: testCase.editedRange
            )
            #expect(
                isAmbiguous == testCase.isAmbiguous,
                "text=\(testCase.newText.debugDescription) range=\(testCase.editedRange)"
            )
        }
    }

    @Test("gutter numbers each native line terminator once", arguments: [
        "\n", "\r", "\r\n", "\u{0085}", "\u{2028}", "\u{2029}",
    ])
    func gutterRendersLineTerminators(_ terminator: String) throws {
        let (container, gutter, scrollView) = try makeLaidOutEditor()
        let editor = container.textView
        editor.string = "a" + terminator + "b" + terminator + "c"
        container.synchronizeLineNumbersToCurrentText()
        editor.layoutSubtreeIfNeeded()

        let lines = gutter.renderedLines(in: scrollView.contentView.bounds)
        #expect(lines.map(\.number) == [1, 2, 3])
        #expect(lines[0].y < lines[1].y)
        #expect(lines[1].y < lines[2].y)
    }

    @Test("gutter draws the empty final line and the empty document")
    func gutterHandlesEmptyLines() throws {
        let (container, gutter, scrollView) = try makeLaidOutEditor()
        let editor = container.textView

        editor.string = ""
        container.synchronizeLineNumbersToCurrentText()
        #expect(
            gutter.renderedLines(in: scrollView.contentView.bounds).map(\.number) == [1]
        )

        editor.string = "tail\n"
        container.synchronizeLineNumbersToCurrentText()
        editor.layoutSubtreeIfNeeded()
        let lines = gutter.renderedLines(in: scrollView.contentView.bounds)
        #expect(lines.map(\.number) == [1, 2])
        #expect(lines[1].y > lines[0].y)
    }

    @Test("gutter numbers a wrapped logical line only once")
    func gutterCountsWrappedLinesOnce() throws {
        let (container, gutter, scrollView) = try makeLaidOutEditor(width: 360)
        let editor = container.textView
        editor.string = String(repeating: "wrap ", count: 40) + "\nlast"
        container.synchronizeLineNumbersToCurrentText()
        editor.layoutSubtreeIfNeeded()

        let lines = gutter.renderedLines(in: scrollView.contentView.bounds)
        #expect(lines.map(\.number) == [1, 2])
        #expect(lines[0].y < lines[1].y)
    }

    @Test("gutter follows the viewport at the end of a long document")
    func gutterFollowsScrolledViewport() throws {
        let (container, gutter, scrollView) = try makeLaidOutEditor()
        let editor = container.textView
        let text = (1...200)
            .map { "line \($0)" }
            .joined(separator: "\n")
        editor.string = text
        container.synchronizeLineNumbersToCurrentText()

        let textLength = (text as NSString).length
        editor.scrollRangeToVisible(
            NSRange(location: max(0, textLength - 1), length: 0)
        )
        scrollView.layoutSubtreeIfNeeded()
        let bottomRect = scrollView.contentView.bounds
        #expect(bottomRect.minY > 0)

        let bottomLines = gutter.renderedLines(in: bottomRect)
        #expect(bottomLines.last?.number == 200)
        #expect(Set(bottomLines.map(\.number)).count == bottomLines.count)
        #expect(bottomLines.map(\.number) == bottomLines.map(\.number).sorted())

        editor.setSelectedRange(NSRange(location: textLength, length: 0))
        editor.insertText("\n", replacementRange: editor.selectedRange())
        container.synchronizeLineNumbersToCurrentText()
        scrollView.layoutSubtreeIfNeeded()
        let insertedLines = gutter.renderedLines(in: scrollView.contentView.bounds)
        #expect(insertedLines.last?.number == 201)
        #expect(Set(insertedLines.map(\.number)).count == insertedLines.count)

        editor.insertText("", replacementRange: NSRange(location: textLength, length: 1))
        container.synchronizeLineNumbersToCurrentText()
        scrollView.layoutSubtreeIfNeeded()
        let deletedLines = gutter.renderedLines(in: scrollView.contentView.bounds)
        #expect(deletedLines.last?.number == 200)
        #expect(Set(deletedLines.map(\.number)).count == deletedLines.count)
        #expect(editor.textLayoutManager != nil)
    }

    @Test("search highlight uses text attributes and leaves undo intact")
    func searchHighlightDoesNotJoinUndo() throws {
        let (container, _, _) = try makeLaidOutEditor()
        let editor = container.textView
        let original = "\naaaaa\nbbbbbb"
        editor.string = original
        let storage = try #require(editor.textStorage)
        let undoManager = try #require(editor.undoManager)
        let matchRange = (original as NSString).range(of: "bbbbbb")

        container.performSearch(
            for: "bbbbbb",
            usesRegularExpression: false,
            navigate: false
        )
        #expect(
            storage.attribute(
                .backgroundColor,
                at: matchRange.location,
                effectiveRange: nil
            ) != nil
        )

        editor.setSelectedRange(NSRange(location: 0, length: 0))
        undoManager.beginUndoGrouping()
        editor.insertText("\n", replacementRange: editor.selectedRange())
        undoManager.endUndoGrouping()
        #expect(editor.string == "\n" + original)
        undoManager.undo()
        #expect(editor.string == original)

        container.clearSearchHighlights()
        #expect(
            storage.attribute(
                .backgroundColor,
                at: matchRange.location,
                effectiveRange: nil
            ) == nil
        )
        #expect(editor.textLayoutManager != nil)
    }

    private func makeLaidOutEditor(width: CGFloat = 600) throws -> (
        EditorTextContainerView,
        LineNumberGutterView,
        NSScrollView
    ) {
        let container = EditorTextContainerView()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 400),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentView = container
        container.frame = NSRect(x: 0, y: 0, width: width, height: 400)
        window.contentView?.layoutSubtreeIfNeeded()

        let gutter = try #require(
            container.subviews.compactMap { $0 as? LineNumberGutterView }.first
        )
        let scrollView = try #require(
            container.subviews.compactMap { $0 as? NSScrollView }.first
        )
        return (container, gutter, scrollView)
    }
}
