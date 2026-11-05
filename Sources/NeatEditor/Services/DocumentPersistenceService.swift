import Foundation

/// File-level DateFormatter cache for default document names. The locale,
/// calendar, and format are fixed once; only the time zone varies per call
/// and is assigned under the lock, so sharing is safe from any thread
/// without changing call-site isolation.
private final class CachedDocumentNameFormatter: @unchecked Sendable {
    static let shared = CachedDocumentNameFormatter()

    private let lock = NSLock()
    private let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    func string(from date: Date, timeZone: TimeZone) -> String {
        lock.lock()
        defer { lock.unlock() }
        formatter.timeZone = timeZone
        return formatter.string(from: date)
    }
}

struct DocumentPersistenceService: Sendable {
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
    /// Pre-folder location used by older builds, retained only as the source
    /// for non-destructive legacy migration.
    let appLibraryDirectory: URL
    func withFileManager<T: Sendable>(_ operation: @Sendable (FileManager) throws -> T) rethrows -> T {
        try fileAccess.withFileManager(operation)
    }
    let fileAccess: DocumentFileAccess
    let recoveryDirectory: URL
    /// Test seam for the exclusive-rename fallback. Production uses the
    /// native `renamex_np(..., RENAME_EXCL)` below; tests inject ENOTSUP to
    /// prove fail-closed behavior. `nil` means native.
    let exclusiveRenameOverride: (@Sendable (URL, URL) throws -> Void)?

    init(
        fileManager: sending FileManager = FileManager(),
        defaultDirectory: URL? = nil,
        appLibraryDirectory: URL? = nil,
        recoveryDirectory: URL? = nil,
        environment: [String: String]? = nil,
        exclusiveRename: (@Sendable (URL, URL) throws -> Void)? = nil
    ) {
        let environment = environment ?? ProcessInfo.processInfo.environment
        self.defaultDirectory = defaultDirectory
            ?? Self.resolveDefaultDirectory(using: fileManager)
        self.appLibraryDirectory = appLibraryDirectory
            ?? Self.resolveAppLibraryDirectory(using: fileManager, environment: environment)
        self.recoveryDirectory = recoveryDirectory ?? self.appLibraryDirectory
            .deletingLastPathComponent().appendingPathComponent("recovery", isDirectory: true)
        self.fileAccess = DocumentFileAccess(manager: fileManager)
        self.exclusiveRenameOverride = exclusiveRename
    }

    func save(
        tab: EditorTab, in directory: URL? = nil, allowsReconciliation: Bool = true,
        filePresenter: DocumentFileObserver? = nil
    ) throws -> EditorTab {
        try fileAccess.sync {
            try saveInOrder(tab: tab, in: directory, allowsReconciliation: allowsReconciliation,
                            filePresenter: filePresenter)
        }
    }

    func publishNewDocument(tab: EditorTab, in directory: URL? = nil) throws -> EditorTab {
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
        try fileAccess.sync {
            try renameInOrder(tab: tab, to: newTitle)
        }
    }

    func moveDocumentFile(tab: EditorTab, to newTitle: String, beforeMove: (URL, URL) -> Void = { _, _ in }) throws -> EditorTab {
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

        guard !withFileManager({ $0.fileExists(atPath: destinationURL.path) }) else {
            throw PersistenceError.destinationAlreadyExists(destinationURL)
        }

        guard withFileManager({ $0.fileExists(atPath: normalizedFileURL.path) }) else {
            // The persisted file is gone; refuse to repoint the tab at a
            // destination that may later belong to an unrelated file.
            throw CocoaError(
                .fileReadNoSuchFile,
                userInfo: [NSFilePathErrorKey: normalizedFileURL.path]
            )
        }

        // Sibling rename; exclusive claim, no overwriting move.
        do {
            beforeMove(normalizedFileURL, destinationURL)
            try exclusiveRenameItem(at: normalizedFileURL, to: destinationURL)
        } catch where isFileExistsError(error) {
            throw PersistenceError.destinationAlreadyExists(destinationURL)
        }

        renamedTab.fileURL = destinationURL
        renamedTab.title = destinationURL.lastPathComponent
        return renamedTab
    }

    func openDocument(at fileURL: URL) throws -> EditorTab {
        try loadDocument(tab: openDocumentLazily(at: fileURL))
    }

