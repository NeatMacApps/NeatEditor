import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(WorkspaceStore.self) private var workspaceStore
    @State private var updater = AppUpdater.shared

    var body: some View {
        @Bindable var workspace = workspaceStore

        VStack(spacing: 0) {
            Text("Settings")
                .font(.title2.weight(.semibold))
                .frame(width: 440, alignment: .leading)
                .padding(.top, 20)
            Form {
                Section("Editor") {
                    LabeledContent {
                        HStack {
                            Text(verbatim: workspaceStore.documentsFolderName)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(workspaceStore.documentsFolder.path)
                                .accessibilityLabel(Text(verbatim: workspaceStore.documentsFolder.path))
                            Button(action: workspaceStore.chooseDocumentsFolder) {
                                Label("Choose Folder…", systemImage: "folder")
                            }
                            .accessibilityIdentifier("settings.documentsFolder.choose")
                        }
                    } label: {
                        Label("Documents Folder", systemImage: "folder")
                    }
                    Picker(selection: $workspace.preferences.editorTheme) {
                        ForEach(EditorTheme.allCases, id: \.self) { theme in
                            Label(LocalizedStringKey(theme.localizedNameKey),
                                  systemImage: theme.settingsSymbol)
                                .tag(theme)
                        }
                    } label: {
                        Label("settings.theme", systemImage: "paintpalette")
                    }
                    .accessibilityIdentifier("settings.theme")
                    Picker(selection: $workspace.preferences.tabBehavior) {
                        ForEach(TabBehavior.allCases, id: \.self) { behavior in
                            Label(LocalizedStringKey(behavior.rawValue),
                                  systemImage: behavior.settingsSymbol)
                                .tag(behavior)
                        }
                    } label: {
                        Label("Tab Behavior", systemImage: "increase.indent")
                    }
                    Picker(selection: $workspace.preferences.appLanguage) {
                        ForEach(AppLanguage.allCases, id: \.self) { language in
                            Label(LocalizedStringKey(language.localizedNameKey),
                                  systemImage: language.settingsSymbol)
                                .tag(language)
                        }
                    } label: {
                        Label("Language", systemImage: "globe")
                    }
                    if workspaceStore.isLanguageChangePendingRestart {
                        Text("A restart is required for language changes to take effect.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                Section("Updates") {
                    Toggle(isOn: Binding(
                        get: { updater.automaticallyChecksForUpdates },
                        set: { updater.setAutomaticChecks($0) }
                    )) {
                        Label("Automatically check for updates", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(!updater.canCheckForUpdates)
                    Toggle(isOn: Binding(
                        get: { updater.automaticallyDownloadsUpdates },
                        set: { updater.setAutomaticDownloads($0) }
                    )) {
                        Label("Automatically download and install updates", systemImage: "arrow.down.circle")
                    }
                    .disabled(!updater.canCheckForUpdates || !updater.allowsAutomaticUpdates)
                }
                Section { aboutRow }
            }
            .formStyle(.grouped)
            .toggleStyle(.switch)
            .scrollDisabled(true)
            .frame(width: 480)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .focusEffectDisabled()
    }

    private var aboutRow: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: "NeatEditor").fontWeight(.medium)
                Text(verbatim: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 12)
            Button {
                updater.checkForUpdates()
            } label: {
                Label("Check for Updates…", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(!updater.canCheckForUpdates)
            Button {
                NSApp.terminate(nil)
            } label: {
                Label("settings.quit", systemImage: "power")
            }
        }
    }
}
