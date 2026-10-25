import AppKit
import Testing

@testable import NeatEditor

@MainActor
struct EditorNewlineTests {
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
