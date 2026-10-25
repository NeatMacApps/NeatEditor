import Foundation
import AppKit
import SwiftUI
import Testing

@testable import NeatEditor

struct WorkspaceSidebarTests {
    @MainActor
    @Test("sidebar folder header carries no actions control")
    func folderHeaderHasNoActionsButton() {
        let host = NSHostingView(
            rootView: WorkspaceSidebarFolderHeader(
                name: "Documents",
                path: "/Users/example/Documents"
            )
        )
        host.frame = NSRect(x: 0, y: 0, width: 200, height: 22)
        host.layoutSubtreeIfNeeded()
        #expect(buttons(in: host).isEmpty)
    }

    @MainActor
    private func buttons(in view: NSView) -> [NSButton] {
        var buttons: [NSButton] = []
        if let button = view as? NSButton {
            buttons.append(button)
        }
        for subview in view.subviews {
            buttons.append(contentsOf: self.buttons(in: subview))
        }
        return buttons
    }

    @MainActor
    @Test("sidebar row heights match for empty, short, multiline and overflowing content")
    func equalRowHeights() throws {
        let samples = [
            ("Empty.txt", ""),
            ("Short.md", "One line"),
            ("多行文件.txt", "First line\nSecond line\nThird line"),
            (String(repeating: "很长的文件名", count: 15), String(repeating: "A long preview 正文 ", count: 50))
        ]
        for width: CGFloat in [160, 240, 340] {
            var sizes: [CGSize] = []
            for (title, preview) in samples {
                let host = NSHostingController(rootView: WorkspaceSidebarFileRow(title: title, preview: preview))
                sizes.append(host.sizeThatFits(in: CGSize(width: width, height: 1000)))
            }
            let first = try #require(sizes.first)
            #expect(first.height > 30)
            for size in sizes {
                #expect(abs(size.height - first.height) < 0.01, "width=\(width), sizes=\(sizes)")
                #expect(size.width <= width)
            }
        }
    }

    private func makeService() throws -> (DocumentPersistenceService, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NeatEditorSidebarTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (DocumentPersistenceService(defaultDirectory: directory), directory)
    }

    private func touch(_ url: URL, date: Date) throws {
        try FileManager.default.setAttributes(
            [.modificationDate: date],
            ofItemAtPath: url.path
        )
    }

