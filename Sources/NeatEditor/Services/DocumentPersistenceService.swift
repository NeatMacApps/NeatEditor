import Foundation

struct DocumentPersistenceService {
    struct SidebarFileInfo: Hashable, Sendable {
        let fileURL: URL
        let modificationDate: Date
        let fileSize: Int
    }

    /// File types shown in the workspace sidebar. Lowercased path extensions.
    static let sidebarSupportedExtensions: Set<String> = ["md", "markdown", "txt", "text"]

    private enum SidebarPreview {
        static let maxLines = 3
        static let maxBytes = 64 * 1024
        static let maxCharacters = 1000
        static let headCharacters = 4096
    }

    /// Extensionless files are only listed when their head looks like plain
    /// UTF-8 text. The bound keeps the probe cheap for large binaries.
    private static let textSniffByteCount = 4 * 1024

    enum PersistenceError: LocalizedError {
        case destinationAlreadyExists(URL)

        var errorDescription: String? {
            switch self {
            case .destinationAlreadyExists(let url):
                let messageFormat = String(localized: "A document named \"%@\" already exists.")
                return String(format: messageFormat, url.lastPathComponent)
            }
        }
    }

    let defaultDirectory: URL
    /// Pre-folder location used by older builds. Kept as the migration source
    /// and as the fallback when the user's Documents folder is unavailable.
    let appLibraryDirectory: URL
    private let fileManager: FileManager

    init(
        fileManager: FileManager = .default,
        defaultDirectory: URL? = nil,
        appLibraryDirectory: URL? = nil,
        environment: [String: String]? = nil
    ) {
        self.fileManager = fileManager
        let environment = environment ?? ProcessInfo.processInfo.environment
        self.defaultDirectory = defaultDirectory
            ?? Self.resolveDefaultDirectory(using: fileManager)
        self.appLibraryDirectory = appLibraryDirectory
            ?? Self.resolveAppLibraryDirectory(using: fileManager, environment: environment)
    }

    func save(tab: EditorTab, in directory: URL? = nil) throws -> EditorTab {
        guard !tab.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return tab
        }

        // Re-saving an already-placed document overwrites its own file, which
        // is the normal save path. Only the first save (no fileURL yet) needs
        // no-clobber creation.
        if let fileURL = tab.fileURL {
            var savedTab = tab
            let normalizedURL = normalizedFileURL(for: fileURL)
            try savedTab.content.write(to: normalizedURL, atomically: true, encoding: .utf8)
            savedTab.fileURL = normalizedURL
            savedTab.title = normalizedURL.lastPathComponent
            return savedTab
        }

        var savedTab = tab
        let validatedTitle = try validatedSingleFileName(from: savedTab.title)
        let fileName = (validatedTitle as NSString).pathExtension.isEmpty
            ? "\(validatedTitle).txt"
            : validatedTitle
        guard let data = savedTab.content.data(using: .utf8) else {
            throw CocoaError(
                .fileWriteInapplicableStringEncoding,
                userInfo: [NSFilePathErrorKey: fileName]
            )
        }

        // Deferred until the first non-blank save so merely opening the app or
        // creating empty tabs never touches the filesystem.
        let fileURL = try exclusivePublish(data: data, named: fileName, in: directory)
        savedTab.fileURL = fileURL
        savedTab.title = fileURL.lastPathComponent

