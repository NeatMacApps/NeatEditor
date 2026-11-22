import SwiftUI

@main
enum NeatEditorEntry {
    static func main() {
        LaunchProfiler.recordEntry()
        MacScrollerPreference.install()
        EditorExtensionBootstrap.registerIfNeeded()
        NeatEditorApp.main()
    }
}

struct NeatEditorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let workspaceStore: WorkspaceStore
    #if DIRECT_DISTRIBUTION
    private let updater = AppUpdater.shared
    #endif

    init() {
        // The E2E launch keeps workspace state and documents inside its own
        // root; every other launch takes the unchanged production path.
        let workspaceStore: WorkspaceStore
        if E2ETestMode.isActive {
            workspaceStore = WorkspaceStore(
                persistenceService: DocumentPersistenceService(
                    defaultDirectory: E2ETestMode.documentsDirectory,
                    recoveryDirectory: E2ETestMode.recoveryDirectory
                ),
                userDefaults: E2ETestMode.userDefaults
            )
        } else {
            workspaceStore = WorkspaceStore()
        }
        self.workspaceStore = workspaceStore
        LaunchProfiler.recordStoreReady()
        E2ETestWindow.prepare(store: workspaceStore)

        #if DIRECT_DISTRIBUTION
        updater.onWillInstallUpdate = { [weak workspaceStore] in
            workspaceStore?.saveAllDocuments()
        }
        #endif
        ExternalFileOpenCoordinator.shared.handler = { [weak workspaceStore] urls in
            workspaceStore?.openFiles(at: urls, source: .external)
        }
        ExternalFileOpenCoordinator.shared.saveBeforeTermination = { [weak workspaceStore] in
            workspaceStore?.saveAllDocuments() ?? true
        }
    }

    var body: some Scene {
        LaunchProfiler.recordBodyEvaluated()
        return Window("NeatEditor", id: E2ETestMode.windowSceneID) {
            WorkspaceView()
                .frame(
                    minWidth: WorkspaceSplitView.minimumWindowWidth(
                        sidebarVisible: workspaceStore.preferences.isSidebarVisible,
                        settingsSelected: settingsSelected
                    ),
                    minHeight: settingsSelected ? max(SettingsView.minimumContentHeight, EditorTabStripView.minimumWindowEdge) : EditorTabStripView.minimumWindowEdge
                )
                .environment(workspaceStore)
                .task {
                    LaunchProfiler.recordFirstFrame()
                    #if DIRECT_DISTRIBUTION
                    AppUpdater.shared.warmUp()
                    #endif
                }
        }
        .handlesExternalEvents(matching: [])
        // Opaque native titlebar: its toolbar view owns blank-titlebar double-click
        // and drag. WorkspaceSplitView paints the band over its section backgrounds.
        .windowStyle(.titleBar)
        // The AppKit bridge limits eligibility to the top row on each press.
        // SwiftUI's automatic scene policy otherwise blocks that native path.
        .windowBackgroundDragBehavior(.enabled)
        .defaultSize(
            width: E2ETestMode.windowSize?.width ?? 800,
            height: E2ETestMode.windowSize?.height ?? 600
        )
        .commands {
            #if DIRECT_DISTRIBUTION
            NeatEditorUpdateCommands()
            #endif
            WorkspaceCommands(workspaceStore: workspaceStore)
        }
    }

    private var settingsSelected: Bool {
        workspaceStore.tabs.contains { $0.id == workspaceStore.selectedTabID && $0.isSettings }
    }
}

#if DIRECT_DISTRIBUTION
private struct NeatEditorUpdateCommands: Commands {
    @State private var updater = AppUpdater.shared

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button {
                updater.checkForUpdates()
            } label: {
                Label("Check for Updates…", systemImage: "arrow.triangle.2.circlepath")
                    .labelStyle(.titleAndIcon)
            }
            .disabled(!updater.canCheckForUpdates)
        }
    }
}
#endif

