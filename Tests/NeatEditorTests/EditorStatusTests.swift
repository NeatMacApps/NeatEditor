import AppKit
import SwiftUI
import Testing

@testable import NeatEditor

struct EditorStatusWorkerTests {
    @Test("Empty text has one logical line and a one-based cursor")
    func emptyText() async throws {
        let result = try await EditorStatusWorker().snapshot(text: "", selection: NSRange(location: 0, length: 0))
        #expect(result == EditorStatusSnapshot())
    }

    @Test("Counts graphemes rather than UTF-16 code units")
    func unicodeCounts() async throws {
        let text = "中e\u{301}👨‍👩‍👧‍👦\tA\r\nB"
        let selection = (text as NSString).range(of: "e\u{301}👨‍👩‍👧‍👦")
        let result = try await EditorStatusWorker().snapshot(text: text, selection: selection)
        #expect(result.characters == 7)
        #expect(result.nonWhitespaceCharacters == 5)
        #expect(result.selectedCharacters == 2)
        #expect(result.lines == 2)
        #expect(result.line == 1)
        #expect(result.column == 2)
    }

    @Test("Native line terminators count once, including the final empty line", arguments: [
        "\n", "\r", "\r\n", "\u{0085}", "\u{2028}", "\u{2029}",
    ])
    func lineTerminators(_ terminator: String) async throws {
        let text = "first" + terminator + "中🙂" + terminator
        let result = try await EditorStatusWorker().snapshot(
            text: text, selection: NSRange(location: (text as NSString).length, length: 0)
        )
        #expect(result.lines == 3)
        #expect(result.line == 3)
        #expect(result.column == 1)
    }

    @Test("Columns count graphemes and tabs once, without soft-wrap lines")
    func characterColumn() async throws {
        let worker = EditorStatusWorker()
        let text = "head\n中🙂\tend"
        let result = try await worker.snapshot(
            text: text, selection: NSRange(location: ("head\n中🙂\t" as NSString).length, length: 0)
        )
        #expect(result.lines == 2)
        #expect(result.line == 2)
        #expect(result.column == 4)
        let moved = try await worker.snapshot(text: text, selection: NSRange(location: 0, length: 4))
        #expect(moved.characters == result.characters)
        #expect(moved.selectedCharacters == 4)
        #expect(moved.line == 1)
        #expect(moved.column == 1)
    }

    @Test("Words use native punctuation-aware enumeration")
    func words() async throws {
        let result = try await EditorStatusWorker().snapshot(
            text: "hello,world!  two\twords", selection: NSRange(location: 0, length: 0)
        )
        #expect(result.words == 4)
    }

    @Test("Stale or unavailable selection ranges are bounded")
    func boundedSelection() async throws {
        let worker = EditorStatusWorker()
        let missing = try await worker.snapshot(text: "abc", selection: NSRange(location: NSNotFound, length: 0))
        #expect(missing.column == 1)
        let stale = try await worker.snapshot(text: "abc", selection: NSRange(location: 99, length: 99))
        #expect(stale.column == 4)
        #expect(stale.selectedCharacters == 0)
    }
}

@MainActor
struct EditorStatusIntegrationTests {
    @Test("Superseded counts cannot cross document identities")
    func newestDocumentWins() async {
        let model = EditorStatusModel()
        let first = UUID()
        let second = UUID()
        let old = model.update(tabID: first, text: String(repeating: "old ", count: 50_000), selection: .init(location: 0, length: 0))
        let latest = model.update(tabID: second, text: "new", selection: .init(location: 3, length: 0))
        await latest.value
        await old.value
        #expect(model.tabID == second)
        #expect(model.snapshot?.characters == 3)
        #expect(model.snapshot?.column == 4)
    }

    @Test("Native selection notifications report without editing the buffer")
    func nativeSelection() async {
        var text = "中文🙂\nhello"
        var reported: EditorStatusSnapshot?
        let model = EditorStatusModel()
        let id = UUID()
        let bridge = EditorTextView(
            tabID: id, text: Binding(get: { text }, set: { text = $0 }),
            fontSize: 13, isEditable: true, tabBehavior: .spaces2,
            textSoftness: .init(), searchState: WorkspaceSearchState(),
            onTextChange: { _ in }, onCompositionEnd: {}, onIncreaseFontSize: {},
            onDecreaseFontSize: {}, onOpenFiles: { _ in }, onRegisterCommitHandler: { _ in },
            onStatusChange: { tabID, value, selection in
                let task = model.update(tabID: tabID, text: value, selection: selection)
                Task {
                    await task.value
                    reported = model.snapshot
                }
            }
        )
        let coordinator = bridge.makeCoordinator()
        let editor = EditorTextContainerView().textView
        coordinator.sync.notePushedText(text, for: id)
        editor.delegate = coordinator
        editor.string = text
        editor.setSelectedRange((text as NSString).range(of: "hello"))
        for _ in 0..<100 where reported == nil {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(reported?.selectedCharacters == 5)
        #expect(reported?.line == 2)
        #expect(reported?.column == 1)
        #expect(editor.string == text)
        #expect(editor.textLayoutManager != nil)
    }

    @Test("Font reset uses the existing clamped per-file preference")
    func resetFontSize() {
        var preferences = WorkspacePreferences(editorFontSize: 28)
        let file = URL(fileURLWithPath: "/tmp/neateditor-status-font-test.txt")
        let changed = preferences.stepEditorFontSize(
            by: WorkspacePreferences.defaultEditorFontSize - preferences.editorFontSize,
            rememberingFor: file
        )
        #expect(changed)
        preferences.editorFontSize = 20
        preferences.applyRememberedEditorFontSize(for: file)
        #expect(preferences.editorFontSize == WorkspacePreferences.defaultEditorFontSize)
    }
}
