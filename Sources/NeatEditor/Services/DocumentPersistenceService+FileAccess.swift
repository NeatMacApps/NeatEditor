import Foundation

extension DocumentPersistenceService {
    enum FileAccessError: Error {
        /// Background I/O never changes a live buffer's ancestry. Reconcile
        /// against the latest committed editor text on the main actor instead.
        case reconciliationRequired
    }

    private struct RecoveryRecord: Codable {
        let originalURL: URL
        let createdAt: Date
        let base: String?
        let local: String
        let disk: Data?
        let cloudVersions: [Data]
    }

    func enqueueSave(
        tab: EditorTab, in directory: URL, reconcileOnly: Bool = false,
        completion: @escaping @Sendable (Result<EditorTab, Error>) -> Void
    ) {
        fileAccess.enqueue {
            completion(Result {
                try saveInOrder(tab: tab, in: directory, allowsReconciliation: false, reconcileOnly: reconcileOnly)
            })
        }
    }

    func loadDocument(tab: EditorTab) throws -> EditorTab {
        try fileAccess.sync {
            guard let url = tab.fileURL else { return tab }
            return try coordinated(at: normalizedFileURL(for: url), writing: false) { coordinatedURL in
                var loaded = try readDocumentFile(at: coordinatedURL)
                loaded = EditorTab(id: tab.id, title: loaded.title, content: loaded.content, fileURL: loaded.fileURL)
                loaded.diskContent = loaded.content
                fileAccess.state.withLock { state in
                    state.bindings[tab.id] = coordinatedURL
                    state.accepted[coordinatedURL] = loaded.content
                }
                return loaded
            }
        }
    }

    func saveInOrder(
        tab: EditorTab, in directory: URL? = nil,
        allowsReconciliation: Bool = true, reconcileOnly: Bool = false
    ) throws -> EditorTab {
        guard tab.isContentLoaded else { return tab }
        // Empty on-disk documents can still receive an external update. A
        // deliberate local clear, however, keeps the existing blank exception.
        if isBlankContent(tab.content), tab.fileURL == nil || tab.content != tab.diskContent { return tab }
        return try fileAccess.state.withLock { state in
            guard let url = state.bindings[tab.id] ?? tab.fileURL.map(normalizedFileURL(for:)) else {
                if reconcileOnly { return tab }
                let folder = directory ?? defaultDirectory
                try withFileManager {
                    try $0.createDirectory(at: folder, withIntermediateDirectories: true,
                                           attributes: [.posixPermissions: 0o700])
                }
                let saved = try coordinated(at: folder, writing: true) { _ in
                    try publishNewDocument(tab: tab, in: folder)
                }
                return accept(saved, state: &state, written: true)
            }
            return try coordinated(at: url, writing: !reconcileOnly) { coordinatedURL in
                let data: Data
                do {
                    data = try Data(contentsOf: coordinatedURL, options: .mappedIfSafe)
                } catch {
                    // Never recreate a deleted/moved source at its old path.
                    // A durable local recovery is retained even when closing fails.
                    try recordRecovery(url: url, base: tab.diskContent, local: tab.content, disk: nil)
                    throw error
                }
                let disk = String(data: data, encoding: .utf8)
                let base = state.written[url] == disk ? state.accepted[url] : (tab.diskContent ?? state.accepted[url])
                let versions = NSFileVersion.unresolvedConflictVersionsOfItem(at: coordinatedURL) ?? []
                let externallyChanged = disk != base || !versions.isEmpty
                if reconcileOnly && !externallyChanged { return tab }
                if externallyChanged && !allowsReconciliation {
                    throw FileAccessError.reconciliationRequired
                }

                var saved = tab
                saved.fileURL = coordinatedURL
                saved.title = coordinatedURL.lastPathComponent
                saved.preservedFileURLs = []
                let merged = base.flatMap { baseline in
                    disk.flatMap { DocumentTextMerge.merge(base: baseline, local: tab.content, disk: $0) }
                }
                let cloudData = try versions.map { try Data(contentsOf: $0.url) }
                if externallyChanged && (tab.content != base || !versions.isEmpty) {
                    try recordRecovery(url: url, base: base, local: tab.content, disk: data, cloudVersions: cloudData)
                }
                for versionData in cloudData {
                    let versionURL = try preserve(versionData, beside: coordinatedURL, label: "Cloud conflict")
                    saved.preservedFileURLs.append(versionURL)
                }

                if let merged {
                    saved.content = merged
                    if merged != disk && !isBlankContent(merged) {
                        try merged.write(to: coordinatedURL, atomically: true, encoding: .utf8)
                        state.written[url] = merged
                    }
                } else if tab.content != disk {
                    // Automatic Keep Both is non-destructive: the external file
                    // stays at its original path and this tab adopts a fresh copy.
                    let conflictURL = try preserve(Data(tab.content.utf8), beside: coordinatedURL, label: "Conflict")
                    saved.fileURL = conflictURL
                    saved.title = conflictURL.lastPathComponent
                    saved.preservedFileURLs.insert(coordinatedURL, at: 0)
                }
                // All version bytes now exist in the recovery record AND files.
                // Do not remove version storage; mark only the preserved conflicts.
                for version in versions { version.isResolved = true }
                return accept(saved, state: &state, written: saved.fileURL != coordinatedURL || saved.content != disk)
            }
        }
    }

