import Foundation
import AppKit
import SwiftUI
import Testing

@testable import NeatEditor

@MainActor
struct WorkspaceStoreTests {
    private func makeWorkspace() throws -> (WorkspaceStore, URL, UserDefaults, String) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NeatEditorWorkspaceTests-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "NeatEditorWorkspaceTests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let state = WorkspaceStore.WorkspaceState(
            tabs: [], selectedFileURL: nil, isSettingsSelected: false,
            preferences: WorkspacePreferences()
        )
        defaults.set(try JSONEncoder().encode(state), forKey: WorkspaceStore.UserDefaultsKey.workspaceState)
        let store = WorkspaceStore(
            persistenceService: DocumentPersistenceService(defaultDirectory: directory),
            userDefaults: defaults
        )
        return (store, directory, defaults, suite)
    }

    private func cleanUp(_ store: WorkspaceStore, directory: URL, defaults: UserDefaults, suite: String) {
        store.pendingSaveStateTask?.cancel()
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }

    @Test("failed UTF-8 load never becomes saveable document text and can retry")
    func failedLoadPreservesOriginalAndRetries() async throws {
        let (store, directory, defaults, suite) = try makeWorkspace()
        defer { cleanUp(store, directory: directory, defaults: defaults, suite: suite) }
        let url = directory.appendingPathComponent("invalid.txt")
        let original = Data([0xff, 0xfe, 0xfd])
        try original.write(to: url)

        store.openFiles(at: [url])
        let id = try #require(store.selectedTabID)
        for _ in 0..<100 where store.loadingTabIDs.contains(id) {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(!store.loadingTabIDs.contains(id))
        let failedTab = try #require(store.tabs.first(where: { $0.id == id }))
        #expect(failedTab.content.isEmpty)
        #expect(!failedTab.isContentLoaded)
        #expect(store.documentFailureAlert != nil)
        store.saveAllDocuments()
        #expect(try Data(contentsOf: url) == original)

        try "recovered text".write(to: url, atomically: true, encoding: .utf8)
        store.dismissDocumentFailureAlert()
        store.openFiles(at: [url])
        for _ in 0..<100 where store.loadingTabIDs.contains(id) {
            try await Task.sleep(for: .milliseconds(20))
        }
        let recoveredTab = try #require(store.tabs.first(where: { $0.id == id }))
        #expect(recoveredTab.isContentLoaded)
        #expect(recoveredTab.content == "recovered text")
    }

    @Test("failed save prevents close and close-other from losing a buffer")
    func failedSaveKeepsTabsOpen() throws {
        let (store, directory, defaults, suite) = try makeWorkspace()
        defer { cleanUp(store, directory: directory, defaults: defaults, suite: suite) }
        let failing = EditorTab(title: "bad/name", content: "unsaved text")
        let kept = EditorTab(title: "keep", content: "")
        store.tabs = [failing, kept]
        store.selectedTabID = failing.id

        store.closeDocument(id: failing.id)
        #expect(store.tabs.count == 2)
        #expect(store.tabs.first?.content == "unsaved text")
        #expect(store.selectedTabID == failing.id)
        #expect(store.closedTabs.isEmpty)
        #expect(store.documentFailureAlert != nil)

        store.closeOtherDocuments(keeping: kept.id)
        #expect(store.tabs.count == 2)
        #expect(store.selectedTabID == failing.id)
        #expect(!store.saveAllDocuments())
    }

    @Test("final reports for a removed tab cannot edit the replacement at its old index")
    func removedTabCannotEditAnotherDocument() throws {
        let (store, directory, defaults, suite) = try makeWorkspace()
        defer { cleanUp(store, directory: directory, defaults: defaults, suite: suite) }
        let removed = EditorTab(title: "removed")
        let remaining = EditorTab(title: "remaining", content: "keep")
        store.tabs = [removed, remaining]
        let binding = WorkspaceView.textBinding(for: removed.id, in: store)
        store.tabs.removeFirst()
        binding.wrappedValue = "late composition"
        #expect(store.tabs[0].content == "keep")
    }

    @Test("save commits pending editor text before taking its snapshot")
    func saveCommitsEditorBeforeWriting() throws {
        let (store, directory, defaults, suite) = try makeWorkspace()
        defer { cleanUp(store, directory: directory, defaults: defaults, suite: suite) }
        let id = try #require(store.selectedTabID)
        store.commitEditorChanges = { [weak store] requestedID in
            store?.updateDocumentContent("committed composition", for: requestedID)
        }

        #expect(store.saveDocument(id: id))
        let url = try #require(store.tabs.first(where: { $0.id == id })?.fileURL)
        #expect(try String(contentsOf: url, encoding: .utf8) == "committed composition")
    }

    @Test("clean transitions commit the native snapshot without requesting another write")
    func cleanTransitionDoesNotSaveAgain() async throws {
        let (store, directory, defaults, suite) = try makeWorkspace()
        defer { cleanUp(store, directory: directory, defaults: defaults, suite: suite) }
        let url = directory.appendingPathComponent("clean.txt")
        try "accepted text".write(to: url, atomically: true, encoding: .utf8)
        let clean = try store.persistenceService.openDocument(at: url)
        let next = EditorTab(title: "next")
        store.tabs = [clean, next]
        store.selectedTabID = clean.id
        store.observeDocument(id: clean.id)
        let observer = store.fileObservers[clean.id]
        let generation = store.saveGenerations[clean.id]
        var committedIDs: [UUID] = []
        store.commitEditorChanges = { committedIDs.append($0) }
        var redundantAutosaveRan = false
        store.autoSaveScheduler.schedule(for: clean.id) { redundantAutosaveRan = true }

        store.selectTab(next.id)

        #expect(committedIDs == [clean.id])
        #expect(store.selectedTabID == next.id)
        #expect(store.saveGenerations[clean.id] == generation)
        #expect(store.fileObservers[clean.id] === observer)
        #expect(!store.isRefreshingSidebar)
        try await Task.sleep(for: .milliseconds(2100))
        #expect(!redundantAutosaveRan)

        // Skipping a no-op transition is not permission to skip validation
        // for explicit saves or to overwrite a later external version.
        try "external text".write(to: url, atomically: true, encoding: .utf8)
        #expect(store.saveDocument(id: clean.id))
        #expect(store.tabs.first(where: { $0.id == clean.id })?.content == "external text")
        #expect(try String(contentsOf: url, encoding: .utf8) == "external text")
        store.stopObservingDocument(id: clean.id)
    }

    @Test("a pending native edit is still saved before a transition")
    func transitionSavesPendingNativeEdit() throws {
        let (store, directory, defaults, suite) = try makeWorkspace()
        defer { cleanUp(store, directory: directory, defaults: defaults, suite: suite) }
        let url = directory.appendingPathComponent("edited.txt")
        try "accepted text".write(to: url, atomically: true, encoding: .utf8)
        let tab = try store.persistenceService.openDocument(at: url)
        let next = EditorTab(title: "next")
        store.tabs = [tab, next]
        store.selectedTabID = tab.id
        store.commitEditorChanges = { [weak store] id in
            if id == tab.id { store?.updateDocumentContent("live native edit", for: id) }
        }

        store.selectTab(next.id)

        #expect(try String(contentsOf: url, encoding: .utf8) == "live native edit")
        #expect(store.selectedTabID == next.id)
        #expect(store.tabs.first(where: { $0.id == tab.id })?.diskContent == "live native edit")
        store.stopObservingDocument(id: tab.id)
    }

    @Test("Don't Save closes only the failed document without recreating its missing file",
          arguments: [true, false])
    func discardMissingDocument(isSelected: Bool) throws {
        let (store, directory, defaults, suite) = try makeWorkspace()
        defer { cleanUp(store, directory: directory, defaults: defaults, suite: suite) }
        let missing = directory.appendingPathComponent("missing.txt")
        let failed = EditorTab(title: "missing.txt", content: "unsaved buffer", fileURL: missing)
        let kept = EditorTab(title: "kept")
        store.tabs = [failed, kept]
        store.selectedTabID = isSelected ? failed.id : kept.id
        store.observeDocument(id: failed.id)
        #expect(!store.saveDocument(id: failed.id))
        let generation = store.saveGenerations[failed.id, default: 0]
        #expect(store.documentFailureAlert?.recoveryTabID == failed.id)

        store.discardFailedDocument(id: kept.id)
        #expect(store.tabs.count == 2)
        #expect(store.documentFailureAlert != nil)
        store.discardFailedDocument(id: failed.id)

        #expect(store.tabs.map(\.id) == [kept.id])
        #expect(store.selectedTabID == kept.id)
        #expect(store.documentFailureAlert == nil)
        #expect(store.fileObservers[failed.id] == nil)
        #expect(store.saveGenerations[failed.id, default: 0] > generation)
        #expect(store.closedTabs.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: missing.path))
        #expect(store.saveAllDocuments())
    }

    @Test("Don't Save cancels pending autosave and leaves other files and normal reopen intact")
    func discardCancelsAutosave() async throws {
        let (store, directory, defaults, suite) = try makeWorkspace()
        defer { cleanUp(store, directory: directory, defaults: defaults, suite: suite) }
        let sentinel = directory.appendingPathComponent("sentinel.txt")
        try "original disk content".write(to: sentinel, atomically: true, encoding: .utf8)
        let failed = EditorTab(title: "bad/name", content: "unsaved buffer")
        let kept = EditorTab(title: "kept")
        store.tabs = [failed, kept]
        store.selectedTabID = failed.id
        #expect(!store.saveDocument(id: failed.id))
        var autosaveRan = false
        store.autoSaveScheduler.schedule(for: failed.id) { autosaveRan = true }
        store.discardFailedDocument(id: failed.id)
        try await Task.sleep(for: .milliseconds(2100))
        #expect(!autosaveRan)
        #expect(try String(contentsOf: sentinel, encoding: .utf8) == "original disk content")
        #expect(store.closedTabs.isEmpty)
        #expect(store.selectedTabID == kept.id)

        store.discardFailedDocument(id: kept.id)
        #expect(store.tabs.count == 1)
        store.closeDocument(id: kept.id)
        #expect(store.closedTabs.last?.tab.id == kept.id)
        store.reopenLastClosedDocument()
        #expect(store.tabs.map(\.id) == [kept.id])
    }

    private func makeEditor(for id: UUID, store: WorkspaceStore) -> (EditorTextView.Coordinator, ZoomableTextView) {
        let parent = EditorTextView(
            tabID: id, text: WorkspaceView.textBinding(for: id, in: store),
            fontSize: 14, isEditable: true, tabBehavior: .spaces2,
            textSoftness: store.preferences.editorTextSoftness,
            searchState: store.searchState,
            onTextChange: { _ in }, onCompositionEnd: {},
            onIncreaseFontSize: {}, onDecreaseFontSize: {}, onOpenFiles: { _ in },
            onRegisterCommitHandler: { store.commitEditorChanges = $0 }
        )
        let coordinator = parent.makeCoordinator()
        let textView = ZoomableTextView(frame: .zero)
        textView.isEditable = true
        coordinator.sync.notePushedText("", for: id)
        coordinator.registerCommitHandler(for: textView)
        return (coordinator, textView)
    }

    private func composeCommittedText(
        _ committed: String, thenMark marked: String,
        coordinator: EditorTextView.Coordinator, textView: ZoomableTextView
    ) {
        textView.string = committed
        coordinator.reportAppKitText(committed)
        textView.setSelectedRange(NSRange(location: (committed as NSString).length, length: 0))
        textView.setMarkedText(marked, selectedRange: NSRange(location: (marked as NSString).length, length: 0),
                               replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    @Test("native snapshots own contiguous UTF-8 without changing document scalars or selection")
    func nativeSnapshotUsesOwnedUTF8() throws {
        let (store, directory, defaults, suite) = try makeWorkspace()
        defer { cleanUp(store, directory: directory, defaults: defaults, suite: suite) }
        let id = try #require(store.selectedTabID)
        let (coordinator, textView) = makeEditor(for: id, store: store)
        let text = String(repeating: "中文🙂 e\u{301}\r\n", count: 100)
        textView.string = text
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        let selection = textView.selectedRange()
        coordinator.reportAppKitText(textView.string)
        let snapshot = try #require(store.tabs.first(where: { $0.id == id })?.content)
        #expect(snapshot.isContiguousUTF8)
        #expect(snapshot.utf8.elementsEqual(text.utf8))
        #expect(coordinator.sync.lastKnownText?.isContiguousUTF8 == true)
        #expect(textView.string.utf8.elementsEqual(text.utf8))
        #expect(textView.selectedRange() == selection)
    }

    @Test("autosave during composition writes committed text and leaves the pinyin marked")
    func saveDuringCompositionSkipsMarkedText() throws {
        let (store, directory, defaults, suite) = try makeWorkspace()
        defer { cleanUp(store, directory: directory, defaults: defaults, suite: suite) }
        let id = try #require(store.selectedTabID)
        let (coordinator, textView) = makeEditor(for: id, store: store)
        defer { withExtendedLifetime(coordinator) {} }
        composeCommittedText("你好", thenMark: "hui", coordinator: coordinator, textView: textView)
        #expect(textView.hasMarkedText())

        #expect(store.saveDocument(id: id))

        #expect(textView.hasMarkedText())
        #expect(textView.string == "你好hui")
        let url = try #require(store.tabs.first(where: { $0.id == id })?.fileURL)
        #expect(try String(contentsOf: url, encoding: .utf8) == "你好")
    }

    @Test("closing a tab mid-composition never saves the pinyin")
    func closeDuringCompositionSkipsMarkedText() throws {
        let (store, directory, defaults, suite) = try makeWorkspace()
        defer { cleanUp(store, directory: directory, defaults: defaults, suite: suite) }
        let id = try #require(store.selectedTabID)
        let (coordinator, textView) = makeEditor(for: id, store: store)
        defer { withExtendedLifetime(coordinator) {} }
        composeCommittedText("你好", thenMark: "hui", coordinator: coordinator, textView: textView)

        store.closeDocument(id: id)

        let closed = try #require(store.closedTabs.last)
        let url = try #require(closed.tab.fileURL)
        #expect(try String(contentsOf: url, encoding: .utf8) == "你好")
    }

    @Test("switching tabs discards the composition instead of committing it")
    func tabSwitchDiscardsComposition() throws {
        let (store, directory, defaults, suite) = try makeWorkspace()
        defer { cleanUp(store, directory: directory, defaults: defaults, suite: suite) }
        let id = try #require(store.selectedTabID)
        let (coordinator, textView) = makeEditor(for: id, store: store)
        defer { withExtendedLifetime(coordinator) {} }
        composeCommittedText("你好", thenMark: "hui", coordinator: coordinator, textView: textView)

        coordinator.discardComposition(in: textView)

        #expect(!textView.hasMarkedText())
        #expect(store.tabs.first(where: { $0.id == id })?.content == "你好")
        #expect(coordinator.sync.lastKnownText == "你好")
    }

    @Test("saving an unloaded placeholder does not claim initial file content as an edit")
    func unloadedEditorCannotBlockInitialPush() throws {
        let (store, directory, defaults, suite) = try makeWorkspace()
        defer { cleanUp(store, directory: directory, defaults: defaults, suite: suite) }
        let id = try #require(store.selectedTabID)
        let (coordinator, textView) = makeEditor(for: id, store: store)
        textView.isEditable = false
        textView.string = "placeholder"
        store.saveDocument(id: id)
        let update = coordinator.sync.update(for: id, text: "loaded file", hasMarkedText: false)
        guard case .pushToTextView("loaded file") = update else {
            Issue.record("unloaded editor must allow its initial file content")
            return
        }
    }

    @Test("workspace restoration never opens Settings proactively")
    func restoreSelectsDocumentInsteadOfSettings() throws {
        let (store, directory, defaults, suite) = try makeWorkspace()
        defer { cleanUp(store, directory: directory, defaults: defaults, suite: suite) }
        store.tabs = []
        store.restoreState(WorkspaceStore.WorkspaceState(
            tabs: [.init(fileURL: nil, isSettings: true)],
            selectedFileURL: nil, isSettingsSelected: true,
            preferences: WorkspacePreferences()
        ))
        #expect(store.tabs.count == 1)
        #expect(store.tabs.allSatisfy { !$0.isSettings })
        #expect(store.selectedTabID == store.tabs.first?.id)
    }
}
