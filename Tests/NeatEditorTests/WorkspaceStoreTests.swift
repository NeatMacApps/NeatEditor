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
