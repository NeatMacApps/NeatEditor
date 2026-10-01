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
        defaultDirectory: URL? = nil
    ) {
        self.fileManager = fileManager
        self.defaultDirectory = defaultDirectory
            ?? Self.resolveDefaultDirectory(using: fileManager)
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

        // Deferred until the first non-blank save so merely opening the app or
        // creating empty tabs never touches the filesystem.
        try fileManager.createDirectory(at: defaultDirectory, withIntermediateDirectories: true)
        let fileURL = try exclusiveCreateFile(named: fileName, content: savedTab.content)
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

        if fileManager.fileExists(atPath: normalizedFileURL.path) {
            // moveItem itself refuses to overwrite an existing destination, so
            // a file created at the destination between the check above and
            // now still cannot be clobbered; map that race to the same error.
            do {
                try fileManager.moveItem(at: normalizedFileURL, to: destinationURL)
            } catch let error as CocoaError where error.code == .fileWriteFileExists {
                throw PersistenceError.destinationAlreadyExists(destinationURL)
            } catch let error as NSError
                where error.domain == NSCocoaErrorDomain
                    && error.code == NSFileWriteFileExistsError
            {
                throw PersistenceError.destinationAlreadyExists(destinationURL)
            }
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

    private static func resolveDefaultDirectory(using fileManager: FileManager) -> URL {
        // App-owned documents live under the XDG config home so they stay out
        // of the user's Documents folder. Existing fileURLs are never
        // rewritten, so this only affects newly saved documents.
        if let xdgConfigHome = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"],
           !xdgConfigHome.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            let expanded = (xdgConfigHome as NSString).expandingTildeInPath
            let base: URL
            if (expanded as NSString).isAbsolutePath {
                base = URL(fileURLWithPath: expanded, isDirectory: true)
            } else {
                base = fileManager.homeDirectoryForCurrentUser
                    .appendingPathComponent(expanded, isDirectory: true)
            }
            return base.appendingPathComponent("neateditor/documents", isDirectory: true)
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

    /// Creates a new file that must not already exist and writes the content
    /// into it. Uses O_EXCL so a file appearing between the existence check
    /// and creation still cannot be overwritten; on collision a numbered
    /// sibling name is tried instead, leaving both contents intact.
    private func exclusiveCreateFile(named fileName: String, content: String) throws -> URL {
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
            let candidateURL = defaultDirectory.appendingPathComponent(candidate)
            if try writeExclusively(content: content, to: candidateURL) {
                return normalizedFileURL(for: candidateURL)
            }
        }

        throw PersistenceError.destinationAlreadyExists(
            defaultDirectory.appendingPathComponent(lastCandidate)
        )
    }

    /// Returns true when this call created and wrote the file, false when the
    /// file already existed. Throws on any other failure.
    private func writeExclusively(content: String, to fileURL: URL) throws -> Bool {
        guard let data = content.data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding, userInfo: [NSFilePathErrorKey: fileURL.path])
        }

        let path = fileURL.path
        let descriptor = path.withCString { cPath in
            open(cPath, O_WRONLY | O_CREAT | O_EXCL, mode_t(0o644))
        }
        if descriptor == -1 {
            if errno == EEXIST {
                return false
            }
            let code = errno
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code), userInfo: [NSFilePathErrorKey: path])
        }
        defer { close(descriptor) }

        try data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            var written = 0
            while written < buffer.count {
                guard let baseAddress = buffer.baseAddress else { break }
                let result = write(descriptor, baseAddress.advanced(by: written), buffer.count - written)
                if result == -1 {
                    if errno == EINTR {
                        continue
                    }
                    let code = errno
                    try? fileManager.removeItem(at: fileURL)
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(code), userInfo: [NSFilePathErrorKey: path])
                }
                written += result
            }
        }

        return true
    }

    /// Names the next untitled tab from in-memory tabs only. Deliberately
    /// avoids scanning the documents directory so startup and new-tab
    /// construction never block on synchronous filesystem I/O; first-save
    /// collision handling protects on-disk files regardless of naming.
    func nextUntitledName(existingTabs: [EditorTab]) -> String {
        var maxN = 0
        let baseName = String(localized: "Untitled")

        for tab in existingTabs {
            let nameWithoutExtension = (tab.title as NSString).deletingPathExtension
            if nameWithoutExtension.hasPrefix(baseName) {
                let suffix = nameWithoutExtension
                    .dropFirst(baseName.count)
                    .trimmingCharacters(in: .whitespaces)
                if let number = Int(suffix), number > maxN {
                    maxN = number
                }
            }
        }

        return "\(baseName) \(maxN + 1)"
    }
}
