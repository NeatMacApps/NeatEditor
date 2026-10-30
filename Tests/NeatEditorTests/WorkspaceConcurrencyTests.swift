import Foundation
import AppKit
import SwiftUI
import Testing

@testable import NeatEditor

@MainActor
struct WorkspaceConcurrencyTests {
    private func fixture() throws -> (WorkspaceStore, URL, String) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("NeatEditorWorkspaceConcurrency-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let suite = "NeatEditorWorkspaceConcurrency-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let service = DocumentPersistenceService(defaultDirectory: root, recoveryDirectory: root.appendingPathComponent("recovery"))
        return (WorkspaceStore(persistenceService: service, userDefaults: defaults), root, suite)
    }

    private func cleanup(_ store: WorkspaceStore, root: URL, suite: String) {
        for id in Array(store.fileObservers.keys) { store.stopObservingDocument(id: id) }
        store.pendingSaveStateTask?.cancel()
        for tab in store.tabs { store.autoSaveScheduler.cancel(for: tab.id) }
        store.userDefaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }

    private func wait(_ predicate: @MainActor () -> Bool) async throws {
        for _ in 0..<200 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(predicate(), "expected file/editor state did not converge")
    }

    private func open(_ store: WorkspaceStore, root: URL, text: String) async throws -> UUID {
        let url = root.appendingPathComponent("shared.txt")
        try text.write(to: url, atomically: true, encoding: .utf8)
        store.openFiles(at: [url])
        let id = try #require(store.selectedTabID)
        try await wait { store.tabs.first(where: { $0.id == id })?.isContentLoaded == true }
        return id
    }

    @Test("filesystem observation survives repeated atomic replacements and direct writes")
    func observesExternalWrites() async throws {
        let (store, root, suite) = try fixture()
        defer { cleanup(store, root: root, suite: suite) }
        let id = try await open(store, root: root, text: "base")
        let url = try #require(store.tabs.first(where: { $0.id == id })?.fileURL)
        for (index, atomic) in [true, true, false, true, false].enumerated() {
            let value = "external-\(index)"
            try value.write(to: url, atomically: atomic, encoding: .utf8)
            try await wait { store.tabs.first(where: { $0.id == id })?.content == value }
            #expect(try String(contentsOf: url, encoding: .utf8) == value)
            #expect(store.documentFailureAlert == nil)
        }
    }