    @Test("sidebar lists supported files in stable descending filename order")
    func sidebarListsSupportedFilesNewestFirst() throws {
        let (service, directory) = try makeService()
        defer { try? FileManager.default.removeItem(at: directory) }

        try "a".write(to: directory.appendingPathComponent("older.txt"), atomically: true, encoding: .utf8)
        try "b".write(to: directory.appendingPathComponent("newer.md"), atomically: true, encoding: .utf8)
        try "c".write(to: directory.appendingPathComponent("upper.MD"), atomically: true, encoding: .utf8)
        try "d".write(to: directory.appendingPathComponent("note.markdown"), atomically: true, encoding: .utf8)
        try "e".write(to: directory.appendingPathComponent("plain.text"), atomically: true, encoding: .utf8)
        try "extensionless note".write(
            to: directory.appendingPathComponent("noext"),
            atomically: true,
            encoding: .utf8
        )
        try Data([0x00, 0xFF, 0x10, 0x80]).write(
            to: directory.appendingPathComponent("binary")
        )
        try "skip".write(to: directory.appendingPathComponent("image.png"), atomically: true, encoding: .utf8)
        try "skip".write(to: directory.appendingPathComponent(".hidden.txt"), atomically: true, encoding: .utf8)
        try "skip".write(
            to: directory.appendingPathComponent(".neateditor-staging-123"),
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("subdir", isDirectory: true),
            withIntermediateDirectories: true
        )

        try touch(directory.appendingPathComponent("older.txt"), date: Date(timeIntervalSince1970: 100))
        try touch(directory.appendingPathComponent("newer.md"), date: Date(timeIntervalSince1970: 300))
        try touch(directory.appendingPathComponent("upper.MD"), date: Date(timeIntervalSince1970: 200))
        try touch(directory.appendingPathComponent("note.markdown"), date: Date(timeIntervalSince1970: 250))
        try touch(directory.appendingPathComponent("plain.text"), date: Date(timeIntervalSince1970: 150))

        let files = try service.sidebarTextFiles()
        let names = files.map(\.fileURL.lastPathComponent)

        #expect(
            names == ["upper.MD", "plain.text", "older.txt", "note.markdown", "noext", "newer.md"]
        )
        try touch(directory.appendingPathComponent("newer.md"), date: .now)
        #expect(try service.sidebarTextFiles().map(\.fileURL.lastPathComponent) == names)
    }

    @Test("sidebar preview excerpt keeps the first three lines")
    func sidebarPreviewExcerptKeepsThreeLines() {
        #expect(DocumentPersistenceService.sidebarPreviewExcerpt(from: "") == "")
        #expect(DocumentPersistenceService.sidebarPreviewExcerpt(from: "  \n  ") == "")
        #expect(DocumentPersistenceService.sidebarPreviewExcerpt(from: "one") == "one")
        #expect(
            DocumentPersistenceService.sidebarPreviewExcerpt(from: "one\ntwo") == "one\ntwo"
        )
        #expect(
            DocumentPersistenceService.sidebarPreviewExcerpt(from: "one\ntwo\nthree\nfour") == "one\ntwo\nthree"
        )
    }

    @Test("sidebar treats CRLF as one line break")
    func excerptHandlesWindowsNewlines() {
        #expect(
            DocumentPersistenceService.sidebarPreviewExcerpt(from: "one\r\ntwo\r\nthree\r\nfour")
                == "one\ntwo\nthree"
        )
    }

    @Test("sidebar distinguishes a missing folder from enumeration failure")
    func enumerationFailureIsNotEmpty() throws {
        let (_, directory) = try makeService()
        defer { try? FileManager.default.removeItem(at: directory) }
        let missingService = DocumentPersistenceService(
            defaultDirectory: directory.appendingPathComponent("missing")
        )
        #expect(try missingService.sidebarTextFiles().isEmpty)

        let notDirectory = directory.appendingPathComponent("file.txt")
        try "not a directory".write(to: notDirectory, atomically: true, encoding: .utf8)
        #expect(throws: (any Error).self) {
            try DocumentPersistenceService(defaultDirectory: notDirectory).sidebarTextFiles()
        }
    }

    @Test("sidebar preview reads a small prefix and tolerates missing files")
    func sidebarPreviewReadsPrefix() throws {
        let (service, directory) = try makeService()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("note.txt")
        try "line1\nline2\nline3\nline4".write(to: url, atomically: true, encoding: .utf8)

        #expect(service.sidebarPreview(for: url) == "line1\nline2\nline3")
        #expect(service.sidebarPreview(for: directory.appendingPathComponent("missing.txt")) == "")
    }

    @Test("renaming a sidebar file moves it and rejects collisions")
    func renameSidebarFileMovesAndRejectsCollisions() throws {
        let (service, directory) = try makeService()
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("a.txt")
        try "x".write(to: source, atomically: true, encoding: .utf8)
        try "y".write(to: directory.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)

        let moved = try service.renameSidebarFile(at: source, to: "c.md")
        #expect(moved.lastPathComponent == "c.md")
        #expect(!FileManager.default.fileExists(atPath: source.path))
        #expect(FileManager.default.fileExists(atPath: moved.path))

        do {
            _ = try service.renameSidebarFile(at: moved, to: "b.txt")
            Issue.record("renaming onto an existing sidebar file must throw")
        } catch is DocumentPersistenceService.PersistenceError {
        }
    }

    @Test("duplicating a sidebar file creates a numbered copy")
    func duplicateSidebarFileCreatesNumberedCopy() throws {
        let (service, directory) = try makeService()
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("note.md")
        try "hello".write(to: source, atomically: true, encoding: .utf8)

        let first = try service.duplicateSidebarFile(at: source)
        #expect(first.lastPathComponent == "note copy.md")
        #expect(try String(contentsOf: first, encoding: .utf8) == "hello")

        let second = try service.duplicateSidebarFile(at: source)
        #expect(second.lastPathComponent == "note copy 2.md")
    }

    @Test("legacy app library documents copy over without overwriting or deleting")
    func legacyAppDocumentsMigrateWithoutOverwriting() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("NeatEditorMigration-\(UUID().uuidString)", isDirectory: true)
        let destination = base.appendingPathComponent("current", isDirectory: true)
        let legacy = base.appendingPathComponent("legacy", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try "legacy note".write(
            to: legacy.appendingPathComponent("old.txt"),
            atomically: true,
            encoding: .utf8
        )
        try "legacy version".write(
            to: legacy.appendingPathComponent("shared.txt"),
            atomically: true,
            encoding: .utf8
        )
        try "current version".write(
            to: destination.appendingPathComponent("shared.txt"),
            atomically: true,
            encoding: .utf8
        )

        let service = DocumentPersistenceService(
            defaultDirectory: destination,
            appLibraryDirectory: legacy
        )

        #expect(service.migrateLegacyAppDocumentsIfNeeded(into: destination) == 1)
        #expect(
            try String(
                contentsOf: destination.appendingPathComponent("old.txt"),
                encoding: .utf8
            ) == "legacy note"
        )
        #expect(
            try String(
                contentsOf: destination.appendingPathComponent("shared.txt"),
                encoding: .utf8
            ) == "current version"
        )
        #expect(
            FileManager.default.fileExists(
                atPath: legacy.appendingPathComponent("old.txt").path
            )
        )
        #expect(service.migrateLegacyAppDocumentsIfNeeded(into: destination) == 0)
    }

    @Test("sidebar visibility defaults to visible and survives encoding")
    func sidebarVisibilityPersists() throws {        #expect(WorkspacePreferences().isSidebarVisible)

        var hidden = WorkspacePreferences()
        hidden.isSidebarVisible = false
        let decoded = try JSONDecoder().decode(
            WorkspacePreferences.self,
            from: JSONEncoder().encode(hidden)
        )
        #expect(!decoded.isSidebarVisible)

        let legacy = try JSONDecoder().decode(
            WorkspacePreferences.self,
            from: JSONEncoder().encode(WorkspacePreferences.EditorTextSoftnessConfiguration())
        )
        #expect(legacy.isSidebarVisible)
    }

    @Test("preview excerpt stays bounded on huge single-line buffers")
    func excerptBoundsHugeBuffers() {
        let huge = String(repeating: "a", count: 100_000)
        #expect(DocumentPersistenceService.sidebarPreviewExcerpt(from: huge).count == 1000)

        let lateNewline = String(repeating: "x", count: 10_000) + "\nsecond"
        #expect(
            DocumentPersistenceService.sidebarPreviewExcerpt(from: lateNewline)
                == String(repeating: "x", count: 1000)
        )
    }
}