    func readDocumentFile(at fileURL: URL) throws -> EditorTab {
        let normalizedFileURL = normalizedFileURL(for: fileURL)
        // Small files decode faster via String(contentsOf:); large files
        // win with mmap. Threshold measured at ~2MB (1MB: direct wins,
        // 10MB: mapped wins 46%).
        let mappedThreshold = 2 * 1024 * 1024
        let fileSize = (try? withFileManager { try $0.attributesOfItem(atPath: normalizedFileURL.path)[.size]
            as? NSNumber })?.intValue
        let content: String
        if let fileSize, fileSize >= mappedThreshold {
            let data = try Data(contentsOf: normalizedFileURL, options: .mappedIfSafe)
            guard let text = String(data: data, encoding: .utf8) else {
                throw CocoaError(
                    .fileReadInapplicableStringEncoding,
                    userInfo: [NSFilePathErrorKey: normalizedFileURL.path]
                )
            }
            content = text
        } else {
            content = try String(contentsOf: normalizedFileURL, encoding: .utf8)
        }

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
        userHomeDirectory(using: fileManager).appendingPathComponent(
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

        return userHomeDirectory(using: fileManager).appendingPathComponent(
            ".config/neateditor/documents",
            isDirectory: true
        )
    }

    static func isUserDocumentsDirectory(
        _ url: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        let documentsPath = userHomeDirectory(using: fileManager)
            .appendingPathComponent("Documents", isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
        return url.standardizedFileURL.resolvingSymlinksInPath().path == documentsPath
    }

    /// The user's home on macOS; the app sandbox home on iOS, where the
    /// shared service always receives explicit directories from its caller.
    static func userHomeDirectory(using fileManager: FileManager) -> URL {
        #if os(macOS)
        fileManager.homeDirectoryForCurrentUser
        #else
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        #endif
    }

    private func renamedFileURL(for fileURL: URL, title: String) -> URL {
        return fileURL
            .deletingLastPathComponent()
            .appendingPathComponent(title)
    }

    /// Allocation-free blank check, semantically identical to
    /// `content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty`:
    /// true only when every unicode scalar is in `.whitespacesAndNewlines`
    /// (empty string counts as blank). Early-exits on the first non-blank
    /// scalar so non-blank saves never copy the whole content.
    func isBlankContent(_ content: String) -> Bool {
        for scalar in content.unicodeScalars {
            if !CharacterSet.whitespacesAndNewlines.contains(scalar) {
                return false
            }
        }
        return true
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
    /// with an atomic exclusive primitive reusing that complete file and its
    /// mode; a name taken in the meantime yields the next numbered sibling,
    /// leaving both contents intact. Pre-existing files are never modified.
    /// Publication tries a hard link first (original exclusive contract on
    /// link-capable volumes), then `renamex_np(..., RENAME_EXCL)` (exclusive
    /// rename, no hard-link support needed). If neither exclusive primitive
    /// is supported the publish fails closed: it throws, removes staging,
    /// and never falls back to an overwriting move/rename.
    func exclusivePublish(data: Data, named fileName: String, in directory: URL? = nil) throws -> URL {
        try publishStagedFile(named: fileName, in: directory) { stagingURL in
            // .withoutOverwriting guards the staging name itself; it is never
            // combined with .atomic — NSData.h forbids that pair.
            try data.write(to: stagingURL, options: .withoutOverwriting)
            try withFileManager {
                try $0.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stagingURL.path)
            }
        }
    }

    /// Publishes bytes produced at a private staging sibling by the same
    /// no-overwrite exclusive contract as a first save. Only a complete
    /// staging file is ever published; staging and candidates share one
    /// directory and no overwriting primitive is used.
    func publishStagedFile(
        named fileName: String,
        in directory: URL? = nil,
        write: (URL) throws -> Void
    ) throws -> URL {
        let directory = directory ?? defaultDirectory
        try withFileManager {
            try $0.createDirectory(at: directory, withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
        }

        let stagingURL = directory.appendingPathComponent(
            ".neateditor-staging-\(UUID().uuidString)"
        )
        defer { try? withFileManager { try $0.removeItem(at: stagingURL) } }
        try write(stagingURL)

        return try publishFile(named: fileName, in: directory) { destination in
            try publishExclusiveStaging(from: stagingURL, to: destination)
        }
    }

    /// Claims one candidate name with an atomic exclusive primitive: hard
    /// link first, then same-directory `renamex_np(..., RENAME_EXCL)`.
    /// Collisions surface as file-exists; anything else fails closed.
    func publishExclusiveStaging(from stagingURL: URL, to destination: URL) throws {
        do {
            try withFileManager { try $0.linkItem(at: stagingURL, to: destination) }
            return
        } catch {
            if isFileExistsError(error) {
                throw error
            }
            if !isUnsupportedHardLinkError(error) {
                throw error
            }
        }
        do {
            try exclusiveRenameItem(at: stagingURL, to: destination)
        } catch {
            // EEXIST means "name taken"; publishFile retries. All other
            // errors fail closed with staging cleanup from the caller.
            throw error
        }
    }

    /// True only for hard-link capability failures that may legitimately try
    /// the exclusive-rename path: direct or wrapped POSIX ENOTSUP/EOPNOTSUPP,
    /// plus EPERM at link time (staging was just created readable in the same
    /// directory, so EPERM indicates volume capability, not staging access).
    /// Permission, I/O, quota, and other errors propagate without fallback.
    func isUnsupportedHardLinkError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain
            && (nsError.code == Int(ENOTSUP) || nsError.code == Int(EOPNOTSUPP) || nsError.code == Int(EPERM)) {
            return true
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError,
           underlying.domain == NSPOSIXErrorDomain
            && (underlying.code == Int(ENOTSUP) || underlying.code == Int(EOPNOTSUPP) || underlying.code == Int(EPERM)) {
            return true
        }
        return false
    }

    /// Same-directory exclusive rename. Production calls the native
    /// `renamex_np(..., RENAME_EXCL)`; tests may inject an override (for
    /// example to simulate ENOTSUP on volumes without exclusive-rename
    /// support). Never overwrites: on supporting volumes EEXIST is returned
    /// when the destination already exists and the staging file is left
    /// intact for the next candidate.
    func exclusiveRenameItem(at srcURL: URL, to dstURL: URL) throws {
        if let override = exclusiveRenameOverride {
            try override(srcURL, dstURL)
            return
        }
        try Self.nativeExclusiveRename(srcURL, dstURL)
    }

    /// Native exclusive rename used on both macOS and iOS (available
    /// macOS 10.12+/iOS 10.0+, within the 26.0 baselines; no `#if` needed).
    /// `renamex_np` with `RENAME_EXCL` returns EEXIST when the destination
    /// exists and ENOTSUP where the filesystem does not support exclusive
    /// rename (see `man renamex_np` and `VOL_CAP_INT_RENAME_EXCL`). Staging
    /// and destination share a directory, so no cross-volume copy occurs.
    static func nativeExclusiveRename(_ srcURL: URL, _ dstURL: URL) throws {
        var syscallResult: Int32 = -1
        var capturedErrno: Int32 = EINVAL
        srcURL.path.withCString { srcPtr in
            dstURL.path.withCString { dstPtr in
                errno = 0
                syscallResult = renamex_np(srcPtr, dstPtr, UInt32(RENAME_EXCL))
                capturedErrno = errno
            }
        }
        if syscallResult == 0 {
            return
        }
        throw NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(capturedErrno),
            userInfo: [NSFilePathErrorKey: dstURL.path]
        )
    }

    /// Tries the original name, then numbered siblings, without a check/write
    /// race. The caller supplies a publication operation that refuses overwrite.
    /// Only name collisions are retried; all other errors keep their context.
    func publishFile(
        named fileName: String,
        in directory: URL,
        using publish: (URL) throws -> Void
    ) throws -> URL {
        let baseName = (fileName as NSString).deletingPathExtension
        let pathExtension = (fileName as NSString).pathExtension
        var destination = directory.appendingPathComponent(fileName)

        for attempt in 0..<1000 {
            let suffix = attempt == 0 ? "" : " \(attempt + 1)"
            let candidate = attempt == 0 ? fileName : (pathExtension.isEmpty
                ? "\(baseName)\(suffix)"
                : "\(baseName)\(suffix).\(pathExtension)")
            destination = directory.appendingPathComponent(candidate)
            do {
                try publish(destination)
                return normalizedFileURL(for: destination)
            } catch where isFileExistsError(error) {
                continue
            }
        }
        throw PersistenceError.destinationAlreadyExists(destination)
    }

    /// An existing destination surfaces as NSFileWriteFileExistsError from
    /// FileManager copy/move/link calls, and as POSIX EEXIST from the native
    /// `renamex_np(..., RENAME_EXCL)` path. CocoaError bridges to NSError
    /// preserving domain and code, so explicit checks cover the Swift,
    /// Objective-C, and POSIX spellings in one place. Only collisions are
    /// retried; every other error (including ENOTSUP for unsupported
    /// exclusive operations) propagates fail-closed.
    func isFileExistsError(_ error: Error) -> Bool {
        if let error = error as? CocoaError, error.code == .fileWriteFileExists {
            return true
        }
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain
            && nsError.code == NSFileWriteFileExistsError {
            return true
        }
        return nsError.domain == NSPOSIXErrorDomain
            && nsError.code == Int(EEXIST)
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
        let baseName = CachedDocumentNameFormatter.shared.string(from: date, timeZone: timeZone)
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
