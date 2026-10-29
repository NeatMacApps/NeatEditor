import Foundation

extension WorkspaceStore {
    // MARK: - Documents

    /// Size threshold for lazy loads: below it a direct `String` read wins,
    /// at/above it mmap + decode wins (mirrors
    /// `DocumentPersistenceService.openDocument`, W1-owned).
    private static let lazyLoadDirectReadThreshold = 2 * 1024 * 1024

    /// Outcome of one detached autosave write. Only Sendable payloads cross
    /// the isolation boundary; the main-actor publish step re-resolves the
    /// tab by stable id. Used only by the background autosave entry below.
    private struct DetachedSaveOutcome: Sendable {
        let id: UUID
        let snapshotFileURL: URL?
        let snapshotTitle: String
        let savedFileURL: URL?
        let savedTitle: String?
        let failureMessage: String?
    }

    /// Fail-fast mirror of `DocumentPersistenceService.validatedSingleFileName`
    /// (W1-owned, private there): a first save whose title can never become
    /// a file name fails synchronously so close/close-other guards keep their
    /// immediate abort signal without doing any I/O. The detached write stays
    /// authoritative for collision handling; keep this in sync with the
    /// service if its rules ever change.
    private func isFirstSaveFileNameValid(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains("/"),
              !trimmed.contains("\0"),
              trimmed != ".",
              trimmed != "..",
              !(trimmed as NSString).pathComponents.contains("..")
        else {
            return false
        }
        return true
    }

    func saveCurrentDocument() {
        guard let id = selectedTabID else { return }
        saveDocument(id: id)
    }

    func saveAndCloseCurrentDocument() {
        guard let id = selectedTabID else {
            return
        }

        closeDocument(id: id)
    }

