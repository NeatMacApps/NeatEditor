import Foundation
import Observation
import AppKit
import OSLog

@Observable
@MainActor
final class WorkspaceStore {
    enum UserDefaultsKey {
        static let workspaceState = "WorkspaceState"
        static let appleLanguages = "AppleLanguages"
        static let didMigrateLegacyAppDocuments = "didMigrateLegacyAppDocuments"
    }

    struct ClosedTabSnapshot {
        let tab: EditorTab
        let index: Int
    }

    struct DocumentFailureAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    static let logger = Logger(
        subsystem: "com.x0c.NeatEditor",
        category: "Workspace"
    )

    var tabs: [EditorTab] = []
    var selectedTabID: UUID?
    var preferences = WorkspacePreferences() {
        didSet {
            handlePreferencesChange(from: oldValue, to: preferences)
        }
    }
    var isLanguageChangePendingRestart = false
    var searchState = WorkspaceSearchState()
    var documentFailureAlert: DocumentFailureAlert?
    var canReopenClosedTab: Bool {
        !closedTabs.isEmpty
    }

    var isRestoringState = false

    @ObservationIgnored
    let persistenceService: DocumentPersistenceService

    @ObservationIgnored
    let autoSaveScheduler: AutoSaveScheduler

    @ObservationIgnored
    let userDefaults: UserDefaults

    @ObservationIgnored
    var commitEditorChanges: (@MainActor (UUID) -> Void)?

    // saveState() is invoked from many small mutating paths and previously did
    // a synchronous JSONEncoder + UserDefaults write per call. Coalesce
    // back-to-back invocations onto a short trailing debounce so a single
    // user-triggered batch (e.g. open files / select tab / autosave) results
    // in one persisted snapshot instead of several. Always flush before
    // app-lifecycle save points.
    @ObservationIgnored
    var pendingSaveStateTask: Task<Void, Never>?

    /// Tabs with an in-flight lazy content load. `isContentLoaded` flips to
    /// `true` only when the load *completes*, so this set also dedupes
    /// overlapping load requests for the same tab.
    @ObservationIgnored
    var loadingTabIDs: Set<UUID> = []

    var closedTabs: [ClosedTabSnapshot] = []

    var sidebarFiles: [WorkspaceSidebarItem] = []

    /// Folder the sidebar lists and where new documents are first saved. The
    /// user can switch it from the sidebar header; the choice is persisted
    /// with the rest of the workspace state.
    var documentsFolder: URL

    var isRefreshingSidebar = false
    var sidebarFailureMessage: String?

    @ObservationIgnored
    var sidebarRefreshRequested = false

    /// Disk previews must not be contaminated by unsaved editor text.
    @ObservationIgnored
    var sidebarDiskFiles: [WorkspaceSidebarItem] = []

    init(
        persistenceService: DocumentPersistenceService = DocumentPersistenceService(),
        autoSaveScheduler: AutoSaveScheduler = AutoSaveScheduler(),
        userDefaults: UserDefaults = .standard
    ) {
        self.persistenceService = persistenceService
        self.autoSaveScheduler = autoSaveScheduler
        self.userDefaults = userDefaults
        self.documentsFolder = persistenceService.normalizedFileURL(
            for: persistenceService.defaultDirectory
        )
        
        if let state = loadState() {
            restoreState(state)
        } else {
            createNewDocument()
        }
    }
}
