import SwiftUI

struct WorkspaceSidebarView: View {
    @Environment(WorkspaceStore.self) private var workspaceStore
    @State private var renamingItem: WorkspaceSidebarItem?
    @State private var renameDraft = ""

    var body: some View {
        List(selection: selection) {
            Section {
                ForEach(workspaceStore.sidebarFiles) { item in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        if !item.preview.isEmpty {
                            Text(item.preview)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(.vertical, 3)
                    .tag(item.fileURL)
                    .contextMenu {
                        sidebarItemMenu(for: item)
                    }
                }
            } header: {
                folderHeader
            }
        }
        .listStyle(.sidebar)
        .focusEffectDisabled()
        .overlay {
            if workspaceStore.sidebarFiles.isEmpty {
                emptyState
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let message = workspaceStore.sidebarFailureMessage,
               !workspaceStore.sidebarFiles.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Retry", action: workspaceStore.refreshSidebarFiles)
                }
                .padding()
            }
        }
        .contextMenu {
            Button(action: workspaceStore.createNewDocument) {
                Label("New Document", systemImage: "plus")
            }
            Button(action: workspaceStore.chooseDocumentsFolder) {
                Label("Choose Folder…", systemImage: "folder")
            }
            Button(action: workspaceStore.refreshSidebarFiles) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
        .alert(
            "Rename",
            isPresented: renameAlertIsPresented,
            presenting: renamingItem
        ) { item in
            TextField("New Name", text: $renameDraft)
            Button("Rename") {
                commitSidebarRename(for: item)
            }
            Button("Cancel", role: .cancel) {
                renamingItem = nil
            }
        } message: { item in
            Text(item.title)
        }
    }

    private var selection: Binding<URL?> {
        Binding(
            get: { workspaceStore.selectedSidebarFileURL },
            set: { fileURL in
                guard let fileURL else { return }
                workspaceStore.openSidebarFile(fileURL)
            }
        )
    }

    private var folderHeader: some View {
        HStack(spacing: 6) {
            Text(workspaceStore.documentsFolderName)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(workspaceStore.documentsFolder.path)

            Spacer(minLength: 0)

            Menu {
                Button(action: workspaceStore.chooseDocumentsFolder) {
                    Label("Choose Folder…", systemImage: "folder")
                }
                Button(action: workspaceStore.revealDocumentsFolderInFinder) {
                    Label("Show in Finder", systemImage: "folder")
                }
                Divider()
                Button(action: workspaceStore.refreshSidebarFiles) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Folder Actions")
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if workspaceStore.isRefreshingSidebar {
            ProgressView()
                .controlSize(.small)
        } else if let message = workspaceStore.sidebarFailureMessage {
            ContentUnavailableView {
                Label("Couldn’t Load Documents", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Retry", action: workspaceStore.refreshSidebarFiles)
                Button("Choose Folder…", action: workspaceStore.chooseDocumentsFolder)
            }
        } else {
            ContentUnavailableView {
                Label("No Documents", systemImage: "doc.text")
            } actions: {
                Button("New Document", action: workspaceStore.createNewDocument)
                Button("Choose Folder…", action: workspaceStore.chooseDocumentsFolder)
            }
        }
    }

    @ViewBuilder
    private func sidebarItemMenu(for item: WorkspaceSidebarItem) -> some View {
        Button {
            workspaceStore.openSidebarFile(item.fileURL)
        } label: {
            Label("Open", systemImage: "doc")
        }

        Button {
            workspaceStore.revealSidebarFileInFinder(item.fileURL)
        } label: {
            Label("Show in Finder", systemImage: "folder")
        }

        Divider()

        Button {
            renamingItem = item
            renameDraft = item.title
        } label: {
            Label("Rename…", systemImage: "pencil")
        }

        Button {
            workspaceStore.duplicateSidebarFile(at: item.fileURL)
        } label: {
            Label("Duplicate", systemImage: "plus.square.on.square")
        }

        Button {
            workspaceStore.copySidebarFilePath(item.fileURL)
        } label: {
            Label("Copy Path", systemImage: "doc.on.doc")
        }

        Divider()

        Button(role: .destructive) {
            workspaceStore.trashSidebarFile(at: item.fileURL)
        } label: {
            Label("Move to Trash", systemImage: "trash")
        }
    }

    private var renameAlertIsPresented: Binding<Bool> {
        Binding(
            get: { renamingItem != nil },
            set: { if !$0 { renamingItem = nil } }
        )
    }

    private func commitSidebarRename(for item: WorkspaceSidebarItem) {
        let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        renamingItem = nil
        guard !trimmed.isEmpty, trimmed != item.title else { return }
        workspaceStore.renameSidebarFile(at: item.fileURL, to: trimmed)
    }
}

#Preview {
    WorkspaceSidebarView()
        .environment(WorkspaceStore())
        .frame(width: 260, height: 500)
}
