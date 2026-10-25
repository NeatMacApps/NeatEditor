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
}
