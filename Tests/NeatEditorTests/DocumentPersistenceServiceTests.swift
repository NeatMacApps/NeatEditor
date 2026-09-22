import Foundation
import Testing

@testable import NeatEditor

/// Persistence regression tests: saving must never write placeholder or
/// blank content over a real file, and rename must keep title/URL coherent.
struct DocumentPersistenceServiceTests {
    private func makeService() throws -> (DocumentPersistenceService, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NeatEditorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (DocumentPersistenceService(defaultDirectory: directory), directory)
    }

    @Test("saving a new tab creates a file and adopts its name")
    func saveNewTabCreatesFile() throws {
        let (service, directory) = try makeService()
        let tab = EditorTab(title: "Untitled 1", content: "hello\n")

        let saved = try service.save(tab: tab)

        #expect(saved.fileURL != nil)
        #expect(saved.title.hasSuffix(".txt"))
        #expect(FileManager.default.fileExists(atPath: saved.fileURL!.path))
        let onDisk = try String(contentsOf: saved.fileURL!, encoding: .utf8)
        #expect(onDisk == "hello\n")
        _ = directory
    }

    @Test("blank content is never written to disk")
    func blankContentNotPersisted() throws {
        let (service, directory) = try makeService()
        let tab = EditorTab(title: "Untitled 1", content: "   \n  ")

        let saved = try service.save(tab: tab)

        #expect(saved.fileURL == nil)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(files.isEmpty)
    }

    @Test("saving an existing file keeps its URL and updates content")
    func saveExistingFile() throws {
        let (service, _) = try makeService()
        let first = try service.save(tab: EditorTab(title: "notes", content: "v1"))

        let second = try service.save(
            tab: EditorTab(title: first.title, content: "v1\nv2", fileURL: first.fileURL)
        )

        #expect(second.fileURL == first.fileURL)
        let onDisk = try String(contentsOf: first.fileURL!, encoding: .utf8)
        #expect(onDisk == "v1\nv2")
    }

    @Test("renaming an unsaved tab only changes the title")
    func renameUnsavedTab() throws {
        let (service, _) = try makeService()
        let renamed = try service.rename(tab: EditorTab(title: "a", content: "x"), to: "b")

        #expect(renamed.title == "b")
        #expect(renamed.fileURL == nil)
        #expect(renamed.content == "x")
    }

    @Test("renaming a saved file moves it on disk")
    func renameSavedFileMovesOnDisk() throws {
        let (service, _) = try makeService()
        let saved = try service.save(tab: EditorTab(title: "a", content: "x"))

        let renamed = try service.rename(tab: saved, to: "b.txt")

        #expect(renamed.fileURL?.lastPathComponent == "b.txt")
        #expect(!FileManager.default.fileExists(atPath: saved.fileURL!.path))
        #expect(FileManager.default.fileExists(atPath: renamed.fileURL!.path))
    }

    @Test("renaming onto an existing name throws instead of overwriting")
    func renameCollisionThrows() throws {
        let (service, _) = try makeService()
        let first = try service.save(tab: EditorTab(title: "a", content: "x"))
        _ = try service.save(tab: EditorTab(title: "b", content: "y"))

        do {
            _ = try service.rename(tab: first, to: "b.txt")
            Issue.record("renaming onto an existing file must throw")
        } catch is DocumentPersistenceService.PersistenceError {
        }
    }

    @Test("lazily opened documents start empty and unloaded")
    func lazyOpenStartsUnloaded() throws {
        let (service, directory) = try makeService()
        let fileURL = directory.appendingPathComponent("doc.txt")
        try "content".write(to: fileURL, atomically: true, encoding: .utf8)

        let tab = service.openDocumentLazily(at: fileURL)

        #expect(tab.content.isEmpty)
        #expect(!tab.isContentLoaded)
        #expect(tab.fileURL != nil)
    }
}
