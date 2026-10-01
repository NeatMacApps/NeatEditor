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

    @Test("first save never overwrites an existing file")
    func firstSaveCollisionKeepsBothFiles() throws {
        let (service, directory) = try makeService()
        let existingURL = directory.appendingPathComponent("Taken.txt")
        try "original\n".write(to: existingURL, atomically: true, encoding: .utf8)

        let saved = try service.save(tab: EditorTab(title: "Taken", content: "new content"))

        #expect(try String(contentsOf: existingURL, encoding: .utf8) == "original\n")
        let savedURL = try #require(saved.fileURL)
        #expect(service.normalizedFileURL(for: savedURL) != service.normalizedFileURL(for: existingURL))
        #expect(try String(contentsOf: savedURL, encoding: .utf8) == "new content")
    }

    @Test("titles containing separators or blank names are rejected without writing")
    func invalidTitleRejectedWithoutWriting() throws {
        let (service, directory) = try makeService()

        for badTitle in ["a/b", "..", "", "   "] {
            do {
                _ = try service.save(tab: EditorTab(title: badTitle, content: "x"))
                Issue.record("saving title \(badTitle) must throw")
            } catch let error as CocoaError where error.code == .fileWriteInvalidFileName {
            } catch {
                Issue.record("wrong error for title \(badTitle): \(error)")
            }
        }

        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(files.isEmpty)
    }

    @Test("renaming onto a path separator is rejected and the file is kept")
    func renameSeparatorRejected() throws {
        let (service, _) = try makeService()
        let saved = try service.save(tab: EditorTab(title: "keep", content: "v"))

        do {
            _ = try service.rename(tab: saved, to: "sub/dir.txt")
            Issue.record("renaming onto a separator must throw")
        } catch let error as CocoaError where error.code == .fileWriteInvalidFileName {
        } catch {
            Issue.record("wrong error for separator rename: \(error)")
        }

        #expect(FileManager.default.fileExists(atPath: saved.fileURL!.path))
    }

    @Test("blank saves never create the documents directory")
    func blankSaveCreatesNoDirectory() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("NeatEditorTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let missingDirectory = base.appendingPathComponent("docs", isDirectory: true)
        let service = DocumentPersistenceService(defaultDirectory: missingDirectory)

        let saved = try service.save(tab: EditorTab(title: "Untitled 1", content: "  \n "))

        #expect(saved.fileURL == nil)
        #expect(!FileManager.default.fileExists(atPath: missingDirectory.path))
    }

    @Test("first nonblank save creates the documents directory")
    func firstSaveCreatesDirectory() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("NeatEditorTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let missingDirectory = base.appendingPathComponent("docs", isDirectory: true)
        let service = DocumentPersistenceService(defaultDirectory: missingDirectory)

        let saved = try service.save(tab: EditorTab(title: "Untitled 1", content: "hello"))

        let savedURL = try #require(saved.fileURL)
        #expect(try String(contentsOf: savedURL, encoding: .utf8) == "hello")
    }

    @Test("default directory follows XDG_CONFIG_HOME")
    func defaultDirectoryRespectsXDG() throws {
        let xdgHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("NeatEditorXDG-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: xdgHome, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: xdgHome) }

        let previous = getenv("XDG_CONFIG_HOME").map { String(cString: $0) }
        setenv("XDG_CONFIG_HOME", xdgHome.path, 1)
        defer {
            if let previous {
                setenv("XDG_CONFIG_HOME", previous, 1)
            } else {
                unsetenv("XDG_CONFIG_HOME")
            }
        }

        #expect(
            DocumentPersistenceService().defaultDirectory.path
                == xdgHome.appendingPathComponent("neateditor/documents", isDirectory: true).path
        )

        unsetenv("XDG_CONFIG_HOME")
        #expect(
            DocumentPersistenceService().defaultDirectory.path
                .hasSuffix(".config/neateditor/documents")
        )
    }
}
