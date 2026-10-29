import SwiftUI

@main
enum NeatEditorEntry {
    static func main() {
        LaunchProfiler.recordEntry()
        MacScrollerPreference.install()
        NeatEditorApp.main()
    }
}

struct NeatEditorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let workspaceStore: WorkspaceStore
    private let updater = AppUpdater.shared

    init() {
        let workspaceStore = WorkspaceStore()
        self.workspaceStore = workspaceStore
        LaunchProfiler.recordStoreReady()

        updater.onWillInstallUpdate = { [weak workspaceStore] in
            workspaceStore?.saveAllDocuments()
        }
        ExternalFileOpenCoordinator.shared.handler = { [weak workspaceStore] urls in
            workspaceStore?.openFiles(at: urls)
        }
        ExternalFileOpenCoordinator.shared.saveBeforeTermination = { [weak workspaceStore] in
            workspaceStore?.saveAllDocuments() ?? true
        }
    }

    var body: some Scene {
        LaunchProfiler.recordBodyEvaluated()
        return Window("NeatEditor", id: "main") {
            WorkspaceView()
                .frame(
                    minWidth: WorkspaceSplitView.minimumWindowWidth(
                        sidebarVisible: workspaceStore.preferences.isSidebarVisible,
                        settingsSelected: settingsSelected
                    ),
                    minHeight: settingsSelected ? max(440, EditorTabStripView.minimumWindowEdge) : EditorTabStripView.minimumWindowEdge
                )
                .environment(workspaceStore)
                .task {
                    LaunchProfiler.recordFirstFrame()
                    AppUpdater.shared.warmUp()
                }
        }
        .handlesExternalEvents(matching: [])
        // Opaque native titlebar: its toolbar view owns blank-titlebar double-click
        // and drag. WorkspaceSplitView paints the band over its section backgrounds.
        .windowStyle(.titleBar)
        .defaultSize(width: 800, height: 600)
        .commands {
            NeatEditorUpdateCommands()
            WorkspaceCommands(workspaceStore: workspaceStore)
        }
    }

    private var settingsSelected: Bool {
        workspaceStore.tabs.contains { $0.id == workspaceStore.selectedTabID && $0.isSettings }
    }
}

private struct NeatEditorUpdateCommands: Commands {
    @State private var updater = AppUpdater.shared

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button(String(localized: "Check for Updates…")) {
                updater.checkForUpdates()
            }
            .disabled(!updater.canCheckForUpdates)
        }
    }
}
