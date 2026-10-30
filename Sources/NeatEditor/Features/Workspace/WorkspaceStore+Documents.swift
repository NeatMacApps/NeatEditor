import Foundation
import AppKit

extension WorkspaceStore {
    // MARK: - Documents

    func saveCurrentDocument() {
        guard let id = selectedTabID else { return }
        saveDocument(id: id)
    }

    func saveAndCloseCurrentDocument() {
        guard let id = selectedTabID else { return }
        closeDocument(id: id)
    }

    func moveToTrash(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }),
              !tabs[index].isSettings, tabs[index].fileURL != nil else { return }
        autoSaveScheduler.cancel(for: id)
        saveGenerations[id, default: 0] += 1
        do {
            try persistenceService.trashDocument(tab: tabs[index])
        } catch {
            presentDocumentFailure(title: String(localized: "Move to Trash Failed"), message: error.localizedDescription)
            return
        }
        stopObservingDocument(id: id)
        closedTabs.append(ClosedTabSnapshot(tab: tabs[index], index: index))
        tabs.remove(at: index)
        if selectedTabID == id {
            selectedTabID = tabs.indices.contains(index) ? tabs[index].id : tabs.last?.id
            if let selectedTabID { loadTabContentIfNeeded(id: selectedTabID) }
            applyEditorFontPreferenceForSelectedTab()
        }
        saveState()
        refreshSidebarFiles()
    }

    func renameDocument(id: UUID, to newTitle: String) {
        guard let index = tabs.firstIndex(where: { $0.id == id }), !tabs[index].isSettings else { return }
        let originalFileURL = normalizedEditorFontFileURL(for: tabs[index].fileURL)
        saveGenerations[id, default: 0] += 1
        do {
            tabs[index] = try persistenceService.rename(tab: tabs[index], to: newTitle)
            preferences.moveRememberedEditorFontSize(from: originalFileURL,
                to: normalizedEditorFontFileURL(for: tabs[index].fileURL))
            if selectedTabID == id {
                preferences.rememberCurrentEditorFontSize(for: normalizedEditorFontFileURL(for: tabs[index].fileURL))
            }
            observeDocument(id: id)
            saveState()
            refreshSidebarFiles()
        } catch {
            if case let DocumentPersistenceService.PersistenceError.destinationAlreadyExists(url) = error {
                let format = String(localized: "“%@” already exists in this folder. Use a different name and try again.")
                presentDocumentFailure(title: String(localized: "Rename Failed"),
                                       message: String(format: format, url.lastPathComponent))
            } else {
                presentDocumentFailure(title: String(localized: "Rename Failed"), message: error.localizedDescription)
            }
        }
    }

    func dismissDocumentFailureAlert() { documentFailureAlert = nil }

    func presentDocumentFailure(title: String, message: String, otherVersionURL: URL? = nil, recoveryTabID: UUID? = nil) {
        guard documentFailureAlert == nil else { return }
        documentFailureAlert = DocumentFailureAlert(title: title, message: message,
            otherVersionURL: otherVersionURL, recoveryTabID: recoveryTabID)
    }

    func saveDocumentCopy(id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = tab.title
        panel.directoryURL = tab.fileURL?.deletingLastPathComponent() ?? documentsFolder
        panel.begin { [weak self] response in
            guard response == .OK, let destination = panel.url, let self else { return }
            self.commitEditorChanges?(id)
            guard let current = self.tabs.first(where: { $0.id == id }) else { return }
            self.saveGenerations[id, default: 0] += 1
            do {
                self.publishSavedDocument(try self.persistenceService.saveCopy(tab: current, to: destination))
            } catch {
                self.presentDocumentFailure(title: String(localized: "Save Failed"),
                    message: error.localizedDescription, recoveryTabID: id)
            }
        }
    }

    func updateDocumentContent(_ content: String, for id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].content = content
        if let fileURL = tabs[index].fileURL { updateSidebarPreview(for: fileURL, content: content) }
    }

    @discardableResult
    func saveDocument(id: UUID) -> Bool {
        commitEditorChanges?(id)
        guard let tab = tabs.first(where: { $0.id == id }), !tab.isSettings, tab.isContentLoaded else { return true }
        autoSaveScheduler.cancel(for: id)
        saveGenerations[id, default: 0] += 1
        do {
            let saved = try persistenceService.save(tab: tab, in: documentsFolder,
                allowsReconciliation: !(editorHasMarkedText?(id) ?? false))
            publishSavedDocument(saved)
            return true
        } catch DocumentPersistenceService.FileAccessError.reconciliationRequired {
            pendingExternalChecks.insert(id)
            return false
        } catch {
            presentDocumentFailure(title: String(localized: "Save Failed"), message: error.localizedDescription, recoveryTabID: id)
            Self.logger.error("Document save failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func saveDocumentInBackground(id: UUID) {
        enqueueDocumentSave(id: id, reconcileOnly: false)
    }

    private func enqueueDocumentSave(id: UUID, reconcileOnly: Bool) {
        commitEditorChanges?(id)
        guard let snapshot = tabs.first(where: { $0.id == id }), !snapshot.isSettings,
              snapshot.isContentLoaded else { return }
        if !reconcileOnly {
            autoSaveScheduler.cancel(for: id)
            saveGenerations[id, default: 0] += 1
        }
        let generation = saveGenerations[id]
        persistenceService.enqueueSave(tab: snapshot, in: documentsFolder, reconcileOnly: reconcileOnly) { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.reconcilingTabIDs.remove(id)
                guard self.saveGenerations[id] == generation,
                      let current = self.tabs.first(where: { $0.id == id }) else { return }
                switch result {
                case .success(var saved):
                    if reconcileOnly {
                        self.observeDocument(id: id)
                        if self.pendingExternalChecks.remove(id) != nil { self.reconcileDocument(id: id) }
                        return
                    }
                    // Normal background saves never merge external content. A
                    // later keystroke remains dirty against this saved snapshot.
                    saved.content = current.content
                    saved.externalRevision = current.externalRevision
                    self.publishSavedDocument(saved)
                case .failure(DocumentPersistenceService.FileAccessError.reconciliationRequired):
                    if self.editorHasMarkedText?(id) ?? false {
                        self.pendingExternalChecks.insert(id)
                    } else {
                        self.saveDocument(id: id)
                    }
                case .failure(let error):
                    self.presentDocumentFailure(title: String(localized: "Save Failed"), message: error.localizedDescription, recoveryTabID: id)
                }
                if self.pendingExternalChecks.remove(id) != nil { self.reconcileDocument(id: id) }
            }
        }
    }

    private func publishSavedDocument(_ saved: EditorTab) {
        guard let index = tabs.firstIndex(where: { $0.id == saved.id }) else { return }
        var published = saved
        // A result carries new notifications, not persistent tab state. Blank
        // saves return the tab unchanged and must not replay an old conflict.
        published.preservedFileURLs = []
        if saved.content != tabs[index].content {
            published.externalRevision = tabs[index].externalRevision + 1
            applyExternalEditorChanges?(saved.id, saved.content, published.externalRevision)
        }
        tabs[index] = published
        if let url = saved.fileURL { updateSidebarPreview(for: url, content: saved.content) }
        if selectedTabID == saved.id {
            preferences.rememberCurrentEditorFontSize(for: normalizedEditorFontFileURL(for: saved.fileURL))
        }
        if let other = saved.preservedFileURLs.first {
            presentDocumentFailure(title: String(localized: "Both Versions Kept"),
                message: String(localized: "The file changed elsewhere. Your text and the other versions were saved as separate files."),
                otherVersionURL: other)
        }
        observeDocument(id: saved.id)
        saveState()
        refreshSidebarFiles()
    }

    @discardableResult
    func saveAllDocuments() -> Bool {
        var didSaveAll = true
        for tab in tabs where !saveDocument(id: tab.id) { didSaveAll = false }
        flushPendingSaveState()
        return didSaveAll
    }

    func cancelAutoSave(for id: UUID) { autoSaveScheduler.cancel(for: id) }

    func queueAutoSave(for id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }), !tab.isSettings else { return }
        if pendingExternalChecks.remove(id) != nil { reconcileDocument(id: id) }
        autoSaveScheduler.schedule(for: id) { [weak self] in self?.saveDocumentInBackground(id: id) }
    }

    func loadTabContentIfNeeded(id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }), !tab.isContentLoaded,
              !loadingTabIDs.contains(id), let url = tab.fileURL else { return }
        loadingTabIDs.insert(id)
        let service = persistenceService
        Task {
            do {
                let loaded = try await Task.detached(priority: .userInitiated) { try service.loadDocument(tab: tab) }.value
                loadingTabIDs.remove(id)
                guard let index = tabs.firstIndex(where: { $0.id == id }), tabs[index].fileURL == url else { return }
                if tabs[index].content.isEmpty { tabs[index] = loaded }
                else { tabs[index].isContentLoaded = true; tabs[index].diskContent = loaded.content }
                observeDocument(id: id)
                updateSidebarPreview(for: url, content: tabs[index].content)
            } catch {
                loadingTabIDs.remove(id)
                guard tabs.contains(where: { $0.id == id && $0.fileURL == url }) else { return }
                presentDocumentFailure(title: String(localized: "Open Failed"), message: error.localizedDescription)
            }
        }
    }

    func saveSelectedDocumentIfNeeded() {
        if let selectedTabID { saveDocument(id: selectedTabID) }
    }

    // MARK: - External changes

    func reconcileOpenDocuments() {
        for tab in tabs where tab.isContentLoaded && tab.fileURL != nil { reconcileDocument(id: tab.id) }
    }

    func reconcileDocument(id: UUID) {
        if editorHasMarkedText?(id) ?? false { pendingExternalChecks.insert(id); return }
        guard !reconcilingTabIDs.contains(id) else { pendingExternalChecks.insert(id); return }
        reconcilingTabIDs.insert(id)
        enqueueDocumentSave(id: id, reconcileOnly: true)
    }

    func observeDocument(id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }), tab.isContentLoaded,
              let url = tab.fileURL else { return }
        fileObservers.removeValue(forKey: id)?.stop()
        fileObservers[id] = DocumentFileObserver(url: url) { [weak self] event in
            Task { @MainActor [weak self] in
                guard let self, let index = self.tabs.firstIndex(where: { $0.id == id }),
                      self.tabs[index].fileURL == url else { return }
                if case .moved(let destination) = event {
                    self.saveGenerations[id, default: 0] += 1
                    self.persistenceService.noteExternalMove(id: id, from: url, to: destination)
                    self.tabs[index].fileURL = destination
                    self.tabs[index].title = destination.lastPathComponent
                    self.saveState()
                    self.refreshSidebarFiles()
                }
                self.reconcileDocument(id: id)
            }
        }
    }

    func stopObservingDocument(id: UUID) {
        fileObservers.removeValue(forKey: id)?.stop()
        persistenceService.releaseDocument(id: id)
        pendingExternalChecks.remove(id)
        reconcilingTabIDs.remove(id)
        saveGenerations[id, default: 0] += 1
    }
}
