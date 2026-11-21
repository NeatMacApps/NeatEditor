import Foundation
import OSLog

/// Persists and activates app-scoped security-scoped bookmarks for user-selected
/// folders and externally opened files so sandboxed Mac App Store builds keep
/// access across relaunches with balanced `startAccessing` / `stopAccessing` calls.
@MainActor
final class SecurityScopedBookmarkStore {
    private enum StorageKey {
        static let documentsFolderBookmark = "SecurityScopedDocumentsFolderBookmark"
        static let fileBookmarks = "SecurityScopedFileBookmarks"
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.caozc.NeatEditor",
        category: "SecurityScopedBookmarks"
    )

    private let userDefaults: UserDefaults
    private var activeFolderURL: URL?
    private var activeFileURLs: [String: URL] = [:]

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    deinit {
        if let activeFolderURL {
            activeFolderURL.stopAccessingSecurityScopedResource()
        }
        for url in activeFileURLs.values {
            url.stopAccessingSecurityScopedResource()
        }
    }

    // MARK: - Documents Folder

    /// Persists a bookmark for the user-selected documents folder and activates
    /// security-scoped access for it, releasing any previously active folder.
    func storeAndActivateDocumentsFolder(_ url: URL) {
        let normalized = normalizedURL(for: url)
        let bookmarkData = makeBookmarkData(for: normalized)
        if let bookmarkData {
            userDefaults.set(bookmarkData, forKey: StorageKey.documentsFolderBookmark)
        } else {
            userDefaults.removeObject(forKey: StorageKey.documentsFolderBookmark)
        }
        replaceActiveFolder(with: normalized)
    }

    /// Resolves and activates the previously bookmarked documents folder, if any.
    /// Returns the resolved URL (refreshing a stale bookmark in place) or `nil`
    /// when no valid bookmark is stored.
    func restoreAndActivateDocumentsFolder() -> URL? {
        guard let data = userDefaults.data(forKey: StorageKey.documentsFolderBookmark) else {
            return nil
        }
        guard let resolved = resolveBookmark(data) else {
            userDefaults.removeObject(forKey: StorageKey.documentsFolderBookmark)
            return nil
        }
        if resolved.isStale, let refreshed = makeBookmarkData(for: resolved.url) {
            userDefaults.set(refreshed, forKey: StorageKey.documentsFolderBookmark)
        }
        replaceActiveFolder(with: resolved.url)
        return resolved.url
    }

    func clearDocumentsFolderBookmark() {
        userDefaults.removeObject(forKey: StorageKey.documentsFolderBookmark)
        releaseActiveFolder()
    }

    // MARK: - Individual Files

    /// Persists a bookmark for an externally opened or saved file and activates
    /// security-scoped access while the tab remains open.
    func storeAndActivateFile(_ url: URL) {
        let normalized = normalizedURL(for: url)
        let key = normalized.path
        if let data = makeBookmarkData(for: normalized) {
            var stored = storedFileBookmarks()
            stored[key] = data
            userDefaults.set(stored, forKey: StorageKey.fileBookmarks)
        }
        activateFile(normalized, key: key)
    }

    /// Resolves and activates a stored bookmark matching `url` on relaunch.
    /// Returns the resolved URL when a valid bookmark exists, or `nil`.
    func restoreAndActivateFile(for url: URL) -> URL? {
        let normalized = normalizedURL(for: url)
        let key = normalized.path
        var stored = storedFileBookmarks()
        guard let data = stored[key] else {
            return nil
        }
        guard let resolved = resolveBookmark(data) else {
            stored.removeValue(forKey: key)
            userDefaults.set(stored, forKey: StorageKey.fileBookmarks)
            return nil
        }
        if resolved.isStale, let refreshed = makeBookmarkData(for: resolved.url) {
            stored[resolved.url.path] = refreshed
            if resolved.url.path != key {
                stored.removeValue(forKey: key)
            }
            userDefaults.set(stored, forKey: StorageKey.fileBookmarks)
        }
        activateFile(resolved.url, key: resolved.url.path)
        return resolved.url
    }

    /// Releases security-scoped access for a closed file and prunes its stored bookmark
    /// when `removeStoredBookmark` is true.
    func releaseFile(_ url: URL, removeStoredBookmark: Bool = false) {
        let key = normalizedURL(for: url).path
        if let active = activeFileURLs.removeValue(forKey: key) {
            active.stopAccessingSecurityScopedResource()
        }
        if removeStoredBookmark {
            var stored = storedFileBookmarks()
            if stored.removeValue(forKey: key) != nil {
                userDefaults.set(stored, forKey: StorageKey.fileBookmarks)
            }
        }
    }

    /// Prunes stored file bookmarks that are no longer referenced by open tabs.
    func pruneFileBookmarks(keeping urls: [URL]) {
        let keptKeys = Set(urls.map { normalizedURL(for: $0).path })
        var stored = storedFileBookmarks()
        let originalCount = stored.count
        stored = stored.filter { keptKeys.contains($0.key) }
        if stored.count != originalCount {
            userDefaults.set(stored, forKey: StorageKey.fileBookmarks)
        }
        for (key, url) in activeFileURLs where !keptKeys.contains(key) {
            url.stopAccessingSecurityScopedResource()
            activeFileURLs.removeValue(forKey: key)
        }
    }

    func releaseAll() {
        releaseActiveFolder()
        for url in activeFileURLs.values {
            url.stopAccessingSecurityScopedResource()
        }
        activeFileURLs.removeAll()
    }

    // MARK: - Helpers

    private func replaceActiveFolder(with url: URL) {
        if activeFolderURL == url {
            return
        }
        releaseActiveFolder()
        if url.startAccessingSecurityScopedResource() {
            activeFolderURL = url
        }
    }

    private func releaseActiveFolder() {
        if let activeFolderURL {
            activeFolderURL.stopAccessingSecurityScopedResource()
            self.activeFolderURL = nil
        }
    }

    private func activateFile(_ url: URL, key: String) {
        if activeFileURLs[key] != nil {
            return
        }
        if url.startAccessingSecurityScopedResource() {
            activeFileURLs[key] = url
        }
    }

    private func storedFileBookmarks() -> [String: Data] {
        userDefaults.dictionary(forKey: StorageKey.fileBookmarks) as? [String: Data] ?? [:]
    }

    private func makeBookmarkData(for url: URL) -> Data? {
        #if os(macOS)
        do {
            return try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            // Non-sandboxed runs or transient paths can still store standard bookmarks
            // so unit tests and direct builds exercise the same persistence path.
            do {
                return try url.bookmarkData(
                    options: [],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
            } catch {
                Self.logger.debug("Bookmark creation skipped for \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
        #else
        return try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        #endif
    }

    private func resolveBookmark(_ data: Data) -> (url: URL, isStale: Bool)? {
        #if os(macOS)
        var isStale = false
        if let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) {
            return (normalizedURL(for: url), isStale)
        }
        isStale = false
        if let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) {
            return (normalizedURL(for: url), isStale)
        }
        return nil
        #else
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }
        return (normalizedURL(for: url), isStale)
        #endif
    }

    private func normalizedURL(for url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }
}