@MainActor
struct WorkspaceSidebarReviewTests {
    private func waitForRefresh(_ store: WorkspaceStore) async throws {
        for _ in 0..<200 {
            if !store.isRefreshingSidebar { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Sidebar refresh did not finish")
    }

    private func withStore(
        _ body: (WorkspaceStore, URL) async throws -> Void
    ) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NeatEditorSidebarReview-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("note.txt")
        try "disk text".write(to: fileURL, atomically: true, encoding: .utf8)
        let suite = "NeatEditorSidebarReview-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = WorkspaceStore(
            persistenceService: DocumentPersistenceService(defaultDirectory: directory),
            userDefaults: defaults
        )
        defer {
            store.pendingSaveStateTask?.cancel()
            store.commitEditorChanges = nil
        }
        let tab = EditorTab(title: "note.txt", content: "draft", fileURL: fileURL)
        store.tabs = [tab]
        store.selectedTabID = tab.id
        try await body(store, fileURL)
        try await waitForRefresh(store)
    }

    @Test("refresh applies the current buffer, not the request-time snapshot")
    func refreshDoesNotRevertLivePreview() async throws {
        try await withStore { store, _ in
            let id = try #require(store.selectedTabID)
            store.refreshSidebarFiles()
            store.refreshSidebarFiles()
            store.updateDocumentContent("newest text", for: id)
            try await waitForRefresh(store)
            #expect(store.sidebarFiles.first?.preview == "newest text")
        }
    }

    @Test("unsaved previews never contaminate the disk preview cache")
    func diskCacheIsSeparateFromLiveBuffers() async throws {
        try await withStore { store, _ in
            store.refreshSidebarFiles()
            try await waitForRefresh(store)
            #expect(store.sidebarFiles.first?.preview == "draft")
            store.tabs = []
            store.selectedTabID = nil
            store.refreshSidebarFiles()
            try await waitForRefresh(store)
            #expect(store.sidebarFiles.first?.preview == "disk text")
        }
    }

    @Test("duplicate includes the latest committed editor text")
    func duplicateIncludesUnsavedEdits() async throws {
        try await withStore { store, fileURL in
            let sourceID = try #require(store.selectedTabID)
            store.commitEditorChanges = { id in
                if id == sourceID {
                    store.updateDocumentContent("committed unsaved text", for: id)
                }
            }
            store.duplicateSidebarFile(at: fileURL)
            let copyURL = fileURL.deletingLastPathComponent().appendingPathComponent("note copy.txt")
            #expect(try String(contentsOf: copyURL, encoding: .utf8) == "committed unsaved text")
            #expect(store.tabs.count == 2)
        }
    }

