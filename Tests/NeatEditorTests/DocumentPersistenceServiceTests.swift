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

    @Test("default document names follow local creation time across year boundaries")
    func defaultNameUsesLocalTime() throws {
        let (service, directory) = try makeService()
        defer { try? FileManager.default.removeItem(at: directory) }
        let date = try #require(ISO8601DateFormatter().date(from: "2025-12-31T16:05:09Z"))
        let timeZone = try #require(TimeZone(secondsFromGMT: 8 * 60 * 60))

        let name = service.defaultDocumentName(existingTabs: [], date: date, timeZone: timeZone)

        #expect(name == "20260101-000509")
    }

    @Test("same-second new documents avoid unsaved and saved tab names")
    func sameSecondNamesRemainUnique() throws {
        let (service, directory) = try makeService()
        defer { try? FileManager.default.removeItem(at: directory) }
        let date = try #require(ISO8601DateFormatter().date(from: "2026-10-01T14:25:30Z"))
        let timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let base = service.defaultDocumentName(existingTabs: [], date: date, timeZone: timeZone)
        var tabs = [EditorTab(title: base)]
        let second = service.defaultDocumentName(existingTabs: tabs, date: date, timeZone: timeZone)
        tabs.append(try service.save(tab: EditorTab(title: second, content: "second")))

        let third = service.defaultDocumentName(existingTabs: tabs, date: date, timeZone: timeZone)

        #expect(base == "20261001-142530")
        #expect(second == "20261001-142530-2")
        #expect(third == "20261001-142530-3")
    }

    @Test("saving a dated document keeps its creation name and preserves disk collisions")
    func saveDatedNamePreservesExistingFile() throws {
        let (service, directory) = try makeService()
        defer { try? FileManager.default.removeItem(at: directory) }
        let date = try #require(ISO8601DateFormatter().date(from: "2026-10-01T14:25:30Z"))
        let timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let name = service.defaultDocumentName(existingTabs: [], date: date, timeZone: timeZone)
        let first = try service.save(tab: EditorTab(title: name, content: "original"))
        let second = try service.save(tab: EditorTab(title: name, content: "new"))

        #expect(first.title == "20261001-142530.txt")
        #expect(second.fileURL != first.fileURL)
        #expect(try String(contentsOf: #require(first.fileURL), encoding: .utf8) == "original")
        #expect(try String(contentsOf: #require(second.fileURL), encoding: .utf8) == "new")
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

        #expect(FileManager.default.fileExists(atPath: (try #require(saved.fileURL)).path))
    }

    @Test("renaming a tab whose file disappeared fails without changing the tab")
    func renameMissingSourceFailsWithoutChangingTab() throws {
        let (service, _) = try makeService()
        let saved = try service.save(tab: EditorTab(title: "gone", content: "v"))
        let savedURL = try #require(saved.fileURL)
        try FileManager.default.removeItem(at: savedURL)

        do {
            _ = try service.rename(tab: saved, to: "elsewhere.txt")
            Issue.record("renaming a missing source must throw")
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
        } catch {
            Issue.record("wrong error for missing source rename: \(error)")
        }
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
        let directoryPermissions = try FileManager.default.attributesOfItem(
            atPath: missingDirectory.path
        )[.posixPermissions] as? Int
        #expect(directoryPermissions == 0o700)
        let filePermissions = try FileManager.default.attributesOfItem(
            atPath: savedURL.path
        )[.posixPermissions] as? Int
        #expect(filePermissions == 0o600)
    }

    @Test("repeated first-save collisions keep every original and publish complete data")
    func repeatedFirstSaveCollisions() throws {
        let (service, directory) = try makeService()
        let firstURL = directory.appendingPathComponent("Taken.txt")
        let secondURL = directory.appendingPathComponent("Taken 2.txt")
        try "first-original".write(to: firstURL, atomically: true, encoding: .utf8)
        try "second-original".write(to: secondURL, atomically: true, encoding: .utf8)
        let payload = String(repeating: "complete-data\n", count: 1000)

        let saved = try service.save(tab: EditorTab(title: "Taken", content: payload))
        let savedURL = try #require(saved.fileURL)

        #expect(try String(contentsOf: firstURL, encoding: .utf8) == "first-original")
        #expect(try String(contentsOf: secondURL, encoding: .utf8) == "second-original")
        #expect(savedURL.lastPathComponent == "Taken 3.txt")
        #expect(try String(contentsOf: savedURL, encoding: .utf8) == payload)
        let stagingLeftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix(".neateditor-staging-") }
        #expect(stagingLeftovers.isEmpty)
        let filePermissions = try FileManager.default.attributesOfItem(
            atPath: savedURL.path
        )[.posixPermissions] as? Int
        #expect(filePermissions == 0o600)
    }

    @Test("default directory follows XDG_CONFIG_HOME")
    func defaultDirectoryRespectsXDG() throws {
        let xdgHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("NeatEditorXDG-\(UUID().uuidString)", isDirectory: true)

        #expect(
            DocumentPersistenceService(environment: ["XDG_CONFIG_HOME": xdgHome.path])
                .defaultDirectory.path
                == xdgHome.appendingPathComponent("neateditor/documents", isDirectory: true).path
        )

        #expect(
            DocumentPersistenceService(environment: [:]).defaultDirectory.path
                .hasSuffix(".config/neateditor/documents")
        )

        #expect(
            DocumentPersistenceService(environment: ["XDG_CONFIG_HOME": "relative/path"])
                .defaultDirectory.path.hasSuffix(".config/neateditor/documents")
        )
    }
}
