import AppKit
import SwiftUI

struct SettingsView: View {
    #if DIRECT_DISTRIBUTION
    static let minimumContentHeight: CGFloat = 636
    #else
    static let minimumContentHeight: CGFloat = 504
    #endif

    @Environment(WorkspaceStore.self) private var workspaceStore
    #if DIRECT_DISTRIBUTION
    @State private var updater = AppUpdater.shared
    #endif

    var body: some View {
        @Bindable var workspace = workspaceStore

        Form {
            Section("settings.section.files") {
                LabeledContent {
                    Button(action: workspaceStore.chooseDocumentsFolder) {
                        Text("settings.defaultApp.choose")
                            .labelStyle(.titleOnly)
                    }
                    .accessibilityLabel("Choose Folder…")
                    .accessibilityIdentifier("settings.documentsFolder.choose")
                } label: {
                    SettingsRowLabel(
                        title: "Documents Folder",
                        systemImage: "folder",
                        subtitle: workspaceStore.documentsFolderName,
                        subtitleHelp: workspaceStore.documentsFolder.path,
                        subtitleAccessibilityLabel: workspaceStore.documentsFolder.path,
                        subtitleTruncation: .middle
                    )
                }

                LabeledContent {
                    Button(action: workspaceStore.presentDefaultAppSettingsSheet) {
                        Text("settings.defaultApp.choose")
                            .labelStyle(.titleOnly)
                    }
                    .accessibilityIdentifier("settings.defaultApp.manage")
                } label: {
                    SettingsRowLabel(
                        title: "settings.defaultApp.label",
                        systemImage: "doc.text",
                        subtitle: workspaceStore.defaultFileTypesSummary,
                        subtitleAccessibilityIdentifier: "settings.defaultApp.status",
                        subtitleTruncation: .tail
                    )
                }
            }

            Section("Editor") {
                Picker(selection: $workspace.preferences.editorTheme) {
                    ForEach(EditorTheme.allCases, id: \.self) { theme in
                        Text(LocalizedStringKey(theme.localizedNameKey))
                            .labelStyle(.titleOnly)
                            .tag(theme)
                    }
                } label: {
                    SettingsRowLabel(title: "settings.theme", systemImage: "paintpalette")
                }
                .accessibilityIdentifier("settings.theme")

                LabeledContent {
                    HStack(spacing: 10) {
                        Slider(
                            value: interfaceFontSizeBinding,
                            in: 0...Double(InterfaceFontSize.allCases.count - 1),
                            step: 1
                        ) {
                            Text("settings.interfaceFontSize")
                        }
                        .labelsHidden()
                        .frame(width: 140)
                        .accessibilityValue(
                            Text(LocalizedStringKey(workspaceStore.preferences.interfaceFontSize.localizedNameKey))
                        )
                        .accessibilityIdentifier("settings.interfaceFontSize.slider")

                        Text(LocalizedStringKey(workspaceStore.preferences.interfaceFontSize.localizedNameKey))
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 72, alignment: .trailing)
                            .accessibilityIdentifier("settings.interfaceFontSize.value")
                    }
                } label: {
                    SettingsRowLabel(
                        title: "settings.interfaceFontSize",
                        systemImage: "textformat.size"
                    )
                }

                Picker(selection: $workspace.preferences.tabBehavior) {
                    ForEach(TabBehavior.allCases, id: \.self) { behavior in
                        Text(LocalizedStringKey(behavior.rawValue))
                            .labelStyle(.titleOnly)
                            .tag(behavior)
                    }
                } label: {
                    SettingsRowLabel(title: "Tab Behavior", systemImage: "increase.indent")
                }

                Picker(selection: $workspace.preferences.appLanguage) {
                    ForEach(AppLanguage.allCases, id: \.self) { language in
                        Text(LocalizedStringKey(language.localizedNameKey))
                            .labelStyle(.titleOnly)
                            .tag(language)
                    }
                } label: {
                    SettingsRowLabel(title: "Language", systemImage: "globe")
                }

                if workspaceStore.isLanguageChangePendingRestart {
                    HStack(alignment: .center, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .frame(width: 18, height: 18, alignment: .center)
                            .accessibilityHidden(true)
                        Text("A restart is required for language changes to take effect.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            #if DIRECT_DISTRIBUTION
            Section("Updates") {
                Toggle(isOn: Binding(
                    get: { updater.automaticallyChecksForUpdates },
                    set: { updater.setAutomaticChecks($0) }
                )) {
                    SettingsRowLabel(
                        title: "Automatically check for updates",
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                }
                .disabled(!updater.canCheckForUpdates)

                Toggle(isOn: Binding(
                    get: { updater.automaticallyDownloadsUpdates },
                    set: { updater.setAutomaticDownloads($0) }
                )) {
                    SettingsRowLabel(
                        title: "Automatically download and install updates",
                        systemImage: "arrow.down.circle"
                    )
                }
                .disabled(!updater.canCheckForUpdates || !updater.allowsAutomaticUpdates)
            }
            #endif

            Section { aboutRow }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .toggleStyle(.switch)
        .scrollDisabled(true)
        .frame(width: 480)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(EditorChrome.editorSurface(for: workspaceStore.preferences.editorTheme))
        .focusEffectDisabled()
        .task {
            await workspaceStore.refreshDefaultFileTypeStatuses()
        }
    }

    private var interfaceFontSizeBinding: Binding<Double> {
        Binding(
            get: { Double(workspaceStore.preferences.interfaceFontSize.stepIndex) },
            set: { newValue in
                let nextSize = InterfaceFontSize(stepIndex: Int(newValue.rounded()))
                if workspaceStore.preferences.interfaceFontSize != nextSize {
                    workspaceStore.preferences.interfaceFontSize = nextSize
                }
            }
        )
    }

    private var aboutRow: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: "NeatEditor")
                    .fontWeight(.medium)
                Text(verbatim: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                #if DIRECT_DISTRIBUTION
                Button {
                    updater.checkForUpdates()
                } label: {
                    Label("Check for Updates…", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(!updater.canCheckForUpdates)
                #endif

                Button {
                    NSApp.terminate(nil)
                } label: {
                    Label("settings.quit", systemImage: "power")
                }
            }
            .fixedSize()
        }
    }
}

private struct SettingsRowLabel: View {
    let title: LocalizedStringKey
    let systemImage: String
    var subtitle: String? = nil
    var subtitleHelp: String? = nil
    var subtitleAccessibilityLabel: String? = nil
    var subtitleAccessibilityIdentifier: String? = nil
    var subtitleTruncation: Text.TruncationMode = .tail

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 13.5, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18, alignment: .center)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle {
                    subtitleView(subtitle)
                }
            }
        }
    }

    @ViewBuilder
    private func subtitleView(_ text: String) -> some View {
        let base = Text(verbatim: text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(subtitleTruncation)

        subtitleWithAccessibility(
            subtitleWithHelp(base)
        )
    }

    @ViewBuilder
    private func subtitleWithHelp<Content: View>(_ content: Content) -> some View {
        if let subtitleHelp {
            content.help(subtitleHelp)
        } else {
            content
        }
    }

    @ViewBuilder
    private func subtitleWithAccessibility<Content: View>(_ content: Content) -> some View {
        if let subtitleAccessibilityLabel, let subtitleAccessibilityIdentifier {
            content
                .accessibilityLabel(Text(verbatim: subtitleAccessibilityLabel))
                .accessibilityIdentifier(subtitleAccessibilityIdentifier)
        } else if let subtitleAccessibilityLabel {
            content.accessibilityLabel(Text(verbatim: subtitleAccessibilityLabel))
        } else if let subtitleAccessibilityIdentifier {
            content.accessibilityIdentifier(subtitleAccessibilityIdentifier)
        } else {
            content
        }
    }
}