    @Test("refresh failure retains the usable list and exposes an error")
    func failedRefreshPreservesFiles() async throws {
        try await withStore { store, fileURL in
            store.refreshSidebarFiles()
            try await waitForRefresh(store)
            let previous = store.sidebarFiles
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.removeItem(at: directory)
            try "not a directory".write(to: directory, atomically: true, encoding: .utf8)
            store.refreshSidebarFiles()
            try await waitForRefresh(store)
            #expect(store.sidebarFiles == previous)
            #expect(store.sidebarFailureMessage != nil)
        }
    }
}

@MainActor
struct WorkspaceSidebarRefreshTests {
    @Test("unloaded tabs never shadow on-disk previews")
    func unloadedTabsKeepDiskPreview() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NeatEditorSidebarRefreshTests-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("note.txt")
        try "first line\nsecond line\nthird line\nfourth".write(
            to: fileURL,
            atomically: true,
            encoding: .utf8
        )

        let suite = "NeatEditorSidebarRefreshTests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = WorkspaceStore.WorkspaceState(
            tabs: [WorkspaceStore.WorkspaceState.TabState(fileURL: fileURL, isSettings: false)],
            selectedFileURL: fileURL,
            isSettingsSelected: false,
            preferences: WorkspacePreferences()
        )
        defaults.set(try JSONEncoder().encode(state), forKey: WorkspaceStore.UserDefaultsKey.workspaceState)

        let store = WorkspaceStore(
            persistenceService: DocumentPersistenceService(defaultDirectory: directory),
            userDefaults: defaults
        )
        defer { store.pendingSaveStateTask?.cancel() }

        let normalizedURL = store.persistenceService.normalizedFileURL(for: fileURL)

        store.refreshSidebarFiles()
        var preview: String?
        for _ in 0..<100 {
            if let item = store.sidebarFiles.first(where: { $0.fileURL == normalizedURL }),
               !item.preview.isEmpty {
                preview = item.preview
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(preview == "first line\nsecond line\nthird line")
    }
}

@MainActor
struct WorkspaceDocumentsFolderTests {
    private func waitForRefresh(_ store: WorkspaceStore) async throws {
        for _ in 0..<200 {
            if !store.isRefreshingSidebar { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Sidebar refresh did not finish")
    }

    @Test("a chosen documents folder persists in workspace state")
    func chosenFolderPersists() async throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("NeatEditorFolderTests-\(UUID().uuidString)", isDirectory: true)
        let first = base.appendingPathComponent("first", isDirectory: true)
        let second = base.appendingPathComponent("second", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        try "note".write(
            to: first.appendingPathComponent("note.txt"),
            atomically: true,
            encoding: .utf8
        )

        let suite = "NeatEditorFolderTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = DocumentPersistenceService(defaultDirectory: first)

        let store = WorkspaceStore(persistenceService: service, userDefaults: defaults)
        defer { store.pendingSaveStateTask?.cancel() }
        #expect(store.documentsFolder == service.normalizedFileURL(for: first))

        store.setDocumentsFolder(second)
        try await waitForRefresh(store)
        #expect(store.documentsFolder == service.normalizedFileURL(for: second))
        store.flushPendingSaveState()

        let restored = WorkspaceStore(persistenceService: service, userDefaults: defaults)
        defer { restored.pendingSaveStateTask?.cancel() }
        #expect(restored.documentsFolder == service.normalizedFileURL(for: second))
    }

    @Test("new documents save into the current documents folder")
    func newDocumentsSaveIntoCurrentFolder() async throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("NeatEditorFolderSave-\(UUID().uuidString)", isDirectory: true)
        let first = base.appendingPathComponent("first", isDirectory: true)
        let second = base.appendingPathComponent("second", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)

        let suite = "NeatEditorFolderSave-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = DocumentPersistenceService(defaultDirectory: first)

        let store = WorkspaceStore(persistenceService: service, userDefaults: defaults)
        defer { store.pendingSaveStateTask?.cancel() }
        store.setDocumentsFolder(second)
        try await waitForRefresh(store)

        store.createNewDocument()
        let id = try #require(store.selectedTabID)
        store.updateDocumentContent("hello", for: id)
        #expect(store.saveDocument(id: id))

        let fileURL = try #require(store.tabs.first { $0.id == id }?.fileURL)
        #expect(
            fileURL.deletingLastPathComponent()
                == service.normalizedFileURL(for: second)
        )
    }
}
