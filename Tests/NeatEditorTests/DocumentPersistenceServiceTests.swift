import Foundation
import Synchronization
import Testing

@testable import NeatEditor

/// Rejects hard links with ENOTSUP while copy and native rename stay
/// available. Stateless, so the inherited unchecked conformance stays safe.
private final class LinkUnsupportedFileManager: FileManager, @unchecked Sendable {
    override func linkItem(at srcURL: URL, to dstURL: URL) throws {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(ENOTSUP), userInfo: [NSFilePathErrorKey: dstURL.path])
    }
}

/// Plants a different-bytes competitor at the first candidate before link.
/// Exclusive claim must fail EEXIST; retry preserves both. Immutable
/// configuration only, so the inherited unchecked conformance stays safe.
private final class PlantRacerLinkManager: FileManager, @unchecked Sendable {
    let firstCandidate: String
    init(firstCandidate: String) {
        self.firstCandidate = firstCandidate
        super.init()
    }
    override func linkItem(at srcURL: URL, to dstURL: URL) throws {
        if dstURL.lastPathComponent == firstCandidate {
            try? Data("RACER".utf8).write(to: dstURL, options: .withoutOverwriting)
        }
        try super.linkItem(at: srcURL, to: dstURL)
    }
}

/// Fails hard-link publication with a non-capability I/O error. Stateless,
/// so the inherited unchecked conformance stays safe. Publication must
/// propagate this error without trying the rename fallback.
private final class NonCapabilityLinkManager: FileManager, @unchecked Sendable {
    override func linkItem(at srcURL: URL, to dstURL: URL) throws {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES), userInfo: [NSFilePathErrorKey: dstURL.path])
    }
}

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

    @Test("default documents folder is the user's Documents directory")
    func defaultDirectoryIsUserDocuments() {
        let expected = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents", isDirectory: true)
        #expect(DocumentPersistenceService().defaultDirectory.path == expected.path)
    }

    @Test("legacy app library follows XDG_CONFIG_HOME")
    func appLibraryRespectsXDG() throws {
        let xdgHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("NeatEditorXDG-\(UUID().uuidString)", isDirectory: true)

        #expect(
            DocumentPersistenceService(environment: ["XDG_CONFIG_HOME": xdgHome.path])
                .appLibraryDirectory.path
                == xdgHome.appendingPathComponent("neateditor/documents", isDirectory: true).path
        )

        #expect(
            DocumentPersistenceService(environment: [:]).appLibraryDirectory.path
                .hasSuffix(".config/neateditor/documents")
        )

        #expect(
            DocumentPersistenceService(environment: ["XDG_CONFIG_HOME": "relative/path"])
                .appLibraryDirectory.path.hasSuffix(".config/neateditor/documents")
        )
    }

    @Test("exclusive link publishes complete bytes on a supporting volume")
    func duplicateViaExclusiveLink() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NeatEditorExcl-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("note.txt")
        let payload = "complete bytes 中文 👨‍👩‍👧‍👦\n"
        try payload.write(to: source, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: source.path)
        let sourcePermissions = try FileManager.default.attributesOfItem(atPath: source.path)[.posixPermissions] as? Int

        let service = DocumentPersistenceService(defaultDirectory: directory)
        let duplicate = try service.duplicateSidebarFile(at: source)

        #expect(duplicate.lastPathComponent == "note copy.txt")
        #expect(try String(contentsOf: duplicate, encoding: .utf8) == payload)
        #expect(try String(contentsOf: source, encoding: .utf8) == payload)
        #expect(try FileManager.default.attributesOfItem(atPath: source.path)[.posixPermissions] as? Int == sourcePermissions)
        let duplicatePermissions = try FileManager.default.attributesOfItem(atPath: duplicate.path)[.posixPermissions] as? Int
        #expect(duplicatePermissions == sourcePermissions)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix(".neateditor-staging-") }
        #expect(leftovers.isEmpty)
    }

    @Test("hard-link rejection falls through to exclusive rename")
    func duplicateFallsBackToExclusiveRename() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NeatEditorNoLink-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("note.txt")
        let payload = "complete bytes 中文 👨‍👩‍👧‍👦\n"
        try payload.write(to: source, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: source.path)

        let linkless = LinkUnsupportedFileManager()
        #expect(throws: (any Error).self) { try linkless.linkItem(at: source, to: directory.appendingPathComponent("probe.txt")) }
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("probe.txt").path))

        // Native RENAME_EXCL still publishes exclusively on APFS.
        let service = DocumentPersistenceService(fileManager: linkless, defaultDirectory: directory)
        let duplicate = try service.duplicateSidebarFile(at: source)

        #expect(duplicate.lastPathComponent == "note copy.txt")
        #expect(try String(contentsOf: duplicate, encoding: .utf8) == payload)
        #expect(try String(contentsOf: source, encoding: .utf8) == payload)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix(".neateditor-staging-") }
        #expect(leftovers.isEmpty)
    }

    @Test("unsupported exclusive primitives fail closed without overwriting")
    func duplicateFailsClosedWhenExclusiveUnsupported() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NeatEditorNoExcl-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("doc.txt")
        try "original".write(to: source, atomically: true, encoding: .utf8)
        let preexisting = directory.appendingPathComponent("doc copy.txt")
        try "kept".write(to: preexisting, atomically: true, encoding: .utf8)

        let linkless = LinkUnsupportedFileManager()
        let unsupportedRename: @Sendable (URL, URL) throws -> Void = { _, dst in
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(ENOTSUP), userInfo: [NSFilePathErrorKey: dst.path])
        }
        let service = DocumentPersistenceService(
            fileManager: linkless, defaultDirectory: directory, exclusiveRename: unsupportedRename
        )
        do {
            _ = try service.duplicateSidebarFile(at: source)
            Issue.record("unsupported exclusive publication must throw instead of overwriting")
        } catch {
            let nsError = error as NSError
            #expect(nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(ENOTSUP))
        }
        // Fail closed: preexisting preserved, no new copy, source intact, staging cleaned.
        #expect(try String(contentsOf: preexisting, encoding: .utf8) == "kept")
        #expect(try String(contentsOf: source, encoding: .utf8) == "original")
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("doc copy 2.txt").path))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix(".neateditor-staging-") }
        #expect(leftovers.isEmpty)
    }

    @Test("duplication never overwrites a pre-existing destination")
    func duplicateNeverOverwritesPreexisting() throws {
        let (service, directory) = try makeService()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("doc.txt")
        try "original".write(to: source, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: source.path)
        let existing = directory.appendingPathComponent("doc copy.txt")
        try "existing copy".write(to: existing, atomically: true, encoding: .utf8)

        let duplicate = try service.duplicateSidebarFile(at: source)

        #expect(duplicate.lastPathComponent == "doc copy 2.txt")
        #expect(try String(contentsOf: duplicate, encoding: .utf8) == "original")
        #expect(try String(contentsOf: existing, encoding: .utf8) == "existing copy")
        #expect(try String(contentsOf: source, encoding: .utf8) == "original")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix(".neateditor-staging-") }
        #expect(leftovers.isEmpty)
    }

    @Test("duplication advances through numbered collisions")
    func duplicateAdvancesThroughCollisions() throws {
        let (service, directory) = try makeService()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("record.md")
        try "v1".write(to: source, atomically: true, encoding: .utf8)
        try "kept-1".write(to: directory.appendingPathComponent("record copy.md"), atomically: true, encoding: .utf8)
        try "kept-2".write(to: directory.appendingPathComponent("record copy 2.md"), atomically: true, encoding: .utf8)

        let duplicate = try service.duplicateSidebarFile(at: source)

        #expect(duplicate.lastPathComponent == "record copy 3.md")
        #expect(try String(contentsOf: duplicate, encoding: .utf8) == "v1")
        #expect(try String(contentsOf: directory.appendingPathComponent("record copy.md"), encoding: .utf8) == "kept-1")
        #expect(try String(contentsOf: directory.appendingPathComponent("record copy 2.md"), encoding: .utf8) == "kept-2")
        #expect(try String(contentsOf: source, encoding: .utf8) == "v1")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix(".neateditor-staging-") }
        #expect(leftovers.isEmpty)
    }

    @Test("racing competitor at the link primitive is preserved")
    func racingCompetitorPreservedViaLink() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NeatEditorRaceLink-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("doc.txt")
        try "STAGED".write(to: source, atomically: true, encoding: .utf8)

        let racer = PlantRacerLinkManager(firstCandidate: "doc copy.txt")
        let service = DocumentPersistenceService(fileManager: racer, defaultDirectory: directory)
        let duplicate = try service.duplicateSidebarFile(at: source)

        // Competitor planted immediately before linkItem keeps different bytes;
        // the exclusive claim fails EEXIST and the retry publishes elsewhere.
        #expect(try String(contentsOf: directory.appendingPathComponent("doc copy.txt"), encoding: .utf8) == "RACER")
        #expect(duplicate.lastPathComponent == "doc copy 2.txt")
        #expect(try String(contentsOf: duplicate, encoding: .utf8) == "STAGED")
        #expect(try String(contentsOf: source, encoding: .utf8) == "STAGED")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix(".neateditor-staging-") }
        #expect(leftovers.isEmpty)
    }

    @Test("racing competitor at the exclusive rename is preserved")
    func racingCompetitorPreservedViaRename() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NeatEditorRaceRename-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("note.txt")
        try "STAGED".write(to: source, atomically: true, encoding: .utf8)

        let linkless = LinkUnsupportedFileManager()
        let racerRename: @Sendable (URL, URL) throws -> Void = { src, dst in
            if dst.lastPathComponent == "note copy.txt" {
                try? Data("RACER".utf8).write(to: dst, options: .withoutOverwriting)
            }
            try DocumentPersistenceService.nativeExclusiveRename(src, dst)
        }
        let service = DocumentPersistenceService(
            fileManager: linkless, defaultDirectory: directory, exclusiveRename: racerRename
        )
        let duplicate = try service.duplicateSidebarFile(at: source)

        #expect(try String(contentsOf: directory.appendingPathComponent("note copy.txt"), encoding: .utf8) == "RACER")
        #expect(duplicate.lastPathComponent == "note copy 2.txt")
        #expect(try String(contentsOf: duplicate, encoding: .utf8) == "STAGED")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix(".neateditor-staging-") }
        #expect(leftovers.isEmpty)
    }

    @Test("failed staged publication cleans up without publishing")
    func failedStagedPublicationCleansUp() throws {
        let (service, directory) = try makeService()
        defer { try? FileManager.default.removeItem(at: directory) }

        do {
            _ = try service.publishStagedFile(named: "never.txt", in: directory) { stagingURL in
                try Data("partial".utf8).write(to: stagingURL, options: .withoutOverwriting)
                throw CocoaError(.fileWriteNoPermission)
            }
            Issue.record("a throwing write must propagate")
        } catch let error as CocoaError {
            #expect(error.code == .fileWriteNoPermission)
        }
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("never.txt").path))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix(".neateditor-staging-") }
        #expect(leftovers.isEmpty)
    }

    @Test("fresh rename claims destination exclusively and notifies before move")
    func renameFreshClaimsExclusively() throws {
        let (service, _) = try makeService()
        let saved = try service.save(tab: EditorTab(title: "orig", content: "fresh-bytes"))
        let sourceURL = try #require(saved.fileURL)
        var notified: [(URL, URL)] = []

        let renamed = try service.moveDocumentFile(tab: saved, to: "renamed.txt", beforeMove: { src, dst in
            notified.append((src, dst))
        })

        #expect(notified.count == 1)
        #expect(notified[0].0 == service.normalizedFileURL(for: sourceURL))
        #expect(notified[0].1.lastPathComponent == "renamed.txt")
        #expect(renamed.id == saved.id)
        #expect(renamed.title == "renamed.txt")
        #expect(renamed.fileURL?.lastPathComponent == "renamed.txt")
        #expect(renamed.content == "fresh-bytes")
        #expect(!FileManager.default.fileExists(atPath: sourceURL.path))
        #expect(try String(contentsOf: #require(renamed.fileURL), encoding: .utf8) == "fresh-bytes")
    }

    @Test("rename onto pre-existing name throws and preserves both files")
    func renamePreexistingPreservesBoth() throws {
        let (service, _) = try makeService()
        let first = try service.save(tab: EditorTab(title: "a", content: "SOURCE-BYTES"))
        let second = try service.save(tab: EditorTab(title: "b", content: "COMPETITOR-BYTES"))
        let firstURL = try #require(first.fileURL)
        let secondURL = try #require(second.fileURL)
        var notified = 0

        do {
            _ = try service.moveDocumentFile(tab: first, to: "b.txt", beforeMove: { _, _ in notified += 1 })
            Issue.record("renaming onto an existing file must throw")
        } catch let error as DocumentPersistenceService.PersistenceError {
            guard case .destinationAlreadyExists(let url) = error else {
                Issue.record("wrong persistence error: \(error)")
                return
            }
            #expect(url.lastPathComponent == "b.txt")
        }
        #expect(try String(contentsOf: firstURL, encoding: .utf8) == "SOURCE-BYTES")
        #expect(try String(contentsOf: secondURL, encoding: .utf8) == "COMPETITOR-BYTES")
        #expect(FileManager.default.fileExists(atPath: firstURL.path))
        #expect(FileManager.default.fileExists(atPath: secondURL.path))
        #expect(notified == 0)
        #expect(first.fileURL == firstURL)
    }

    @Test("rename racing competitor with different bytes is preserved")
    func renameRacedTargetPreserved() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NeatEditorRaceRename-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let base = DocumentPersistenceService(defaultDirectory: directory)
        let saved = try base.save(tab: EditorTab(title: "orig", content: "STAGED"))
        let sourceURL = try #require(saved.fileURL)
        var notified: [(URL, URL)] = []
        let racerRename: @Sendable (URL, URL) throws -> Void = { src, dst in
            if dst.lastPathComponent == "renamed.txt" {
                try? Data("RACER".utf8).write(to: dst, options: .withoutOverwriting)
            }
            try DocumentPersistenceService.nativeExclusiveRename(src, dst)
        }
        let racerService = DocumentPersistenceService(defaultDirectory: directory, exclusiveRename: racerRename)

        do {
            _ = try racerService.moveDocumentFile(tab: saved, to: "renamed.txt", beforeMove: { src, dst in
                notified.append((src, dst))
            })
            Issue.record("raced rename must throw instead of overwriting")
        } catch let error as DocumentPersistenceService.PersistenceError {
            guard case .destinationAlreadyExists = error else {
                Issue.record("wrong persistence error: \(error)")
                return
            }
        }
        #expect(try String(contentsOf: directory.appendingPathComponent("renamed.txt"), encoding: .utf8) == "RACER")
        #expect(try String(contentsOf: sourceURL, encoding: .utf8) == "STAGED")
        #expect(FileManager.default.fileExists(atPath: sourceURL.path))
        #expect(notified.count == 1)
        #expect(saved.fileURL == sourceURL)
    }

    @Test("unsupported rename fails closed without creating destination")
    func renameUnsupportedFailsClosed() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NeatEditorRenameNoExcl-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let base = DocumentPersistenceService(defaultDirectory: directory)
        let saved = try base.save(tab: EditorTab(title: "orig", content: "hello"))
        let sourceURL = try #require(saved.fileURL)
        let unsupported: @Sendable (URL, URL) throws -> Void = { _, dst in
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(ENOTSUP), userInfo: [NSFilePathErrorKey: dst.path])
        }
        let service = DocumentPersistenceService(defaultDirectory: directory, exclusiveRename: unsupported)
        var notified = 0

        do {
            _ = try service.moveDocumentFile(tab: saved, to: "fresh.txt", beforeMove: { _, _ in notified += 1 })
            Issue.record("unsupported rename must throw instead of overwriting")
        } catch {
            let nsError = error as NSError
            #expect(nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(ENOTSUP))
        }
        #expect(try String(contentsOf: sourceURL, encoding: .utf8) == "hello")
        #expect(FileManager.default.fileExists(atPath: sourceURL.path))
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("fresh.txt").path))
        #expect(notified == 1)
    }

    @Test("non-capability link error never tries rename fallback")
    func nonCapabilityLinkErrorSkipsRenameFallback() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NeatEditorNonCap-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("doc.txt")
        try "original".write(to: source, atomically: true, encoding: .utf8)

        let invoked = Mutex(false)
        let renameOverride: @Sendable (URL, URL) throws -> Void = { src, dst in
            invoked.withLock { $0 = true }
            try DocumentPersistenceService.nativeExclusiveRename(src, dst)
        }
        let service = DocumentPersistenceService(
            fileManager: NonCapabilityLinkManager(), defaultDirectory: directory, exclusiveRename: renameOverride
        )
        do {
            _ = try service.duplicateSidebarFile(at: source)
            Issue.record("non-capability link failure must propagate")
        } catch {
            let nsError = error as NSError
            #expect(nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(EACCES))
        }
        #expect(invoked.withLock { $0 } == false)
        #expect(try String(contentsOf: source, encoding: .utf8) == "original")
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("doc copy.txt").path))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix(".neateditor-staging-") }
        #expect(leftovers.isEmpty)
    }
}
