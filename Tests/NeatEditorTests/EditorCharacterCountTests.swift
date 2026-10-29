import AppKit
import SwiftUI
import Testing

@testable import NeatEditor

struct EditorCharacterCountWorkerTests {
    @Test("Empty text has no characters")
    func emptyText() async throws {
        let count = try await EditorCharacterCountWorker().count(text: "")
        #expect(count == 0)
    }

    @Test("Counts graphemes rather than UTF-16 code units")
    func unicodeCounts() async throws {
        let text = "中e\u{301}👨‍👩‍👧‍👦\tA\r\nB"
        let count = try await EditorCharacterCountWorker().count(text: text)
        #expect(count == 7)
    }

    @Test("Repeated counts reuse the cached text")
    func repeatedCount() async throws {
        let worker = EditorCharacterCountWorker()
        let first = try await worker.count(text: "中文🙂")
        let second = try await worker.count(text: "中文🙂")
        #expect(first == 3)
        #expect(second == first)
    }
}

@MainActor
struct EditorCharacterCountIntegrationTests {
    @Test("Superseded counts cannot cross document identities")
    func newestDocumentWins() async {
        let model = EditorCharacterCountModel()
        let first = UUID()
        let second = UUID()
        let old = model.update(tabID: first, text: String(repeating: "old ", count: 50_000))
        let latest = model.update(tabID: second, text: "new")
        await latest.value
        await old.value
        #expect(model.tabID == second)
        #expect(model.characters == 3)
        #expect(model.count(for: first) == nil)
    }

    @Test("Native typing reports the live count without changing the buffer")
    func nativeTyping() async {
        var text = ""
        let model = EditorCharacterCountModel()
        let id = UUID()
        let bridge = EditorTextView(
            tabID: id,
            text: Binding(get: { text }, set: { text = $0 }),
            fontSize: 13,
            isEditable: true,
            tabBehavior: .spaces2,
            textSoftness: .init(),
            searchState: WorkspaceSearchState(),
            onTextChange: { _ in },
            onCompositionEnd: {},
            onIncreaseFontSize: {},
            onDecreaseFontSize: {},
            onOpenFiles: { _ in },
            onRegisterCommitHandler: { _ in },
            onCharacterCountChange: { tabID, value in
                model.update(tabID: tabID, text: value)
            }
        )
        let container = EditorTextContainerView()
        let editor = container.textView
        let coordinator = bridge.makeCoordinator()
        coordinator.sync.notePushedText("", for: id)
        editor.delegate = coordinator
        editor.string = ""
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        coordinator.scheduleCharacterCountReport(for: editor)
        let sawEmptyCount = await wait(for: model, toReach: 0)
        #expect(sawEmptyCount)

        editor.insertText("中文🙂\nA", replacementRange: NSRange(location: 0, length: 0))
        let sawTypedCount = await wait(for: model, toReach: 5)
        #expect(sawTypedCount)
        #expect(editor.string == "中文🙂\nA")
        #expect(editor.textLayoutManager != nil)
    }

    @Test("Floating count does not shorten the native text viewport", arguments: [360.0, 900.0])
    func fullHeightViewport(width: CGFloat) throws {
        let (window, container, scrollView) = try makeEditor(width: width)
        defer { window.close() }

        #expect(scrollView.frame.maxY == container.bounds.maxY)
        #expect(scrollView.contentView.frame.height == container.bounds.height)
        #expect(scrollView.contentInsets.bottom == EditorCharacterCountLayout.scrollableBottomInset)
        #expect(scrollView.automaticallyAdjustsContentInsets == false)
        let gutter = try #require(container.subviews.compactMap { $0 as? LineNumberGutterView }.first)
        #expect(gutter.frame.height == container.bounds.height)
        #expect(container.textView.textLayoutManager != nil)
    }

    @Test("Last wrapped line and caret scroll above the floating count", arguments: [13.0, 36.0])
    func finalLineClearsCount(fontSize: CGFloat) throws {
        let (window, container, scrollView) = try makeEditor(width: 360)
        defer { window.close() }
        let editor = container.textView
        container.applyFontSize(fontSize)
        editor.string = String(repeating: "中文 wrapped text 🙂 abcdefghijklmnop\n", count: 80)
            + "FINAL " + String(repeating: "wrapped 中文🙂 ", count: 12)
        container.applyEditorTextAttributes()
        let end = NSRange(location: editor.string.utf16.count, length: 0)
        editor.setSelectedRange(end)
        editor.scrollRangeToVisible(end)
        scrollView.layoutSubtreeIfNeeded()

        let caretOnScreen = editor.firstRect(forCharacterRange: end, actualRange: nil)
        let caret = editor.convert(window.convertFromScreen(caretOnScreen), from: nil)
        let viewport = scrollView.contentView.bounds
        #expect(viewport.minY > 0)
        #expect(caret.height > 0)
        #expect(caret.maxY <= viewport.maxY - EditorCharacterCountLayout.scrollableBottomInset + 1)
        #expect(editor.textLayoutManager != nil)
    }

    private func makeEditor(width: CGFloat) throws -> (NSWindow, EditorTextContainerView, NSScrollView) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 400),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        let container = EditorTextContainerView()
        window.contentView = container
        container.frame = NSRect(x: 0, y: 0, width: width, height: 400)
        container.layoutSubtreeIfNeeded()
        let scrollView = try #require(container.subviews.compactMap { $0 as? NSScrollView }.first)
        return (window, container, scrollView)
    }

    private func wait(for model: EditorCharacterCountModel, toReach expected: Int) async -> Bool {
        for _ in 0..<200 {
            if model.characters == expected {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }
}
