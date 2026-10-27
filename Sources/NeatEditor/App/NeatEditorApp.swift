import SwiftUI

@main
enum NeatEditorEntry {
    static func main() {
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
        Window("NeatEditor", id: "main") {
            WorkspaceView()
                .frame(
                    minWidth: WorkspaceSplitView.minimumWindowWidth(
                        sidebarVisible: workspaceStore.preferences.isSidebarVisible,
                        settingsSelected: settingsSelected
                    ),
                    minHeight: settingsSelected ? max(440, EditorTabStripView.minimumWindowEdge) : EditorTabStripView.minimumWindowEdge
                )
                .environment(workspaceStore)
        }
        .handlesExternalEvents(matching: [])
        // Transparent titlebar keeps the full-height sidebar behind the traffic
        // lights; WorkspaceSplitView routes blank titlebar hits to native chrome.
        .windowStyle(.hiddenTitleBar)
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
