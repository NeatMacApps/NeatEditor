import Foundation
import Testing
@testable import NeatEditor

@MainActor
@Suite("SecurityScopedBookmarkStore")
struct SecurityScopedBookmarkStoreTests {
    private func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "com.caozc.NeatEditor.tests.bookmarks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }

    private func makeTempDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NeatEditorBookmarkTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("Stores and restores documents folder bookmark across store instances")
    func storesAndRestoresDocumentsFolder() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let folder = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }

        let writer = SecurityScopedBookmarkStore(userDefaults: defaults)
        writer.storeAndActivateDocumentsFolder(folder)
        writer.releaseAll()

        let reader = SecurityScopedBookmarkStore(userDefaults: defaults)
        let restored = reader.restoreAndActivateDocumentsFolder()
        reader.releaseAll()

        #expect(restored == folder.standardizedFileURL.resolvingSymlinksInPath())
    }

    @Test("Stores, restores, and prunes individual file bookmarks")
    func storesRestoresAndPrunesFileBookmarks() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileA = dir.appendingPathComponent("a.txt")
        let fileB = dir.appendingPathComponent("b.txt")
        try "alpha".write(to: fileA, atomically: true, encoding: .utf8)
        try "beta".write(to: fileB, atomically: true, encoding: .utf8)

        let store = SecurityScopedBookmarkStore(userDefaults: defaults)
        store.storeAndActivateFile(fileA)
        store.storeAndActivateFile(fileB)
        store.pruneFileBookmarks(keeping: [fileA])
        store.releaseAll()

        let reopened = SecurityScopedBookmarkStore(userDefaults: defaults)
        #expect(reopened.restoreAndActivateFile(for: fileA) == fileA.standardizedFileURL.resolvingSymlinksInPath())
        #expect(reopened.restoreAndActivateFile(for: fileB) == nil)
        reopened.releaseAll()
    }

    @Test("Removes stale bookmark when target file no longer exists")
    func removesMissingFileBookmark() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appendingPathComponent("ephemeral.txt")
        try "temp".write(to: file, atomically: true, encoding: .utf8)

        let store = SecurityScopedBookmarkStore(userDefaults: defaults)
        store.storeAndActivateFile(file)
        store.releaseAll()

        try FileManager.default.removeItem(at: file)

        let reopened = SecurityScopedBookmarkStore(userDefaults: defaults)
        #expect(reopened.restoreAndActivateFile(for: file) == nil)
        reopened.releaseAll()
    }
}
