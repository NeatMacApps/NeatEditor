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
                    Picker("Tab Behavior", selection: $workspace.preferences.tabBehavior) {
                        ForEach(TabBehavior.allCases, id: \.self) { behavior in
                            Text(LocalizedStringKey(behavior.rawValue)).tag(behavior)
                        }
                    }
                    Picker("Language", selection: $workspace.preferences.appLanguage) {
                        ForEach(AppLanguage.allCases, id: \.self) { language in
                            Text(LocalizedStringKey(language.localizedNameKey)).tag(language)
                        }
                    }
                    if workspaceStore.isLanguageChangePendingRestart {
                        Text("A restart is required for language changes to take effect.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                Section("Updates") {
                    Toggle("Automatically check for updates", isOn: Binding(
                        get: { updater.automaticallyChecksForUpdates },
                        set: { updater.setAutomaticChecks($0) }
                    ))
                    .disabled(!updater.canCheckForUpdates)
                    Toggle("Automatically download and install updates", isOn: Binding(
                        get: { updater.automaticallyDownloadsUpdates },
                        set: { updater.setAutomaticDownloads($0) }
                    ))
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
            Button("Check for Updates…") { updater.checkForUpdates() }
                .disabled(!updater.canCheckForUpdates)
            Button("settings.quit") { NSApp.terminate(nil) }
        }
    }
}
