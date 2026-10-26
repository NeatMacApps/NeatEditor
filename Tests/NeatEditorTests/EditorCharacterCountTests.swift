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
