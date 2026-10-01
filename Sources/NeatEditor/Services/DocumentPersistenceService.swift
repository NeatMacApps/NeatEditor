import Foundation

struct DocumentPersistenceService {
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
    private let fileManager: FileManager

    init(
        fileManager: FileManager = .default,
        defaultDirectory: URL? = nil,
        environment: [String: String]? = nil
    ) {
        self.fileManager = fileManager
        let environment = environment ?? ProcessInfo.processInfo.environment
        self.defaultDirectory = defaultDirectory
            ?? Self.resolveDefaultDirectory(using: fileManager, environment: environment)
    }

    func save(tab: EditorTab) throws -> EditorTab {
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
        let fileURL = try exclusivePublish(data: data, named: fileName)
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
        using fileManager: FileManager,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        // App-owned documents live under the XDG config home so they stay out
        // of the user's Documents folder. Existing fileURLs are never
        // rewritten, so this only affects newly saved documents. Relative
        // XDG values are ignored per the base directory specification, which
        // requires an absolute path.
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
    private func exclusivePublish(data: Data, named fileName: String) throws -> URL {
        try fileManager.createDirectory(
            at: defaultDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        // .withoutOverwriting guards the staging name itself; it is never
        // combined with .atomic — NSData.h forbids that pair.
        let stagingURL = defaultDirectory.appendingPathComponent(
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
                    to: defaultDirectory.appendingPathComponent(candidate)
                )
                // The candidate now links the complete staged inode and keeps
                // its 600 mode; the staging alias is dropped by the defer.
                return normalizedFileURL(
                    for: defaultDirectory.appendingPathComponent(candidate)
                )
            } catch where isFileExistsError(error) {
                continue
            }
        }

        throw PersistenceError.destinationAlreadyExists(
            defaultDirectory.appendingPathComponent(lastCandidate)
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
