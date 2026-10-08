import SwiftUI

@main
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
                    minWidth: EditorTabStripView.minimumWindowEdge,
                    minHeight: EditorTabStripView.minimumWindowEdge
                )
                .environment(workspaceStore)
        }
        .handlesExternalEvents(matching: [])
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 800, height: 600)
        .commands {
            NeatEditorUpdateCommands()
            WorkspaceCommands(workspaceStore: workspaceStore)
        }
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
