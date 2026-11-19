import Foundation

enum FileOpenSource: Sendable {
    case `internal`
    case external
}

struct DefaultAppPromptState: Identifiable, Equatable {
    enum Trigger: Equatable {
        case startup
        case externalOpen(Set<DefaultFileType>)
        case settings
    }

    let id = UUID()
    var trigger: Trigger
    var statuses: [DefaultFileType: DefaultFileTypeStatus]
    var selectedTypes: Set<DefaultFileType>
    var isApplying = false
    var hasUserModifiedSelection = false
    var feedbackMessage: String?
    var isErrorFeedback = false

    var showsDontAskAgain: Bool {
        trigger != .settings
    }

    var hasUnassignedTypes: Bool {
        DefaultFileType.allCases.contains { statuses[$0]?.isCurrentAppDefault != true }
    }
}

extension WorkspaceStore {
    // MARK: - Default File Types

    var defaultFileTypesSummary: String {
        let isPlainTextDefault = defaultFileTypeStatuses[.plainText]?.isCurrentAppDefault == true
        let isMarkdownDefault = defaultFileTypeStatuses[.markdown]?.isCurrentAppDefault == true

        switch (isPlainTextDefault, isMarkdownDefault) {
        case (true, true):
            return String(localized: "settings.defaultApp.summary.all")
        case (true, false):
            return String(localized: "settings.defaultApp.summary.plainText")
        case (false, true):
            return String(localized: "settings.defaultApp.summary.markdown")
        case (false, false):
            return String(localized: "settings.defaultApp.summary.none")
        }
    }

    func refreshDefaultFileTypeStatuses() async {
        let statuses = await fileAssociationService.fetchStatuses(for: DefaultFileType.allCases)
        defaultFileTypeStatuses = statuses
        if var prompt = defaultAppPrompt, !prompt.isApplying {
            prompt.statuses = statuses
            defaultAppPrompt = prompt
        }
    }

    func evaluateDefaultAppPromptOnLaunch() async {
        guard !hasCompletedLaunchDefaultAppCheck else {
            return
        }
        hasCompletedLaunchDefaultAppCheck = true
        isAwaitingLaunchDefaultAppPrompt = true
        defer { isAwaitingLaunchDefaultAppPrompt = false }

        let statuses = await fileAssociationService.fetchStatuses(for: DefaultFileType.allCases)
        defaultFileTypeStatuses = statuses

        if enablesAutomaticDefaultAppPrompts,
           !userDefaults.bool(forKey: UserDefaultsKey.isDefaultAppPromptSuppressed),
           pendingExternalDefaultAppTypes.isEmpty,
           launchDefaultAppPromptDelay > .zero {
            try? await Task.sleep(for: launchDefaultAppPromptDelay)
        }
        guard !Task.isCancelled else {
            return
        }

        let queuedExternal = pendingExternalDefaultAppTypes
        pendingExternalDefaultAppTypes.removeAll()

        guard enablesAutomaticDefaultAppPrompts,
              !userDefaults.bool(forKey: UserDefaultsKey.isDefaultAppPromptSuppressed),
              defaultAppPrompt == nil,
              documentFailureAlert == nil else {
            return
        }

        if !queuedExternal.isEmpty {
            presentExternalPromptIfNeeded(for: queuedExternal, statuses: statuses)
            return
        }

        guard !userDefaults.bool(forKey: UserDefaultsKey.hasHandledStartupDefaultAppPrompt) else {
            return
        }

        if statuses[.plainText]?.isCurrentAppDefault == true {
            userDefaults.set(true, forKey: UserDefaultsKey.hasHandledStartupDefaultAppPrompt)
            return
        }

        defaultAppPrompt = DefaultAppPromptState(
            trigger: .startup,
            statuses: statuses,
            selectedTypes: [.plainText]
        )
    }