/// Launch-time test hooks for the background E2E harness.
///
/// Active only when the harness passes `--e2e-testing` together with an
/// absolute `--e2e-root <directory>`; a normal launch (including a release
/// build with stray arguments) falls back to the production store, defaults
/// and scene identifiers, so nothing here can alter user behavior.
enum E2ETestMode {
    struct Configuration {
        let root: URL
        let windowSize: CGSize?
    }

    static let configuration: Configuration? = parse(CommandLine.arguments)

    static var isActive: Bool { configuration != nil }

    /// A separate scene identifier keeps the harness window from overwriting
    /// the production `main` window frame in the user's defaults.
    static var windowSceneID: String { isActive ? "main-e2e" : "main" }

    static var windowSize: CGSize? { configuration?.windowSize }

    static var documentsDirectory: URL {
        root.appendingPathComponent("documents", isDirectory: true)
    }

    static var recoveryDirectory: URL {
        root.appendingPathComponent("recovery", isDirectory: true)
    }

    /// Workspace state and preferences live in a suite of their own, cleared at
    /// every launch, so a run never reads or writes `com.x0c.NeatEditor`.
    static var userDefaults: UserDefaults {
        let suiteName = "com.x0c.NeatEditor.e2e"
        guard let defaults = UserDefaults(suiteName: suiteName) else { return .standard }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private static var root: URL {
        // `isActive` gates every caller, so a missing configuration is unreachable.
        configuration?.root ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    }

    private static func parse(_ arguments: [String]) -> Configuration? {
        guard arguments.contains("--e2e-testing"),
              let rawRoot = value(of: "--e2e-root", in: arguments)
        else { return nil }
        let expandedRoot = (rawRoot as NSString).expandingTildeInPath
        guard expandedRoot.hasPrefix("/") else { return nil }
        var windowSize: CGSize?
        if let rawSize = value(of: "--e2e-window-size", in: arguments) {
            let parts = rawSize.lowercased().split(separator: "x")
            if parts.count == 2,
               let width = Double(parts[0]), let height = Double(parts[1]),
               width > 0, height > 0 {
                windowSize = CGSize(width: width, height: height)
            }
        }
        return Configuration(
            root: URL(fileURLWithPath: expandedRoot, isDirectory: true),
            windowSize: windowSize
        )
    }

    private static func value(of flag: String, in arguments: [String]) -> String? {
        // `open --args` hands bare positional values to LaunchServices as
        // document paths, so every E2E option is passed as `--flag=value`.
        let prefix = flag + "="
        for argument in arguments where argument.hasPrefix(prefix) {
            let candidate = argument.dropFirst(prefix.count)
                .trimmingCharacters(in: .whitespaces)
            return candidate.isEmpty ? nil : candidate
        }
        return nil
    }
}

/// The E2E launch presents its window itself: a background launch never
/// activates, and the SwiftUI scene window only exists after activation.
@MainActor
enum E2ETestWindow {
    private static var pendingStore: WorkspaceStore?
    private static var window: NSWindow?

    static func prepare(store: WorkspaceStore) {
        guard E2ETestMode.isActive else { return }
        pendingStore = store
    }

    static func presentIfNeeded() {
        guard let store = pendingStore, window == nil else { return }
        // Pixel baselines cannot depend on the owner's light/dark setting.
        NSApp.appearance = NSAppearance(named: .aqua)
        let size = E2ETestMode.windowSize ?? CGSize(width: 800, height: 600)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            // Full-size content: WorkspaceSplitView extends under the titlebar and
            // paints its own band; without this, the titlebar/toolbar height becomes
            // an empty strip between the tab strip and the content.
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "NeatEditor"
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 480, height: 320)
        window.contentView = NSHostingView(
            rootView: WorkspaceView()
                .environment(store)
                .frame(minWidth: 480, minHeight: 320)
        )
        // Never activate. Behind everything, still on the current Space, and
        // drawn once so window-scoped capture sees fresh pixels.
        window.orderBack(nil)
        window.displayIfNeeded()
        CATransaction.flush()
        Self.window = window
    }
}