    func renameInOrder(tab: EditorTab, to title: String) throws -> EditorTab {
        try fileAccess.state.withLock { state in
            var current = tab
            current.fileURL = state.bindings[tab.id] ?? tab.fileURL
            guard let source = current.fileURL else { return try moveDocumentFile(tab: current, to: title) }
            let oldURL = normalizedFileURL(for: source)
            let coordinator = NSFileCoordinator()
            return try coordinated(at: oldURL, writing: true, options: .forMoving, coordinator: coordinator) { _ in
                let renamed = try moveDocumentFile(tab: current, to: title) { source, destination in
                    coordinator.item(at: source, willMoveTo: destination)
                }
                if let destination = renamed.fileURL, destination != oldURL {
                    coordinator.item(at: oldURL, didMoveTo: destination)
                    state.bindings[tab.id] = destination
                    state.accepted[destination] = state.accepted.removeValue(forKey: oldURL)
                    state.written[destination] = state.written.removeValue(forKey: oldURL)
                }
                return renamed
            }
        }
    }

    func saveCopy(tab: EditorTab, to destination: URL) throws -> EditorTab {
        guard !isBlankContent(tab.content) else { return tab }
        return try fileAccess.sync {
            try coordinated(at: destination.deletingLastPathComponent(), writing: true) { _ in
                var copy = tab
                copy.fileURL = nil
                copy.title = destination.lastPathComponent
                let saved = try publishNewDocument(tab: copy, in: destination.deletingLastPathComponent())
                return fileAccess.state.withLock { accept(saved, state: &$0, written: true) }
            }
        }
    }

    func releaseDocument(id: UUID) {
        fileAccess.sync {
            fileAccess.state.withLock { state in
                guard let url = state.bindings.removeValue(forKey: id),
                      !state.bindings.values.contains(url) else { return }
                state.accepted.removeValue(forKey: url)
                state.written.removeValue(forKey: url)
            }
        }
    }

    func trashDocument(tab: EditorTab) throws {
        try fileAccess.sync {
            let url = fileAccess.state.withLock { $0.bindings[tab.id] ?? tab.fileURL }
            guard let url else { return }
            try coordinated(at: url, writing: true, options: .forDeleting) { url in
                try withFileManager { try $0.trashItem(at: url, resultingItemURL: nil) }
            }
        }
    }

    /// External moves must not wait for an old autosave's MainActor callback.
    func noteExternalMove(id: UUID, from source: URL, to destination: URL) {
        fileAccess.sync {
            fileAccess.state.withLock { state in
                guard state.bindings[id] == source else { return }
                state.bindings[id] = destination
                state.accepted[destination] = state.accepted.removeValue(forKey: source)
                state.written[destination] = state.written.removeValue(forKey: source)
            }
        }
    }

    private func accept(_ tab: EditorTab, state: inout DocumentFileAccess.State, written: Bool) -> EditorTab {
        var result = tab
        result.diskContent = result.content
        if let url = result.fileURL {
            state.bindings[result.id] = url
            state.accepted[url] = result.content
            if written { state.written[url] = result.content }
        }
        return result
    }

    private func preserve(_ data: Data, beside url: URL, label: String) throws -> URL {
        let ext = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        let name = "\(base) (\(label))" + (ext.isEmpty ? "" : ".\(ext)")
        return try exclusivePublish(data: data, named: name, in: url.deletingLastPathComponent())
    }

    private func recordRecovery(
        url: URL, base: String?, local: String, disk: Data?, cloudVersions: [Data] = []
    ) throws {
        try withFileManager {
            try $0.createDirectory(at: recoveryDirectory, withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
        }
        let record = RecoveryRecord(originalURL: url, createdAt: Date(), base: base,
                                    local: local, disk: disk, cloudVersions: cloudVersions)
        let data = try JSONEncoder().encode(record)
        let destination = recoveryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        try data.write(to: destination, options: .atomic)
        try withFileManager { try $0.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path) }
    }

    private func coordinated<T>(
        at url: URL, writing: Bool, options: NSFileCoordinator.WritingOptions = [],
        coordinator: NSFileCoordinator = NSFileCoordinator(), operation: (URL) throws -> T
    ) throws -> T {
        var coordinationError: NSError?
        var result: Result<T, Error>?
        if writing {
            coordinator.coordinate(writingItemAt: url, options: options, error: &coordinationError) { coordinatedURL in
                result = Result { try operation(coordinatedURL) }
            }
        } else {
            coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
                result = Result { try operation(coordinatedURL) }
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileReadUnknown) }
        return try result.get()
    }
}
