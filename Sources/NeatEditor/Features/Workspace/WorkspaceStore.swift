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
        static let hasHandledStartupDefaultAppPrompt = "hasHandledStartupDefaultAppPrompt"
        static let isDefaultAppPromptSuppressed = "isDefaultAppPromptSuppressed"
        static let dismissedExternalDefaultAppPromptTypes = "dismissedExternalDefaultAppPromptTypes"
    }

    struct ClosedTabSnapshot {
        let tab: EditorTab
        let index: Int
    }

    struct DocumentFailureAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        var otherVersionURL: URL? = nil
        var recoveryTabID: UUID? = nil
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
    var defaultFileTypeStatuses: [DefaultFileType: DefaultFileTypeStatus] = [:]
    var defaultAppPrompt: DefaultAppPromptState?
    var canReopenClosedTab: Bool {
        !closedTabs.isEmpty
    }

    var isSettingsSelected: Bool {
        tabs.contains { $0.id == selectedTabID && $0.isSettings }
    }

    var markdownSourceModeTabIDs: Set<UUID> = []

    var selectedTab: EditorTab? {
        guard let selectedTabID else { return nil }
        return tabs.first(where: { $0.id == selectedTabID })
    }

    var isMarkdownSurfaceAvailable: Bool {
        EditorExtensionRegistry.markdownProvider != nil
    }

    var markdownCapability: MarkdownEditCapability {
        EditorExtensionRegistry.markdownProvider?.capability ?? .readOnlyPreview
    }

    var isSelectedTabMarkdown: Bool {
        isMarkdownSurfaceAvailable && (selectedTab?.isMarkdownDocument ?? false)
    }

    var isSelectedTabInSourceMode: Bool {
        guard let selectedTabID else { return false }
        return markdownSourceModeTabIDs.contains(selectedTabID)
    }

    var canPerformMarkdownFormatting: Bool {
        isSelectedTabMarkdown
            && !isSettingsSelected
            && (selectedTab?.isContentLoaded ?? false)
            && markdownCapability == .fullEditing
    }

    var isRestoringState = false

    @ObservationIgnored
    let persistenceService: DocumentPersistenceService

    @ObservationIgnored
    let autoSaveScheduler: AutoSaveScheduler

    @ObservationIgnored
    let userDefaults: UserDefaults

    @ObservationIgnored
    let bookmarkStore: SecurityScopedBookmarkStore

    @ObservationIgnored
    private var activeEditorHandlerOwner: UUID?

    @ObservationIgnored
    var commitEditorChanges: (@MainActor (UUID) -> Void)?

    @ObservationIgnored
    var editorHasMarkedText: (@MainActor (UUID) -> Bool)?

    @ObservationIgnored
    var applyExternalEditorChanges: (@MainActor (UUID, String, UInt64) -> Void)?

    @ObservationIgnored
    var editorSelectedSearchSeed: (@MainActor () -> String?)?

    @ObservationIgnored
    var focusEditor: (@MainActor () -> Void)?

    @ObservationIgnored
    var performMarkdownFormatAction: (@MainActor (MarkdownFormattingAction) -> Void)?

    func registerEditorHandlers(
        ownerID: UUID,
        commit: @escaping @MainActor (UUID) -> Void,
        hasMarkedText: @escaping @MainActor (UUID) -> Bool,
        applyExternal: @escaping @MainActor (UUID, String, UInt64) -> Void,
        selectedSearchSeed: @escaping @MainActor () -> String?,
        focus: @escaping @MainActor () -> Void,
        performMarkdownFormat: (@MainActor (MarkdownFormattingAction) -> Void)? = nil
    ) {
        activeEditorHandlerOwner = ownerID
        commitEditorChanges = commit
        editorHasMarkedText = hasMarkedText
        applyExternalEditorChanges = applyExternal
        editorSelectedSearchSeed = selectedSearchSeed
        focusEditor = focus
        performMarkdownFormatAction = performMarkdownFormat
    }

    func unregisterEditorHandlers(ownerID: UUID) {
        guard activeEditorHandlerOwner == ownerID else {
            return
        }
        activeEditorHandlerOwner = nil
        commitEditorChanges = nil
        editorHasMarkedText = nil
        applyExternalEditorChanges = nil
        editorSelectedSearchSeed = nil
        focusEditor = nil
        performMarkdownFormatAction = nil
    }

    func setMarkdownSourceMode(_ enabled: Bool, for tabID: UUID) {
        guard isMarkdownSurfaceAvailable,
              let tab = tabs.first(where: { $0.id == tabID }),
              tab.isMarkdownDocument else {
            return
        }
        commitEditorChanges?(tabID)
        if enabled {
            markdownSourceModeTabIDs.insert(tabID)
        } else {
            markdownSourceModeTabIDs.remove(tabID)
        }
    }

    func toggleMarkdownSourceMode() {
        guard let selectedTabID, isSelectedTabMarkdown, !isSettingsSelected else {
            return
        }
        setMarkdownSourceMode(!markdownSourceModeTabIDs.contains(selectedTabID), for: selectedTabID)
    }

    func performMarkdownFormatting(_ action: MarkdownFormattingAction) {
        guard canPerformMarkdownFormatting else {
            return
        }
        performMarkdownFormatAction?(action)
    }

    @ObservationIgnored
    var saveGenerations: [UUID: UInt64] = [:]

    @ObservationIgnored
    var pendingWriteGenerations: [UUID: UInt64] = [:]

    @ObservationIgnored
    var fileObservers: [UUID: DocumentFileObserver] = [:]

    @ObservationIgnored
    var reconcilingTabIDs: Set<UUID> = []

    @ObservationIgnored
    var pendingExternalChecks: Set<UUID> = []

    // saveState() is invoked from many small mutating paths and previously did
    // a synchronous JSONEncoder + UserDefaults write per call. Coalesce
    // back-to-back invocations onto a short trailing debounce so a single
    // user-triggered batch (e.g. open files / select tab / autosave) results
    // in one persisted snapshot instead of several. Always flush before
    // app-lifecycle save points.
    @ObservationIgnored
    var pendingSaveStateTask: Task<Void, Never>?

    /// Explicit font-size adjustments are folded into the adaptive new-draft
    /// default after a short trailing debounce. The pending sample and its
    /// task are observation-ignored bookkeeping, not UI state.
    @ObservationIgnored
    var pendingAdaptiveFontSample: CGFloat?

    @ObservationIgnored
    var pendingAdaptiveFontTask: Task<Void, Never>?

    @ObservationIgnored
    let adaptiveFontSampleDelay: Duration

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

    /// The row the user just chose in the sidebar. The sidebar consumes it to
    /// avoid re-scrolling a row that is already on screen: `List`'s
    /// `scrollTo` aligns the target at the top even when it is already visible.
    @ObservationIgnored
    var sidebarOriginatedSelectionURL: URL?

    @ObservationIgnored
    let fileAssociationService: any FileAssociationManaging

    @ObservationIgnored
    let enablesAutomaticDefaultAppPrompts: Bool

    @ObservationIgnored
    let launchDefaultAppPromptDelay: Duration

    @ObservationIgnored
    var pendingExternalDefaultAppTypes: Set<DefaultFileType> = []

    @ObservationIgnored
    var hasCompletedLaunchDefaultAppCheck = false

    @ObservationIgnored
    var isAwaitingLaunchDefaultAppPrompt = false

    @ObservationIgnored
    var pendingDefaultAppTask: Task<Void, Never>?

    deinit {
        for observer in fileObservers.values { observer.stop() }
    }

    init(
        persistenceService: DocumentPersistenceService = DocumentPersistenceService(),
        autoSaveScheduler: AutoSaveScheduler = AutoSaveScheduler(),
        userDefaults: UserDefaults = .standard,
        adaptiveFontSampleDelay: Duration = .seconds(2),
        fileAssociationService: any FileAssociationManaging = SystemFileAssociationService(),
        enablesAutomaticDefaultAppPrompts: Bool = !E2ETestMode.isActive
            && ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
        launchDefaultAppPromptDelay: Duration = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
            ? .milliseconds(300)
            : .zero
    ) {
        self.persistenceService = persistenceService
        self.autoSaveScheduler = autoSaveScheduler
        self.userDefaults = userDefaults
        self.bookmarkStore = SecurityScopedBookmarkStore(userDefaults: userDefaults)
        self.adaptiveFontSampleDelay = adaptiveFontSampleDelay
        self.fileAssociationService = fileAssociationService
        self.enablesAutomaticDefaultAppPrompts = enablesAutomaticDefaultAppPrompts
        self.launchDefaultAppPromptDelay = launchDefaultAppPromptDelay
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