    func recordExternalFileOpenForDefaultAppCheck(urls: [URL]) {
        let matched = Set(urls.compactMap(DefaultFileType.match(for:)))
        guard !matched.isEmpty,
              enablesAutomaticDefaultAppPrompts,
              !userDefaults.bool(forKey: UserDefaultsKey.isDefaultAppPromptSuppressed) else {
            return
        }

        pendingExternalDefaultAppTypes.formUnion(matched)

        if !hasCompletedLaunchDefaultAppCheck || isAwaitingLaunchDefaultAppPrompt {
            return
        }

        pendingDefaultAppTask?.cancel()
        pendingDefaultAppTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let statuses = await self.fileAssociationService.fetchStatuses(for: DefaultFileType.allCases)
            guard !Task.isCancelled else { return }
            self.defaultFileTypeStatuses = statuses
            let queued = self.pendingExternalDefaultAppTypes
            self.pendingExternalDefaultAppTypes.removeAll()
            self.presentExternalPromptIfNeeded(for: queued, statuses: statuses)
        }
    }

    func presentDefaultAppSettingsSheet() {
        guard defaultAppPrompt == nil else {
            return
        }

        pendingDefaultAppTask?.cancel()
        pendingDefaultAppTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let statuses = await self.fileAssociationService.fetchStatuses(for: DefaultFileType.allCases)
            guard !Task.isCancelled, self.defaultAppPrompt == nil else { return }
            self.defaultFileTypeStatuses = statuses
            let unassigned = Set(
                DefaultFileType.allCases.filter { statuses[$0]?.isCurrentAppDefault != true }
            )
            self.defaultAppPrompt = DefaultAppPromptState(
                trigger: .settings,
                statuses: statuses,
                selectedTypes: unassigned
            )
        }
    }

    func setDefaultFileTypeSelected(_ isSelected: Bool, for fileType: DefaultFileType) {
        guard var prompt = defaultAppPrompt, !prompt.isApplying else {
            return
        }
        prompt.hasUserModifiedSelection = true
        if isSelected {
            prompt.selectedTypes.insert(fileType)
        } else {
            prompt.selectedTypes.remove(fileType)
        }
        defaultAppPrompt = prompt
    }

    func applySelectedDefaultAppTypes() async {
        guard var prompt = defaultAppPrompt, !prompt.isApplying else {
            return
        }
        let promptID = prompt.id
        prompt.isApplying = true
        prompt.feedbackMessage = nil
        prompt.isErrorFeedback = false
        defaultAppPrompt = prompt

        let targets = DefaultFileType.allCases.filter {
            prompt.selectedTypes.contains($0) && prompt.statuses[$0]?.isCurrentAppDefault != true
        }
        if targets.isEmpty {
            markDefaultAppPromptHandled(for: prompt.trigger, refreshedStatuses: prompt.statuses)
            defaultAppPrompt = nil
            return
        }

        var unexpectedError: Error?
        for fileType in targets {
            do {
                try await fileAssociationService.setDefaultApplication(for: fileType)
            } catch {
                if !Self.isDefaultAppUserCancellation(error), unexpectedError == nil {
                    unexpectedError = error
                }
            }
        }

        let refreshed = await fileAssociationService.fetchStatuses(for: DefaultFileType.allCases)
        defaultFileTypeStatuses = refreshed

        guard var currentPrompt = defaultAppPrompt, currentPrompt.id == promptID else {
            return
        }

        let remaining = targets.filter { refreshed[$0]?.isCurrentAppDefault != true }
        if remaining.isEmpty {
            markDefaultAppPromptHandled(for: currentPrompt.trigger, refreshedStatuses: refreshed)
            defaultAppPrompt = nil
            return
        }

        currentPrompt.statuses = refreshed
        currentPrompt.selectedTypes = Set(remaining)
        currentPrompt.isApplying = false
        if let unexpectedError {
            currentPrompt.feedbackMessage = unexpectedError.localizedDescription
            currentPrompt.isErrorFeedback = true
        } else {
            currentPrompt.feedbackMessage = String(localized: "defaultApp.feedback.confirmationRequired")
            currentPrompt.isErrorFeedback = false
        }
        defaultAppPrompt = currentPrompt
    }

    func dismissDefaultAppPrompt(suppressFuturePrompts: Bool) {
        guard let prompt = defaultAppPrompt else {
            return
        }

        if suppressFuturePrompts {
            userDefaults.set(true, forKey: UserDefaultsKey.hasHandledStartupDefaultAppPrompt)
            userDefaults.set(true, forKey: UserDefaultsKey.isDefaultAppPromptSuppressed)
        } else {
            markDefaultAppPromptHandled(for: prompt.trigger, refreshedStatuses: prompt.statuses)
        }

        defaultAppPrompt = nil
    }

    // MARK: - Helpers

    private func presentExternalPromptIfNeeded(
        for types: Set<DefaultFileType>,
        statuses: [DefaultFileType: DefaultFileTypeStatus]
    ) {
        guard documentFailureAlert == nil,
              !userDefaults.bool(forKey: UserDefaultsKey.isDefaultAppPromptSuppressed) else {
            return
        }

        let dismissed = dismissedExternalDefaultAppPromptTypes()
        let actionable = types.filter {
            statuses[$0]?.isCurrentAppDefault != true && !dismissed.contains($0)
        }
        guard !actionable.isEmpty else {
            return
        }

        if defaultAppPrompt == nil {
            defaultAppPrompt = DefaultAppPromptState(
                trigger: .externalOpen(actionable),
                statuses: statuses,
                selectedTypes: actionable
            )
        } else if var existing = defaultAppPrompt,
                  existing.trigger == .startup,
                  !existing.isApplying,
                  !existing.hasUserModifiedSelection,
                  existing.feedbackMessage == nil {
            existing.trigger = .externalOpen(actionable)
            existing.statuses = statuses
            existing.selectedTypes = actionable
            defaultAppPrompt = existing
        }
    }

    private func markDefaultAppPromptHandled(
        for trigger: DefaultAppPromptState.Trigger,
        refreshedStatuses: [DefaultFileType: DefaultFileTypeStatus]
    ) {
        switch trigger {
        case .startup:
            userDefaults.set(true, forKey: UserDefaultsKey.hasHandledStartupDefaultAppPrompt)
        case .externalOpen(let types):
            let remainingUnassigned = types.filter {
                refreshedStatuses[$0]?.isCurrentAppDefault != true
            }
            if !remainingUnassigned.isEmpty {
                var dismissed = dismissedExternalDefaultAppPromptTypes()
                dismissed.formUnion(remainingUnassigned)
                userDefaults.set(
                    dismissed.map(\.rawValue).sorted(),
                    forKey: UserDefaultsKey.dismissedExternalDefaultAppPromptTypes
                )
            }
            if types.contains(.plainText) || refreshedStatuses[.plainText]?.isCurrentAppDefault == true {
                userDefaults.set(true, forKey: UserDefaultsKey.hasHandledStartupDefaultAppPrompt)
            }
        case .settings:
            break
        }
    }

    private func dismissedExternalDefaultAppPromptTypes() -> Set<DefaultFileType> {
        let rawValues = userDefaults.stringArray(
            forKey: UserDefaultsKey.dismissedExternalDefaultAppPromptTypes
        ) ?? []
        return Set(rawValues.compactMap(DefaultFileType.init(rawValue:)))
    }

    private static func isDefaultAppUserCancellation(_ error: Error) -> Bool {
        if let cocoaError = error as? CocoaError, cocoaError.code == .userCancelled {
            return true
        }
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError {
            return true
        }
        if nsError.domain == NSOSStatusErrorDomain && nsError.code == -128 {
            return true
        }
        return false
    }
}