    func moveToTrash(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }),
              !tabs[index].isSettings,
              let fileURL = tabs[index].fileURL
        else { return }

        autoSaveScheduler.cancel(for: id)

        do {
            try FileManager.default.trashItem(at: fileURL, resultingItemURL: nil)
        } catch {
            presentDocumentFailure(title: String(localized: "Move to Trash Failed"), message: error.localizedDescription)
            Self.logger.error("Failed to trash file at \(fileURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return
        }

        let closedTab = tabs[index]
        closedTabs.append(ClosedTabSnapshot(tab: closedTab, index: index))
        tabs.remove(at: index)

        if selectedTabID == id {
            if tabs.indices.contains(index) {
                selectedTabID = tabs[index].id
            } else {
                selectedTabID = tabs.last?.id
            }
            if let newSelection = selectedTabID {
                loadTabContentIfNeeded(id: newSelection)
                applyEditorFontPreferenceForSelectedTab()
            }
        }

        saveState()
        refreshSidebarFiles()
    }

    func renameDocument(id: UUID, to newTitle: String) {
        guard let index = tabs.firstIndex(where: { $0.id == id }), !tabs[index].isSettings else {
            return
        }

        let originalFileURL = normalizedEditorFontFileURL(for: tabs[index].fileURL)

        do {
            tabs[index] = try persistenceService.rename(tab: tabs[index], to: newTitle)
            preferences.moveRememberedEditorFontSize(
                from: originalFileURL,
                to: normalizedEditorFontFileURL(for: tabs[index].fileURL)
            )

            if selectedTabID == id {
                preferences.rememberCurrentEditorFontSize(
                    for: normalizedEditorFontFileURL(for: tabs[index].fileURL)
                )
            }
            saveState()
            refreshSidebarFiles()
        } catch {
            if case let DocumentPersistenceService.PersistenceError.destinationAlreadyExists(url) = error {
                let messageFormat = String(
                    localized: "“%@” already exists in this folder. Use a different name and try again."
                )
                presentDocumentFailure(
                    title: String(localized: "Rename Failed"),
                    message: String(format: messageFormat, url.lastPathComponent)
                )
            } else {
                presentDocumentFailure(title: String(localized: "Rename Failed"), message: error.localizedDescription)
            }
            Self.logger.error("Failed to rename document: \(error.localizedDescription, privacy: .public)")
        }
    }

    func dismissDocumentFailureAlert() {
        documentFailureAlert = nil
    }

    func presentDocumentFailure(title: String, message: String) {
        guard documentFailureAlert == nil else { return }
        documentFailureAlert = DocumentFailureAlert(title: title, message: message)
    }

    func updateDocumentContent(_ content: String, for id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].content = content
        if let fileURL = tabs[index].fileURL {
            updateSidebarPreview(for: fileURL, content: content)
        }
    }

    @discardableResult
    func saveDocument(id: UUID) -> Bool {
        commitEditorChanges?(id)
        guard let index = tabs.firstIndex(where: { $0.id == id }), !tabs[index].isSettings else { return true }

        guard tabs[index].isContentLoaded else { return true }
        autoSaveScheduler.cancel(for: id)

        do {
            tabs[index] = try persistenceService.save(tab: tabs[index], in: documentsFolder)

            if selectedTabID == id {
                preferences.rememberCurrentEditorFontSize(
                    for: normalizedEditorFontFileURL(for: tabs[index].fileURL)
                )
            }
            saveState()
            refreshSidebarFiles()
            return true
        } catch {
            presentDocumentFailure(title: String(localized: "Save Failed"), message: error.localizedDescription)
            Self.logger.error("Failed to save document: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Background autosave entry, used only by `queueAutoSave`. Snapshots on
    /// the main actor and writes off-main; unlike `saveDocument` it never
    /// blocks the caller and reports nothing (failures surface as alerts).
    /// All durability paths (`saveDocument`, close, tab switch, lifecycle
    /// flush) stay synchronous, so a racing synchronous save always wins on
    /// disk and the publish below only fills in file identity when the tab
    /// was not retargeted since the snapshot.
    func saveDocumentInBackground(id: UUID) {
        commitEditorChanges?(id)
        guard let index = tabs.firstIndex(where: { $0.id == id }), !tabs[index].isSettings else { return }

        guard tabs[index].isContentLoaded else { return }
        autoSaveScheduler.cancel(for: id)

        // Same blank/product-rule ordering as `saveDocument`.
        let snapshot = tabs[index]
        guard !snapshot.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        if snapshot.fileURL == nil, !isFirstSaveFileNameValid(snapshot.title) {
            let error = CocoaError(.fileWriteInvalidFileName, userInfo: [NSFilePathErrorKey: snapshot.title])
            presentDocumentFailure(title: String(localized: "Save Failed"), message: error.localizedDescription)
            Self.logger.error("Failed to save document: \(error.localizedDescription, privacy: .public)")
            return
        }

        // The struct copy retains the CoW String buffer with zero copy; every
        // capture below is Sendable, so MainActor state never crosses the
        // isolation boundary.
        let content = snapshot.content
        let fileURL = snapshot.fileURL
        let title = snapshot.title
        let directory = documentsFolder

        let ioTask = Task.detached(priority: .utility) { [id, content, fileURL, title, directory] () -> DetachedSaveOutcome in
            let tabSnapshot = EditorTab(id: id, title: title, content: content, fileURL: fileURL)
            // A snapshot-scoped service instance keeps the store's
            // MainActor-isolated service out of the detached task (same
            // pattern as refreshSidebarFiles); save only uses the file
            // manager plus the given directory for first saves.
            let service = DocumentPersistenceService(fileManager: .default, defaultDirectory: directory)
            do {
                let savedTab = try service.save(tab: tabSnapshot, in: directory)
                return DetachedSaveOutcome(
                    id: id,
                    snapshotFileURL: fileURL, snapshotTitle: title,
                    savedFileURL: savedTab.fileURL, savedTitle: savedTab.title,
                    failureMessage: nil
                )
            } catch {
                return DetachedSaveOutcome(
                    id: id,
                    snapshotFileURL: fileURL, snapshotTitle: title,
                    savedFileURL: nil, savedTitle: nil,
                    failureMessage: error.localizedDescription
                )
            }
        }

        // Back on the main actor to publish file identity, then snapshot
        // state and sidebar. The live buffer is never touched: it may have
        // advanced past the snapshot while the write was in flight.
        Task { @MainActor [weak self] in
            let outcome = await ioTask.value
            self?.publishBackgroundSaveOutcome(outcome)
        }
    }

    /// Main-actor publish for one detached autosave. Applies file identity
    /// only when the tab still matches the snapshot (a synchronous save or
    /// rename/move since then already owns the tab and the disk).
    private func publishBackgroundSaveOutcome(_ outcome: DetachedSaveOutcome) {
        guard let index = tabs.firstIndex(where: { $0.id == outcome.id }) else {
            // Tab closed while the write was in flight: the file still holds
            // the snapshot, so keep the reopen entry linked to it instead of
            // dropping the metadata. (closedTabs is not part of the persisted
            // snapshot, so no saveState here.)
            if let savedFileURL = outcome.savedFileURL,
               let savedTitle = outcome.savedTitle,
               let closedIndex = closedTabs.lastIndex(where: { $0.tab.id == outcome.id }),
               closedTabs[closedIndex].tab.fileURL == outcome.snapshotFileURL
            {
                var tab = closedTabs[closedIndex].tab
                tab.fileURL = savedFileURL
                tab.title = savedTitle
                closedTabs[closedIndex] = ClosedTabSnapshot(tab: tab, index: closedTabs[closedIndex].index)
                refreshSidebarFiles()
            }
            return
        }
        guard tabs[index].fileURL == outcome.snapshotFileURL,
              tabs[index].title == outcome.snapshotTitle
        else { return }

        if let failureMessage = outcome.failureMessage {
            presentDocumentFailure(title: String(localized: "Save Failed"), message: failureMessage)
            Self.logger.error("Failed to save document: \(failureMessage, privacy: .public)")
            return
        }
        if let savedFileURL = outcome.savedFileURL, let savedTitle = outcome.savedTitle {
            tabs[index].fileURL = savedFileURL
            tabs[index].title = savedTitle
        }

        if selectedTabID == outcome.id {
            preferences.rememberCurrentEditorFontSize(
                for: normalizedEditorFontFileURL(for: tabs[index].fileURL)
            )
        }
        saveState()
        refreshSidebarFiles()
    }

    @discardableResult
    func saveAllDocuments() -> Bool {
        var didSaveAll = true
        for tab in tabs {
            if !saveDocument(id: tab.id) {
                didSaveAll = false
            }
        }
        // saveDocument enqueues a debounced saveState; force a synchronous
        // flush here because saveAllDocuments is invoked at lifecycle
        // boundaries (scenePhase != active, app termination) where we cannot
        // rely on the debounce window completing.
        flushPendingSaveState()
        return didSaveAll
    }

    func cancelAutoSave(for id: UUID) {
        autoSaveScheduler.cancel(for: id)
    }

    func queueAutoSave(for id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }), !tabs[index].isSettings else { return }

        autoSaveScheduler.schedule(for: id) { [weak self] in
            self?.saveDocumentInBackground(id: id)
        }
    }

    func loadTabContentIfNeeded(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }),
              !tabs[index].isContentLoaded,
              !loadingTabIDs.contains(id),
              let fileURL = tabs[index].fileURL else {
            return
        }

        // `isContentLoaded` flips to `true` only when the load below
        // completes (see the `Task`), so the editor stays non-editable until
        // then and `saveDocument` skips the placeholder.
        loadingTabIDs.insert(id)

        let normalizedURL = persistenceService.normalizedFileURL(for: fileURL)
        // Hoisted so the detached task captures a plain Sendable value.
        let directReadThreshold = Self.lazyLoadDirectReadThreshold

        Task {
            do {
                let content = try await Task.detached(priority: .userInitiated) {
                    // One lightweight stat decides the read path: small files
                    // decode faster via a direct String read, large files keep
                    // mmap + decode. A failed stat falls through to the mapped
                    // read, whose error preserves the existing failure path.
                    let resourceValues = try? normalizedURL.resourceValues(forKeys: [.fileSizeKey])
                    if let fileSize = resourceValues?.fileSize, fileSize < directReadThreshold {
                        return try String(contentsOf: normalizedURL, encoding: .utf8)
                    }
                    let data = try Data(contentsOf: normalizedURL, options: .mappedIfSafe)
                    guard let text = String(data: data, encoding: .utf8) else {
                        throw CocoaError(.fileReadInapplicableStringEncoding)
                    }
                    return text
                }.value

                loadingTabIDs.remove(id)
                guard let currentIndex = self.tabs.firstIndex(where: { $0.id == id }) else { return }
                guard self.tabs[currentIndex].fileURL.map(persistenceService.normalizedFileURL(for:)) == normalizedURL else {
                    loadTabContentIfNeeded(id: id)
                    return
                }
                // The editor is non-editable while loading, so non-empty
                // content here means something else already provided it —
                // never silently discard it with the stale load result.
                if self.tabs[currentIndex].content.isEmpty {
                    self.tabs[currentIndex].content = content
                } else if self.tabs[currentIndex].content != content {
                    Self.logger.error("Discarding stale lazy load for \(normalizedURL.lastPathComponent, privacy: .public): buffer changed while loading.")
                }
                self.tabs[currentIndex].isContentLoaded = true
                if let loadedURL = self.tabs[currentIndex].fileURL {
                    self.updateSidebarPreview(for: loadedURL, content: self.tabs[currentIndex].content)
                }
            } catch {
                loadingTabIDs.remove(id)
                Self.logger.error("Failed to load document content lazily at \(fileURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                guard let currentIndex = self.tabs.firstIndex(where: { $0.id == id }) else { return }
                guard self.tabs[currentIndex].fileURL.map(persistenceService.normalizedFileURL(for:)) == normalizedURL else {
                    loadTabContentIfNeeded(id: id)
                    return
                }
                // An error is never document text. Keep the placeholder
                // unsaveable so lifecycle autosave cannot corrupt the file.
                presentDocumentFailure(title: String(localized: "Open Failed"), message: error.localizedDescription)
            }
        }
    }

    func saveSelectedDocumentIfNeeded() {
        if let selectedTabID {
            saveDocument(id: selectedTabID)
        }
    }
}
