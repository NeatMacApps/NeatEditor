import SwiftUI

struct DefaultAppRegistrationSheet: View {
    @Environment(WorkspaceStore.self) private var workspaceStore

    var body: some View {
        if let prompt = workspaceStore.defaultAppPrompt {
            content(for: prompt)
        }
    }

    private func content(for prompt: DefaultAppPromptState) -> some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    ForEach(DefaultFileType.allCases) { fileType in
                        fileTypeRow(fileType, in: prompt)
                    }

                    if let feedback = prompt.feedbackMessage {
                        Label {
                            Text(feedback)
                        } icon: {
                            Image(systemName: prompt.isErrorFeedback ? "exclamationmark.triangle.fill" : "info.circle")
                                .foregroundStyle(prompt.isErrorFeedback ? Color.orange : Color.secondary)
                        }
                        .font(.caption)
                        .foregroundStyle(prompt.isErrorFeedback ? .orange : .secondary)
                        .accessibilityIdentifier("defaultApp.feedback")
                    }
                } header: {
                    Text(LocalizedStringKey(headerTitleKey(for: prompt.trigger)))
                } footer: {
                    if prompt.hasUnassignedTypes {
                        Text("defaultApp.sheet.systemConfirmationNote")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .toggleStyle(.switch)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                if prompt.showsDontAskAgain {
                    Button("defaultApp.action.dontAskAgain") {
                        workspaceStore.dismissDefaultAppPrompt(suppressFuturePrompts: true)
                    }
                    .disabled(prompt.isApplying)
                    .accessibilityIdentifier("defaultApp.action.dontAskAgain")
                }

                Spacer(minLength: 12)

                if prompt.isApplying {
                    ProgressView()
                        .controlSize(.small)
                }

                Button(LocalizedStringKey(dismissTitleKey(for: prompt))) {
                    workspaceStore.dismissDefaultAppPrompt(suppressFuturePrompts: false)
                }
                .keyboardShortcut(.cancelAction)
                .disabled(prompt.isApplying)
                .accessibilityIdentifier("defaultApp.action.cancel")

                if prompt.hasUnassignedTypes {
                    Button("defaultApp.action.setAsDefault") {
                        Task {
                            await workspaceStore.applySelectedDefaultAppTypes()
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(prompt.isApplying || selectedUnassignedCount(in: prompt) == 0)
                    .accessibilityIdentifier("defaultApp.action.apply")
                }
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 440)
        .focusEffectDisabled()
        .interactiveDismissDisabled(prompt.isApplying)
        .accessibilityIdentifier("defaultApp.sheet")
    }

    @ViewBuilder
    private func fileTypeRow(_ fileType: DefaultFileType, in prompt: DefaultAppPromptState) -> some View {
        let status = prompt.statuses[fileType]
        let labelView = VStack(alignment: .leading, spacing: 2) {
            Text(LocalizedStringKey(fileType.titleLocalizationKey))
            Text(currentAppSubtitle(for: status))
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        if status?.isCurrentAppDefault == true {
            LabeledContent {
                Label("defaultApp.status.default", systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("defaultApp.status.\(fileType.rawValue)")
            } label: {
                labelView
            }
        } else {
            Toggle(
                isOn: Binding(
                    get: { prompt.selectedTypes.contains(fileType) },
                    set: { workspaceStore.setDefaultFileTypeSelected($0, for: fileType) }
                )
            ) {
                labelView
            }
            .disabled(prompt.isApplying)
            .accessibilityIdentifier("defaultApp.toggle.\(fileType.rawValue)")
        }
    }

    private func headerTitleKey(for trigger: DefaultAppPromptState.Trigger) -> String {
        switch trigger {
        case .startup, .externalOpen:
            "defaultApp.sheet.title.prompt"
        case .settings:
            "defaultApp.sheet.title.settings"
        }
    }

    private func dismissTitleKey(for prompt: DefaultAppPromptState) -> String {
        if !prompt.hasUnassignedTypes {
            return "defaultApp.action.done"
        }
        return prompt.showsDontAskAgain ? "defaultApp.action.notNow" : "Cancel"
    }

    private func selectedUnassignedCount(in prompt: DefaultAppPromptState) -> Int {
        DefaultFileType.allCases.count(where: {
            prompt.selectedTypes.contains($0) && prompt.statuses[$0]?.isCurrentAppDefault != true
        })
    }

    private func currentAppSubtitle(for status: DefaultFileTypeStatus?) -> String {
        if let name = status?.currentApplicationName, !name.isEmpty {
            return String(format: String(localized: "defaultApp.currentApp.format"), name)
        }
        return String(localized: "defaultApp.currentApp.none")
    }
}