        return savedTab
    }

    func rename(tab: EditorTab, to newTitle: String) throws -> EditorTab {
        let validatedTitle = try validatedSingleFileName(from: newTitle)
        var renamedTab = tab
        renamedTab.title = validatedTitle

        guard let fileURL = renamedTab.fileURL else {
            return renamedTab
        }

        let normalizedFileURL = normalizedFileURL(for: fileURL)
        let destinationURL = renamedFileURL(for: normalizedFileURL, title: validatedTitle)

        guard destinationURL != normalizedFileURL else {
            renamedTab.fileURL = normalizedFileURL
            renamedTab.title = normalizedFileURL.lastPathComponent
            return renamedTab
        }

        guard !fileManager.fileExists(atPath: destinationURL.path) else {
            throw PersistenceError.destinationAlreadyExists(destinationURL)
        }

        guard fileManager.fileExists(atPath: normalizedFileURL.path) else {
            // The persisted file is gone; refuse to repoint the tab at a
            // destination that may later belong to an unrelated file.
            throw CocoaError(
                .fileReadNoSuchFile,
                userInfo: [NSFilePathErrorKey: normalizedFileURL.path]
            )
        }

        // moveItem itself refuses to overwrite an existing destination, so
        // a file created at the destination between the check above and
        // now still cannot be clobbered; map that race to the same error.
        do {
            try fileManager.moveItem(at: normalizedFileURL, to: destinationURL)
        } catch where isFileExistsError(error) {
            throw PersistenceError.destinationAlreadyExists(destinationURL)
        }

        renamedTab.fileURL = destinationURL
        renamedTab.title = destinationURL.lastPathComponent
        return renamedTab
    }

    func openDocument(at fileURL: URL) throws -> EditorTab {
        let normalizedFileURL = normalizedFileURL(for: fileURL)
        let content = try String(contentsOf: normalizedFileURL, encoding: .utf8)

        return EditorTab(
            title: normalizedFileURL.lastPathComponent,
            content: content,
            fileURL: normalizedFileURL,
            isContentLoaded: true
        )
    }

    func openDocumentLazily(at fileURL: URL) -> EditorTab {
        let normalizedFileURL = normalizedFileURL(for: fileURL)

        return EditorTab(
            title: normalizedFileURL.lastPathComponent,
            content: "",
            fileURL: normalizedFileURL,
            isContentLoaded: false
        )
    }

    func normalizedFileURL(for fileURL: URL) -> URL {
        fileURL.standardizedFileURL.resolvingSymlinksInPath()
    }

    static func resolveDefaultDirectory(
        using fileManager: FileManager
    ) -> URL {
        // New notes are user content, so the default destination is the
        // user's Documents folder. The sidebar can switch to another folder;
        // the old app library remains only as a migration source.
        fileManager.homeDirectoryForCurrentUser.appendingPathComponent(
            "Documents",
            isDirectory: true
        )
    }

    /// Pre-folder app-owned library (`~/.config/neateditor/documents` or the
    /// XDG equivalent). Existing documents there are copied into the current
    /// documents folder on first launch; new documents never use it unless
    /// the user explicitly chooses it.
    static func resolveAppLibraryDirectory(
        using fileManager: FileManager,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        // Relative XDG values are ignored per the base directory
        // specification, which requires an absolute path.
        if let xdgConfigHome = environment["XDG_CONFIG_HOME"],
           !xdgConfigHome.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            let expanded = (xdgConfigHome as NSString).expandingTildeInPath
            if expanded.hasPrefix("/") {
                return URL(fileURLWithPath: expanded, isDirectory: true)
                    .appendingPathComponent("neateditor/documents", isDirectory: true)
            }
        }

        return fileManager.homeDirectoryForCurrentUser.appendingPathComponent(
            ".config/neateditor/documents",
            isDirectory: true
        )
    }

    static func isUserDocumentsDirectory(
        _ url: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        let documentsPath = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents", isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
        return url.standardizedFileURL.resolvingSymlinksInPath().path == documentsPath
    }

    private func renamedFileURL(for fileURL: URL, title: String) -> URL {
        return fileURL
            .deletingLastPathComponent()
            .appendingPathComponent(title)
    }

    /// A tab title denotes exactly one file name inside its directory. Reject
    /// anything that could escape it so a hostile or accidental title can
    /// never write outside the destination folder.
    private func validatedSingleFileName(from title: String) throws -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains("/"),
              !trimmed.contains("\0"),
              trimmed != ".",
              trimmed != "..",
              !(trimmed as NSString).pathComponents.contains("..")
        else {
            throw CocoaError(.fileWriteInvalidFileName, userInfo: [NSFilePathErrorKey: title])
        }
        return trimmed
    }

    /// Publishes a complete file at a fresh name without ever overwriting an
    /// existing one. The content is written once to a unique private staging
    /// sibling (never at a candidate name, so a failed or interrupted write
    /// cannot leave a partial document), then each candidate name is claimed
    /// with an exclusive hard-link publication reusing that same inode; a
    /// name taken in the meantime yields the next numbered sibling, leaving
    /// both contents intact. Pre-existing files are never modified.
    private func exclusivePublish(data: Data, named fileName: String, in directory: URL? = nil) throws -> URL {
        let directory = directory ?? defaultDirectory
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        // .withoutOverwriting guards the staging name itself; it is never
        // combined with .atomic — NSData.h forbids that pair.
        let stagingURL = directory.appendingPathComponent(
            ".neateditor-staging-\(UUID().uuidString)"
        )
        defer { try? fileManager.removeItem(at: stagingURL) }
        try data.write(to: stagingURL, options: .withoutOverwriting)
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: stagingURL.path
        )

        let baseName = (fileName as NSString).deletingPathExtension
        let pathExtension = (fileName as NSString).pathExtension

        var lastCandidate = fileName
        for attempt in 0..<1000 {
            let candidate: String
            if attempt == 0 {
                candidate = fileName
            } else if pathExtension.isEmpty {
                candidate = "\(baseName) \(attempt + 1)"
            } else {
                candidate = "\(baseName) \(attempt + 1).\(pathExtension)"
            }
            lastCandidate = candidate

            do {
                try fileManager.linkItem(
                    at: stagingURL,
                    to: directory.appendingPathComponent(candidate)
                )
                // The candidate now links the complete staged inode and keeps
                // its 600 mode; the staging alias is dropped by the defer.
                return normalizedFileURL(
                    for: directory.appendingPathComponent(candidate)
                )
            } catch where isFileExistsError(error) {
                continue
            }
        }

        throw PersistenceError.destinationAlreadyExists(
            directory.appendingPathComponent(lastCandidate)
        )
    }

    /// An existing destination surfaces as NSFileWriteFileExistsError from
    /// FileManager copy/move/link calls. CocoaError bridges to NSError
    /// preserving domain and code, so a single NSError check covers both the
    /// Swift and Objective-C spellings in one place.
    private func isFileExistsError(_ error: Error) -> Bool {
        if let error = error as? CocoaError, error.code == .fileWriteFileExists {
            return true
        }
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain
            && nsError.code == NSFileWriteFileExistsError
    }

    /// Missing app-owned directories are normal before the first save.
    /// Other enumeration errors must remain distinguishable from an empty list.
    func sidebarTextFiles() throws -> [SidebarFileInfo] {
        try sidebarTextFiles(in: defaultDirectory)
    }

    /// Lists regular text files in `directory`: the supported extensions plus
    /// extensionless files whose head looks like plain UTF-8 text. Hidden
    /// entries, directories, binaries and unpublished staging files are
    /// skipped so a sidebar row always opens as editable text.
    func sidebarTextFiles(in directory: URL) throws -> [SidebarFileInfo] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        let urls: [URL]
        do {
            urls = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles]
            )
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return []
        }

        var infos: [SidebarFileInfo] = []
        infos.reserveCapacity(urls.count)
        var seen = Set<URL>()
        for url in urls {
            if url.lastPathComponent.hasPrefix(".neateditor-staging-") {
                continue
            }
            let pathExtension = url.pathExtension
            let hasSupportedExtension = Self.sidebarSupportedExtensions.contains(
                pathExtension.lowercased()
            )
            guard hasSupportedExtension || pathExtension.isEmpty else {
                continue
            }
            let values = try url.resourceValues(forKeys: keys)
            let fileURL = normalizedFileURL(for: url)
            guard values.isRegularFile == true, seen.insert(fileURL).inserted else {
                continue
            }
            if !hasSupportedExtension,
               !Self.isLikelyTextFile(at: fileURL, fileManager: fileManager) {
                continue
            }
            infos.append(SidebarFileInfo(
                fileURL: fileURL,
                modificationDate: values.contentModificationDate ?? .distantPast,
                fileSize: values.fileSize ?? 0
            ))
        }
        return infos.sorted { lhs, rhs in
            let comparison = lhs.fileURL.lastPathComponent.localizedStandardCompare(
                rhs.fileURL.lastPathComponent
            )
            if comparison != .orderedSame {
                return comparison == .orderedDescending
            }
            return lhs.fileURL.path > rhs.fileURL.path
        }
    }

    /// Copies documents left in the pre-folder app library into `directory`.
    /// Existing names are never overwritten and the originals are never
    /// moved or deleted, so a failed migration can only leave files behind.
    /// Returns the copy count, or `nil` when the legacy folder could not be
    /// read and the caller should retry later.
    func migrateLegacyAppDocumentsIfNeeded(into directory: URL) -> Int? {
        let destination = normalizedFileURL(for: directory)
        guard normalizedFileURL(for: appLibraryDirectory) != destination else {
            return 0
        }
        let legacyFiles: [SidebarFileInfo]
        do {
            legacyFiles = try sidebarTextFiles(in: appLibraryDirectory)
        } catch {
            return nil
        }
        guard !legacyFiles.isEmpty else {
            return 0
        }

        var copiedCount = 0
        for info in legacyFiles {
            let destinationURL = destination.appendingPathComponent(
                info.fileURL.lastPathComponent
            )
            guard !fileManager.fileExists(atPath: destinationURL.path) else {
                continue
            }
            do {
                try fileManager.copyItem(at: info.fileURL, to: destinationURL)
                copiedCount += 1
            } catch {
                // One unreadable legacy document must not block the rest.
                continue
            }
        }
        return copiedCount
    }

    /// Extensionless candidates get a bounded probe: NUL bytes and invalid
    /// UTF-8 sequences mark a binary. A truncated sequence at the 4 KiB
    /// boundary is accepted because the read may split a character.
    static func isLikelyTextFile(
        at fileURL: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return false
        }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: textSniffByteCount) else {
            return false
        }
        guard !data.isEmpty else {
            return true
        }
        guard !data.contains(0) else {
            return false
        }
        return isUTF8Prefix(data)
    }

    private static func isUTF8Prefix(_ data: Data) -> Bool {
        let bytes = [UInt8](data)
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            let length: Int
            switch byte {
            case 0x00...0x7F:
                length = 1
            case 0xC2...0xDF:
                length = 2
            case 0xE0...0xEF:
                length = 3
            case 0xF0...0xF4:
                length = 4
            default:
                return false
            }

            if index + length > bytes.count {
                // A character split by the sniff boundary is still text.
                return true
            }
            var offset = 1
            while offset < length {
                if bytes[index + offset] & 0xC0 != 0x80 {
                    return false
                }
                offset += 1
            }
            index += length
        }
        return true
    }

    /// Short preview excerpt for a sidebar row: the first lines of content.
    /// Pure string transform so rows stay live while typing without disk I/O.
    /// Only scans a small head of the buffer so per-keystroke updates stay cheap.
    static func sidebarPreviewExcerpt(from content: String, maxLines: Int = SidebarPreview.maxLines) -> String {
        let excerpt = String(content.prefix(SidebarPreview.headCharacters))
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .prefix(max(1, maxLines))
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard excerpt.count > SidebarPreview.maxCharacters else {
            return excerpt
        }
        return String(excerpt.prefix(SidebarPreview.maxCharacters))
    }

    /// Reads only a small prefix of the file for preview purposes. Never
    /// throws: missing/unreadable files yield an empty preview and the row
    /// falls back to its placeholder.
    func sidebarPreview(
        for fileURL: URL,
        maxLines: Int = SidebarPreview.maxLines
    ) -> String {
        guard let data = sidebarPrefixData(for: fileURL) else {
            return ""
        }
        let content: String
        if let strict = String(data: data, encoding: .utf8) {
            content = strict
        } else {
            content = String(decoding: data, as: UTF8.self)
        }
        return Self.sidebarPreviewExcerpt(from: content, maxLines: maxLines)
    }

    private func sidebarPrefixData(for fileURL: URL) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return nil
        }
        defer { try? handle.close() }
        return try? handle.read(upToCount: SidebarPreview.maxBytes)
    }

    /// Closed files use exactly the same validation and collision policy as tabs.
    func renameSidebarFile(at fileURL: URL, to newTitle: String) throws -> URL {
        let sourceURL = normalizedFileURL(for: fileURL)
        let tab = EditorTab(title: sourceURL.lastPathComponent, fileURL: sourceURL)
        return try rename(tab: tab, to: newTitle).fileURL ?? sourceURL
    }

    /// Live text is staged completely before exclusive publication. Unopened
    /// files use FileManager copying so their full content isn't read into memory.
    func duplicateSidebarFile(at fileURL: URL, content: String? = nil) throws -> URL {
        let sourceURL = normalizedFileURL(for: fileURL)
        let pathExtension = sourceURL.pathExtension
        let baseName = (sourceURL.lastPathComponent as NSString).deletingPathExtension
        let copyName = pathExtension.isEmpty
            ? "\(baseName) copy"
            : "\(baseName) copy.\(pathExtension)"
        if let content {
            return try exclusivePublish(
                data: Data(content.utf8),
                named: copyName,
                in: sourceURL.deletingLastPathComponent()
            )
        }
        for attempt in 0..<1000 {
            let suffix = attempt == 0 ? "" : " \(attempt + 1)"
            let candidateName = pathExtension.isEmpty
                ? "\(baseName) copy\(suffix)"
                : "\(baseName) copy\(suffix).\(pathExtension)"
            let destinationURL = sourceURL
                .deletingLastPathComponent()
                .appendingPathComponent(candidateName)
            do {
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
                return normalizedFileURL(for: destinationURL)
            } catch where isFileExistsError(error) {
                continue
            }
        }
        throw PersistenceError.destinationAlreadyExists(sourceURL)
    }

    /// Names a new tab from its local creation time and in-memory tabs only. Deliberately
    /// avoids scanning the documents directory so startup and new-tab
    /// construction never block on synchronous filesystem I/O; first-save
    /// collision handling protects on-disk files regardless of naming.
    func defaultDocumentName(
        existingTabs: [EditorTab],
        date: Date = Date(),
        timeZone: TimeZone = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let baseName = formatter.string(from: date)
        let existingNames = Set(existingTabs.map {
            ($0.title as NSString).deletingPathExtension
        })

        var candidate = baseName
        var suffix = 2
        while existingNames.contains(candidate) {
            candidate = "\(baseName)-\(suffix)"
            suffix += 1
        }

        return candidate
    }
}
