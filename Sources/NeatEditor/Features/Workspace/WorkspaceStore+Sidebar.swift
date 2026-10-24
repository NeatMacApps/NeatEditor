import AppKit
import Foundation

extension WorkspaceStore {
    // MARK: - Sidebar

    var selectedSidebarFileURL: URL? {
        guard let selectedTabID,
              let tab = tabs.first(where: { $0.id == selectedTabID }),
              let fileURL = tab.fileURL
        else {
            return nil
        }
        return persistenceService.normalizedFileURL(for: fileURL)
    }

    func toggleSidebar() {
        preferences.isSidebarVisible.toggle()
        if preferences.isSidebarVisible {
            refreshSidebarFiles()
        }
    }

    /// Coalesces requests while enumerating and reading bounded prefixes off
    /// the main actor. Resolve live buffers after the await, never before it.
    func refreshSidebarFiles() {
        guard !isRefreshingSidebar else {
            sidebarRefreshRequested = true
            return
        }
        isRefreshingSidebar = true
        let directory = persistenceService.defaultDirectory
        let cachedItems = sidebarDiskFiles

        Task {
            do {
                let diskItems = try await Task.detached(priority: .utility) {
                    let service = DocumentPersistenceService(defaultDirectory: directory)
                    let cachedByURL = Dictionary(
                        cachedItems.map { ($0.fileURL, $0) },
                        uniquingKeysWith: { _, latest in latest }
                    )
                    return try service.sidebarTextFiles().map { info in
                        let cached = cachedByURL[info.fileURL]
                        let canReuse = cached?.modificationDate == info.modificationDate
                            && cached?.fileSize == info.fileSize
                        return WorkspaceSidebarItem(
                            fileURL: info.fileURL,
                            modificationDate: info.modificationDate,
                            preview: canReuse ? cached?.preview ?? "" : service.sidebarPreview(for: info.fileURL),
                            fileSize: info.fileSize
                        )
                    }
                }.value

                sidebarDiskFiles = diskItems
                sidebarFiles = diskItems
                for tab in tabs where tab.isContentLoaded {
                    if let fileURL = tab.fileURL {
                        updateSidebarPreview(for: fileURL, content: tab.content)
                    }
                }
                sidebarFailureMessage = nil
            } catch {
                // Keep the previous usable list; an unreadable folder is not empty.
                sidebarFailureMessage = error.localizedDescription
                Self.logger.error("Sidebar refresh failed: \(error.localizedDescription, privacy: .public)")
            }
            isRefreshingSidebar = false
            if sidebarRefreshRequested {
                sidebarRefreshRequested = false
                refreshSidebarFiles()
            }
        }
    }

    func openSidebarFile(_ fileURL: URL) {
        if let existingTabID = existingTabID(for: fileURL) {
            selectTab(existingTabID)
        } else {
            openFiles(at: [fileURL])
        }
    }

    func updateSidebarPreview(for fileURL: URL, content: String) {
        let normalizedURL = persistenceService.normalizedFileURL(for: fileURL)
        guard let index = sidebarFiles.firstIndex(where: { $0.fileURL == normalizedURL }) else {
            return
        }
        sidebarFiles[index].preview = DocumentPersistenceService.sidebarPreviewExcerpt(from: content)
    }

    func renameSidebarFile(at fileURL: URL, to newTitle: String) {
        if let existingTabID = existingTabID(for: fileURL) {
            renameDocument(id: existingTabID, to: newTitle)
            return
        }
        do {
            let newURL = try persistenceService.renameSidebarFile(at: fileURL, to: newTitle)
            preferences.moveRememberedEditorFontSize(
                from: persistenceService.normalizedFileURL(for: fileURL),
                to: newURL
            )
            refreshSidebarFiles()
        } catch let error as DocumentPersistenceService.PersistenceError {
            if case let .destinationAlreadyExists(url) = error {
                let messageFormat = String(
                    localized: "“%@” already exists in this folder. Use a different name and try again."
                )
                presentDocumentFailure(
                    title: String(localized: "Rename Failed"),
                    message: String(format: messageFormat, url.lastPathComponent)
                )
            } else {
                presentDocumentFailure(
                    title: String(localized: "Rename Failed"),
                    message: error.localizedDescription
                )
            }
            Self.logger.error("Failed to rename sidebar file: \(error.localizedDescription, privacy: .public)")
        } catch {
            presentDocumentFailure(title: String(localized: "Rename Failed"), message: error.localizedDescription)
            Self.logger.error("Failed to rename sidebar file: \(error.localizedDescription, privacy: .public)")
        }
    }

    func trashSidebarFile(at fileURL: URL) {
        if let existingTabID = existingTabID(for: fileURL) {
            moveToTrash(id: existingTabID)
            return
        }
        do {
            try FileManager.default.trashItem(
                at: persistenceService.normalizedFileURL(for: fileURL),
                resultingItemURL: nil
            )
            refreshSidebarFiles()
        } catch {
            presentDocumentFailure(title: String(localized: "Move to Trash Failed"), message: error.localizedDescription)
            Self.logger.error("Failed to trash sidebar file: \(error.localizedDescription, privacy: .public)")
        }
    }

    func duplicateSidebarFile(at fileURL: URL) {
        let tabID = existingTabID(for: fileURL)
        if let tabID {
            commitEditorChanges?(tabID)
        }
        let liveContent = tabs.first { $0.id == tabID && $0.isContentLoaded }?.content
        do {
            let newURL = try persistenceService.duplicateSidebarFile(at: fileURL, content: liveContent)
            openFiles(at: [newURL])
        } catch {
            presentDocumentFailure(title: String(localized: "Duplicate Failed"), message: error.localizedDescription)
            Self.logger.error("Failed to duplicate sidebar file: \(error.localizedDescription, privacy: .public)")
        }
    }

    func revealSidebarFileInFinder(_ fileURL: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([
            persistenceService.normalizedFileURL(for: fileURL),
        ])
    }

    func copySidebarFilePath(_ fileURL: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(
            persistenceService.normalizedFileURL(for: fileURL).path,
            forType: .string
        )
    }
}
