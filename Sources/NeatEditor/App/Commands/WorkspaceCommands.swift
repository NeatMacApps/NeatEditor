import AppKit
import SwiftUI

struct WorkspaceCommands: Commands {
    let workspaceStore: WorkspaceStore

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button {
                workspaceStore.createNewDocument()
            } label: {
                Label("New", systemImage: "doc")
                    .labelStyle(.titleAndIcon)
            }
            .keyboardShortcut("n", modifiers: .command)

            Button {
                workspaceStore.createNewDocument()
            } label: {
                Label("New Tab", systemImage: "plus.square")
                    .labelStyle(.titleAndIcon)
            }
            .keyboardShortcut("t", modifiers: .command)
        }

        CommandGroup(after: .newItem) {
            Button {
                openDocumentsFromUserHome()
            } label: {
                Label("Open...", systemImage: "folder")
                    .labelStyle(.titleAndIcon)
            }
            .keyboardShortcut("o", modifiers: .command)
        }

        CommandGroup(replacing: .appSettings) {
            Button {
                workspaceStore.openSettings()
            } label: {
                Label("Settings...", systemImage: "gearshape")
                    .labelStyle(.titleAndIcon)
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        CommandGroup(replacing: .saveItem) {
            Button {
                workspaceStore.saveCurrentDocument()
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
                    .labelStyle(.titleAndIcon)
            }
            .keyboardShortcut("s", modifiers: .command)

            Button {
                workspaceStore.saveAndCloseCurrentDocument()
            } label: {
                Label("Close Tab", systemImage: "xmark")
                    .labelStyle(.titleAndIcon)
            }
            .keyboardShortcut("w", modifiers: .command)
            .disabled(workspaceStore.selectedTabID == nil)

            Button {
                workspaceStore.reopenLastClosedDocument()
            } label: {
                Label("Reopen Closed Tab", systemImage: "arrow.uturn.backward")
                    .labelStyle(.titleAndIcon)
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            .disabled(!workspaceStore.canReopenClosedTab)
        }

        CommandGroup(after: .textEditing) {
            Button {
                workspaceStore.presentSearchBar()
            } label: {
                Label("Find", systemImage: "magnifyingglass")
                    .labelStyle(.titleAndIcon)
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(workspaceStore.selectedTabID == nil)
        }

        CommandGroup(after: .toolbar) {
            Button {
                workspaceStore.increaseEditorFontSize()
            } label: {
                Label("Zoom In", systemImage: "plus.magnifyingglass")
                    .labelStyle(.titleAndIcon)
            }
            .keyboardShortcut("=", modifiers: .command)

            Button {
                workspaceStore.decreaseEditorFontSize()
            } label: {
                Label("Zoom Out", systemImage: "minus.magnifyingglass")
                    .labelStyle(.titleAndIcon)
            }
            .keyboardShortcut("-", modifiers: .command)
        }

        CommandGroup(after: .sidebar) {
            Button {
                workspaceStore.toggleSidebar()
            } label: {
                Label("Toggle Sidebar", systemImage: "sidebar.left")
                    .labelStyle(.titleAndIcon)
            }
            .keyboardShortcut("s", modifiers: [.command, .option])
        }
    }

    @MainActor
    private func openDocumentsFromUserHome() {
        let panel = NSOpenPanel()
        panel.directoryURL = workspaceStore.documentsFolder
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.resolvesAliases = true

        guard panel.runModal() == .OK else {
            return
        }

        workspaceStore.openFiles(at: panel.urls)
    }
}