    @Test("a cooperating external writer notifies the installed native presenter path")
    func coordinatedExternalWrite() async throws {
        let (store, root, suite) = try fixture()
        defer { cleanup(store, root: root, suite: suite) }
        let id = try await open(store, root: root, text: "base")
        let url = try #require(store.tabs.first(where: { $0.id == id })?.fileURL)
        try await Task.detached {
            let coordinator = NSFileCoordinator()
            var error: NSError?
            var writeError: Error?
            coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &error) { url in
                do { try "coordinated external".write(to: url, atomically: true, encoding: .utf8) }
                catch { writeError = error }
            }
            if let error = error ?? writeError { throw error }
        }.value
        try await wait { store.tabs.first(where: { $0.id == id })?.content == "coordinated external" }
    }

    @Test("an initially empty file receives external contents")
    func emptyFileReload() async throws {
        let (store, root, suite) = try fixture()
        defer { cleanup(store, root: root, suite: suite) }
        let id = try await open(store, root: root, text: "")
        let url = try #require(store.tabs.first(where: { $0.id == id })?.fileURL)
        try "new contents".write(to: url, atomically: true, encoding: .utf8)
        try await wait { store.tabs.first(where: { $0.id == id })?.content == "new contents" }
    }

    @Test("external rename follows the document instead of resurrecting the old name")
    func externalRename() async throws {
        let (store, root, suite) = try fixture()
        defer { cleanup(store, root: root, suite: suite) }
        let id = try await open(store, root: root, text: "base")
        let old = try #require(store.tabs.first(where: { $0.id == id })?.fileURL)
        let destination = old.deletingLastPathComponent().appendingPathComponent("moved.txt")
        try FileManager.default.moveItem(at: old, to: destination)
        try await wait { store.tabs.first(where: { $0.id == id })?.fileURL?.lastPathComponent == "moved.txt" }
        let followed = try #require(store.tabs.first(where: { $0.id == id })?.fileURL)
        let actualID = try FileManager.default.attributesOfItem(atPath: followed.path)[.systemFileNumber] as? NSNumber
        let expectedID = try FileManager.default.attributesOfItem(atPath: destination.path)[.systemFileNumber] as? NSNumber
        #expect(actualID == expectedID)
        try await wait {
            store.sidebarFiles.contains(where: { $0.fileURL.lastPathComponent == "moved.txt" })
                && !store.sidebarFiles.contains(where: { $0.fileURL.lastPathComponent == "shared.txt" })
        }
        store.updateDocumentContent("edited after move", for: id)
        #expect(store.saveDocument(id: id))
        #expect(try String(contentsOf: destination, encoding: .utf8) == "edited after move")
        #expect(!FileManager.default.fileExists(atPath: old.path))
    }

    @Test("external deletion keeps the buffer and prevents destructive close")
    func externalDeletion() async throws {
        let (store, root, suite) = try fixture()
        defer { cleanup(store, root: root, suite: suite) }
        let id = try await open(store, root: root, text: "base")
        let url = try #require(store.tabs.first(where: { $0.id == id })?.fileURL)
        store.updateDocumentContent("retained draft", for: id)
        try FileManager.default.removeItem(at: url)
        store.closeDocument(id: id)
        #expect(store.tabs.contains(where: { $0.id == id && $0.content == "retained draft" }))
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(store.documentFailureAlert != nil)
    }

    @Test("old first-save completion cannot override manual/close save")
    func closeWithPendingFirstSave() async throws {
        let (store, root, suite) = try fixture()
        defer { cleanup(store, root: root, suite: suite) }
        let id = try #require(store.selectedTabID)
        let gate = DispatchSemaphore(value: 0)
        store.persistenceService.fileAccess.enqueue { gate.wait() }
        store.updateDocumentContent("old", for: id)
        store.saveDocumentInBackground(id: id)
        store.updateDocumentContent("newest", for: id)
        gate.signal()
        store.closeDocument(id: id)
        try await Task.sleep(for: .milliseconds(100))
        let closed = try #require(store.closedTabs.last)
        #expect(closed.tab.content == "newest")
        #expect(try String(contentsOf: #require(closed.tab.fileURL), encoding: .utf8) == "newest")
        #expect(!store.tabs.contains(where: { $0.id == id }))
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).count == 1)
    }

    @Test("typing during background save remains dirty and the next save persists it")
    func editDuringSave() async throws {
        let (store, root, suite) = try fixture()
        defer { cleanup(store, root: root, suite: suite) }
        let id = try await open(store, root: root, text: "base")
        let gate = DispatchSemaphore(value: 0)
        store.persistenceService.fileAccess.enqueue { gate.wait() }
        store.updateDocumentContent("snapshot", for: id)
        store.saveDocumentInBackground(id: id)
        store.updateDocumentContent("typed later", for: id)
        gate.signal()
        try await wait { store.tabs.first(where: { $0.id == id })?.diskContent == "snapshot" }
        #expect(store.tabs.first(where: { $0.id == id })?.content == "typed later")
        #expect(store.saveAllDocuments())
        let url = try #require(store.tabs.first(where: { $0.id == id })?.fileURL)
        #expect(try String(contentsOf: url, encoding: .utf8) == "typed later")
    }

    @Test("missed notifications are caught at lifecycle save and conflicting copies restore")
    func conflictAndRestore() async throws {
        let (store, root, suite) = try fixture()
        defer { cleanup(store, root: root, suite: suite) }
        let id = try await open(store, root: root, text: "base")
        let original = try #require(store.tabs.first(where: { $0.id == id })?.fileURL)
        store.stopObservingDocument(id: id)
        store.updateDocumentContent("local", for: id)
        try "external".write(to: original, atomically: true, encoding: .utf8)
        #expect(store.saveAllDocuments())
        let localURL = try #require(store.tabs.first(where: { $0.id == id })?.fileURL)
        #expect(localURL != original)
        #expect(store.documentFailureAlert?.otherVersionURL == original)
        let restarted = WorkspaceStore(persistenceService: DocumentPersistenceService(defaultDirectory: root,
            recoveryDirectory: root.appendingPathComponent("recovery")), userDefaults: store.userDefaults)
        defer {
            for id in Array(restarted.fileObservers.keys) { restarted.stopObservingDocument(id: id) }
            restarted.pendingSaveStateTask?.cancel()
        }
        try await wait { restarted.tabs.contains(where: { $0.fileURL == localURL && $0.content == "local" }) }
        #expect(try String(contentsOf: original, encoding: .utf8) == "external")
        #expect(restarted.tabs.allSatisfy { !$0.isSettings })
    }

    @Test("external updates wait for composition and reconcile committed input only")
    func compositionDefersUpdate() async throws {
        let (store, root, suite) = try fixture()
        defer { cleanup(store, root: root, suite: suite) }
        let id = try await open(store, root: root, text: "one\nmiddle\nthree")
        let url = try #require(store.tabs.first(where: { $0.id == id })?.fileURL)
        store.editorHasMarkedText = { $0 == id }
        try "one\nmiddle\nDISK".write(to: url, atomically: true, encoding: .utf8)
        store.reconcileDocument(id: id)
        #expect(store.pendingExternalChecks.contains(id))
        #expect(store.tabs.first(where: { $0.id == id })?.content == "one\nmiddle\nthree")
        store.editorHasMarkedText = { _ in false }
        store.updateDocumentContent("LOCAL\nmiddle\nthree", for: id)
        store.queueAutoSave(for: id)
        try await wait { store.tabs.first(where: { $0.id == id })?.content == "LOCAL\nmiddle\nDISK" }
        #expect(try String(contentsOf: url, encoding: .utf8) == "LOCAL\nmiddle\nDISK")
    }

    @Test("closing releases file presenters and their vnode resources")
    func presenterCleanup() async throws {
        let (store, root, suite) = try fixture()
        defer { cleanup(store, root: root, suite: suite) }
        let id = try await open(store, root: root, text: "base")
        let observer = try #require(store.fileObservers[id])
        #expect(NSFileCoordinator.filePresenters.contains(where: { ($0 as AnyObject) === observer }))
        store.closeDocument(id: id)
        #expect(store.fileObservers[id] == nil)
        #expect(!NSFileCoordinator.filePresenters.contains(where: { ($0 as AnyObject) === observer }))
    }

    @Test("native external text replacement preserves selection, undo and newer edits")
    func nativeReplacementAndUndo() throws {
        let (store, root, suite) = try fixture()
        defer { cleanup(store, root: root, suite: suite) }
        let id = try #require(store.selectedTabID)
        store.updateDocumentContent("hello 🐈\nworld", for: id)
        let parent = EditorTextView(tabID: id, text: WorkspaceView.textBinding(for: id, in: store),
            fontSize: 14, isEditable: true, tabBehavior: .spaces2,
            textSoftness: store.preferences.editorTextSoftness, searchState: store.searchState,
            onTextChange: { _ in }, onCompositionEnd: {}, onIncreaseFontSize: {}, onDecreaseFontSize: {},
            onOpenFiles: { _ in }, onRegisterCommitHandler: { store.commitEditorChanges = $0 },
            onRegisterCompositionCheck: { store.editorHasMarkedText = $0 },
            onRegisterExternalChangeHandler: { store.applyExternalEditorChanges = $0 })
        let coordinator = parent.makeCoordinator()
        let container = EditorTextContainerView(onIncreaseFontSize: {}, onDecreaseFontSize: {})
        let window = NSWindow(contentRect: NSRect(x: 50, y: 50, width: 600, height: 400),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = container
        defer { window.close() }
        let view = container.textView
        view.string = "hello 🐈\nworld"
        view.delegate = coordinator
        view.isEditable = true
        coordinator.sync.noteTextViewContent(view.string, for: id)
        coordinator.registerCommitHandler(for: view)
        let caret = (view.string as NSString).length
        view.setSelectedRange(NSRange(location: caret, length: 0))
        store.applyExternalEditorChanges?(id, "prefix\nhello 🐈\nworld", 1)
        #expect(view.string == "prefix\nhello 🐈\nworld")
        #expect(view.selectedRange().location == caret + 7)
        #expect(view.undoManager?.canUndo == true)
        view.undoManager?.undo()
        #expect(view.string == "hello 🐈\nworld")
        #expect(store.tabs.first(where: { $0.id == id })?.content == "hello 🐈\nworld")
        let old = coordinator.sync.update(for: id, text: "stale before external update", hasMarkedText: false, externalRevision: 0)
        guard case .keepTextView = old else { Issue.record("stale pre-external snapshot must not replace native text"); return }
    }
}
