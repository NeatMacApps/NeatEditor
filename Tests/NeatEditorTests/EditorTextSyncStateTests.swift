import Foundation
import Testing

@testable import NeatEditor

/// Contract tests for the `NSTextView` <-> SwiftUI `String` binding.
///
/// Each case replays one real-world editing scenario against the pure
/// decision state: the buggy behavior was "push `text` into the text view
/// whenever it differs", which clobbered newer in-flight edits with stale
/// SwiftUI snapshots (cut lines -> unrelated lines vanish).
struct EditorTextSyncStateTests {
    @Test("same-tab echo of our own edit never pushes back")
    func sameTabEchoKeepsTextView() {
        let tabID = UUID()
        var sync = EditorTextSyncState()
        sync.notePushedText("line1\nline2\n", for: tabID)

        // User cuts "line2\n" in the text view; the report is forwarded.
        sync.noteTextViewContent("line1\n", for: tabID)

        // SwiftUI echoes the same string back on the next update.
        let update = sync.update(for: tabID, text: "line1\n", hasMarkedText: false)
        guard case .keepTextView = update else {
            Issue.record("echo of our own edit must not push back into the text view")
            return
        }
    }

    @Test("stale snapshot arriving after rapid typing never overwrites")
    func staleSnapshotKeepsTextView() {
        let tabID = UUID()
        var sync = EditorTextSyncState()
        sync.notePushedText("a", for: tabID)
        sync.noteTextViewContent("abc", for: tabID)

        // A previously scheduled updateNSView still carries the older "ab".
        // It can no longer be mistaken for an external change because the
        // agreement point already moved to "abc".
        let update = sync.update(for: tabID, text: "abc", hasMarkedText: false)
        guard case .keepTextView = update else {
            Issue.record("stale snapshot must not overwrite newer buffer content")
            return
        }
    }

    @Test("external change on the same tab pushes once")
    func externalChangePushes() {
        let tabID = UUID()
        var sync = EditorTextSyncState()
        sync.notePushedText("", for: tabID)

        // Lazy file load finished and replaced the placeholder.
        let update = sync.update(for: tabID, text: "file content\n", hasMarkedText: false)
        guard case .pushToTextView(let pushed) = update, pushed == "file content\n" else {
            Issue.record("external content change must be pushed into the text view")
            return
        }

        // The follow-up echo of that push is a no-op.
        let echo = sync.update(for: tabID, text: "file content\n", hasMarkedText: false)
        guard case .keepTextView = echo else {
            Issue.record("echo after external push must not push again")
            return
        }
    }

    @Test("tab switch always pushes the newly selected content")
    func tabSwitchPushes() {
        let tabA = UUID()
        let tabB = UUID()
        var sync = EditorTextSyncState()
        sync.notePushedText("aaa", for: tabA)
        sync.noteTextViewContent("aaa edited", for: tabA)

        let update = sync.update(for: tabB, text: "bbb", hasMarkedText: false)
        guard case .pushToTextView(let pushed) = update, pushed == "bbb" else {
            Issue.record("switching tabs must push the new tab content")
            return
        }
    }

    @Test("switching back to the previous tab pushes its content again")
    func tabSwitchBackPushes() {
        let tabA = UUID()
        let tabB = UUID()
        var sync = EditorTextSyncState()
        sync.notePushedText("aaa edited", for: tabA)
        _ = sync.update(for: tabB, text: "bbb", hasMarkedText: false)

        let update = sync.update(for: tabA, text: "aaa edited", hasMarkedText: false)
        guard case .pushToTextView(let pushed) = update, pushed == "aaa edited" else {
            Issue.record("switching back must restore the previous tab content")
            return
        }
    }

    @Test("marked (IME composing) text is never overwritten on the same tab")
    func markedTextKeepsTextView() {
        let tabID = UUID()
        var sync = EditorTextSyncState()
        sync.notePushedText("ni", for: tabID)

        // Even if the binding disagrees mid-composition, the marked range
        // belongs to the input method.
        let update = sync.update(for: tabID, text: "different", hasMarkedText: true)
        guard case .keepTextView = update else {
            Issue.record("composing text must not be overwritten")
            return
        }
    }
}
