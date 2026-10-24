import SwiftUI

struct WorkspaceView: View {
    private enum UserDefaultsKey {
        static let hasShownCloseTabShortcutHint = "hasShownCloseTabShortcutHint"
    }

    @Environment(WorkspaceStore.self) private var workspaceStore
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(UserDefaultsKey.hasShownCloseTabShortcutHint)
    private var hasShownCloseTabShortcutHint = false
    @FocusState private var isSearchFieldFocused: Bool
    @State private var isCloseTabShortcutHintVisible = false
    @State private var isWindowPinned = false

    var body: some View {
        NavigationSplitView(columnVisibility: sidebarVisibility) {
            WorkspaceSidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 360)
        } detail: {
            editorColumn
                .frame(minWidth: isSettingsSelected ? 500 : 300)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: workspaceStore.createNewDocument) {
                            Label("New Document", systemImage: "square.and.pencil")
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Toggle(isOn: $isWindowPinned) {
                            Label("Always on Top", systemImage: "pin")
                        }
                        .toggleStyle(.button)
                        .help(isWindowPinned ? "Disable Always on Top" : "Enable Always on Top")
                    }
                }
        }
        .navigationSplitViewStyle(.balanced)
        .background {
            WindowPinningView(isWindowPinned: isWindowPinned)
        }
        .focusEffectDisabled()
        .alert(
            workspaceStore.documentFailureAlert?.title ?? String(localized: "Save Failed"),
            isPresented: documentFailureAlertIsPresented,
            presenting: workspaceStore.documentFailureAlert
        ) { _ in
            Button("OK", role: .cancel) {
                workspaceStore.dismissDocumentFailureAlert()
            }
        } message: { alert in
            Text(alert.message)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                workspaceStore.refreshSidebarFiles()
            }
            if newPhase == .inactive || newPhase == .background {
                workspaceStore.saveAllDocuments()
            }
        }
        .onChange(of: workspaceStore.searchState.focusRequestID) { _, _ in
            isSearchFieldFocused = workspaceStore.searchState.isPresented
        }
        .onChange(of: workspaceStore.tabs.count) { _, newCount in
            presentCloseTabShortcutHintIfNeeded(for: newCount)
        }
        .dropDestination(for: URL.self) { items, _ in
            workspaceStore.openFiles(at: items)
            return true
        }
        .task {
            workspaceStore.refreshSidebarFiles()
            presentCloseTabShortcutHintIfNeeded(for: workspaceStore.tabs.count)
        }
    }

    private var isSettingsSelected: Bool {
        workspaceStore.tabs.contains { $0.id == workspaceStore.selectedTabID && $0.isSettings }
    }

    private var sidebarVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { workspaceStore.preferences.isSidebarVisible ? .all : .detailOnly },
            set: { workspaceStore.preferences.isSidebarVisible = $0 != .detailOnly }
        )
    }

    private var editorColumn: some View {
        VStack(spacing: 0) {
            @Bindable var bindableWorkspace = workspaceStore
            EditorTabStripView(
                tabs: $bindableWorkspace.tabs,
                selectedTabID: workspaceStore.selectedTabID,
                onSelectTab: workspaceStore.selectTab,
                onSelectTabRelative: workspaceStore.selectTab(relativeOffset:),
                onRenameTab: workspaceStore.renameDocument,
                onCloseTab: workspaceStore.closeDocument,
                onDeleteTab: workspaceStore.moveToTrash,
                onCloseOtherTabs: workspaceStore.closeOtherDocuments(keeping:)
            )

            if isCloseTabShortcutHintVisible {
                CloseTabShortcutHint {
                    dismissCloseTabShortcutHint()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            if let selectedTabID = workspaceStore.selectedTabID,
               let index = workspaceStore.tabs.firstIndex(where: { $0.id == selectedTabID }) {
                editorBody(for: workspaceStore.tabs[index], selectedTabID: selectedTabID)
            } else {
                Text("No Document Selected")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(EditorChrome.editorSurface)
            }

            if workspaceStore.searchState.isPresented {
                searchBar
            }
        }
    }

    private func editorBody(for tab: EditorTab, selectedTabID: UUID) -> some View {
        Group {
            if tab.isSettings {
                SettingsView()
            } else {
                EditorTextView(
                    tabID: tab.id,
                    text: Self.textBinding(for: tab.id, in: workspaceStore),
                    fontSize: workspaceStore.preferences.editorFontSize,
                    isEditable: tab.isContentLoaded,
                    tabBehavior: workspaceStore.preferences.tabBehavior,
                    textSoftness: workspaceStore.preferences.editorTextSoftness,
                    searchState: workspaceStore.searchState,
                    onTextChange: { isComposing in
                        if isComposing {
                            workspaceStore.cancelAutoSave(for: selectedTabID)
                        } else {
                            workspaceStore.queueAutoSave(for: selectedTabID)
                        }
                    },
                    onCompositionEnd: {
                        workspaceStore.queueAutoSave(for: selectedTabID)
                    },
                    onIncreaseFontSize: {
                        workspaceStore.increaseEditorFontSize()
                    },
                    onDecreaseFontSize: {
                        workspaceStore.decreaseEditorFontSize()
                    },
                    onOpenFiles: { urls in
                        workspaceStore.openFiles(at: urls)
                    },
                    onRegisterCommitHandler: { handler in
                        workspaceStore.commitEditorChanges = handler
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .background(EditorChrome.editorSurface)
                .overlay {
                    EditorSurfaceBorderShape()
                        .stroke(EditorChrome.border, lineWidth: EditorChrome.lineWidth)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var searchBar: some View {
        @Bindable var bindableWorkspace = workspaceStore

        return HStack(spacing: 12) {
            TextField("Search", text: $bindableWorkspace.searchState.query)
                .textFieldStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(NSColor.textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .focusEffectDisabled()
                .focused($isSearchFieldFocused)
                .onSubmit {
                    workspaceStore.submitSearch()
                }

            Button {
                workspaceStore.toggleRegexSearch()
            } label: {
                Text(".*")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(
                        workspaceStore.searchState.isRegexEnabled ? Color.accentColor : .secondary
                    )
                    .frame(minWidth: 28)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel(
                workspaceStore.searchState.isRegexEnabled
                ? "Disable Regular Expression Search"
                : "Enable Regular Expression Search"
            )

            Button("Search") {
                workspaceStore.submitSearch()
            }
            .disabled(isSearchActionDisabled)

            Button {
                workspaceStore.dismissSearchBar()
                isSearchFieldFocused = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .background(.tertiary.opacity(0.4), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close Search")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(EditorChrome.tabBarBackground)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(EditorChrome.border)
                .frame(height: EditorChrome.lineWidth)
        }
    }

    private var isSearchActionDisabled: Bool {
        workspaceStore.selectedTabID == nil ||
        !workspaceStore.searchState.canSubmit
    }

    static func textBinding(for id: UUID, in store: WorkspaceStore) -> Binding<String> {
        Binding(
            get: { store.tabs.first(where: { $0.id == id })?.content ?? "" },
            set: { store.updateDocumentContent($0, for: id) }
        )
    }

    private var documentFailureAlertIsPresented: Binding<Bool> {
        Binding(
            get: { workspaceStore.documentFailureAlert != nil },
            set: { isPresented in
                if !isPresented {
                    workspaceStore.dismissDocumentFailureAlert()
                }
            }
        )
    }

    private func presentCloseTabShortcutHintIfNeeded(for tabCount: Int) {
        guard tabCount > 1, !hasShownCloseTabShortcutHint, !isCloseTabShortcutHintVisible else {
            return
        }

        hasShownCloseTabShortcutHint = true
        withAnimation(.snappy(duration: 0.24)) {
            isCloseTabShortcutHintVisible = true
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            dismissCloseTabShortcutHint()
        }
    }

    private func dismissCloseTabShortcutHint() {
        guard isCloseTabShortcutHintVisible else {
            return
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            isCloseTabShortcutHintVisible = false
        }
    }
}

private struct CloseTabShortcutHint: View {
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Label("Press", systemImage: "keyboard")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            (
                Text("Use ")
                + Text("\u{2318}W").fontWeight(.semibold)
                + Text(" to close the current tab")
            )
            .font(.system(size: 12))
            .foregroundStyle(.primary)

            Spacer(minLength: 0)

            Button("Got it") {
                onDismiss()
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(EditorChrome.tabBarBackground)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(EditorChrome.border)
                .frame(height: EditorChrome.lineWidth)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(EditorChrome.border)
                .frame(height: EditorChrome.lineWidth)
        }
    }
}

#Preview {
    WorkspaceView()
        .environment(WorkspaceStore())
        .frame(width: 800, height: 600)
}
