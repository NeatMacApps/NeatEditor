import Foundation

extension WorkspaceStore {
    // MARK: - Preferences

    private enum EditorFontStep {
        static let value: CGFloat = 1
    }

    func increaseEditorFontSize() {
        updateEditorFontSize(by: EditorFontStep.value)
    }

    func decreaseEditorFontSize() {
        updateEditorFontSize(by: -EditorFontStep.value)
    }

    func updateEditorFontSize(by delta: CGFloat) {
        guard preferences.stepEditorFontSize(
            by: delta,
            rememberingFor: selectedEditorFontFileURL()
        ) else {
            return
        }
        scheduleAdaptiveFontSample(preferences.editorFontSize)
    }

    // MARK: - Adaptive font size

    private func scheduleAdaptiveFontSample(_ fontSize: CGFloat) {
        pendingAdaptiveFontSample = fontSize
        pendingAdaptiveFontTask?.cancel()
        pendingAdaptiveFontTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: self.adaptiveFontSampleDelay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self.settlePendingAdaptiveFontSample()
        }
    }

    /// Commits the pending sample synchronously and clears the bookkeeping.
    /// Mutating preferences here schedules a debounced save; callers that are
    /// themselves flushing state cancel that task before their final write.
    func settlePendingAdaptiveFontSample() {
        guard let sample = pendingAdaptiveFontSample else { return }
        pendingAdaptiveFontSample = nil
        pendingAdaptiveFontTask?.cancel()
        pendingAdaptiveFontTask = nil
        preferences.learnAdaptiveEditorFontSize(sample)
    }

    func handlePreferencesChange(
        from oldPreferences: WorkspacePreferences,
        to newPreferences: WorkspacePreferences
    ) {
        guard !isRestoringState else {
            return
        }

        if oldPreferences.appLanguage != newPreferences.appLanguage {
            updateAppleLanguages(for: newPreferences.appLanguage)
        }

        saveState()
    }

    func updateAppleLanguages(for appLanguage: AppLanguage) {
        // Only update if it actually differs from what's currently in UserDefaults
        // to avoid triggering "restart required" continuously.
        if appLanguage == .system {
            if userDefaults.object(forKey: UserDefaultsKey.appleLanguages) != nil {
                userDefaults.removeObject(forKey: UserDefaultsKey.appleLanguages)
                isLanguageChangePendingRestart = true
            }
        } else {
            let currentLanguages = userDefaults.stringArray(
                forKey: UserDefaultsKey.appleLanguages
            )
            if currentLanguages?.first != appLanguage.rawValue {
                userDefaults.set(
                    [appLanguage.rawValue],
                    forKey: UserDefaultsKey.appleLanguages
                )
                isLanguageChangePendingRestart = true
            }
        }
    }

    func selectedEditorFontFileURL() -> URL? {
        guard let selectedTabID,
              let tab = tabs.first(where: { $0.id == selectedTabID }),
              !tab.isSettings else {
            return nil
        }

        return normalizedEditorFontFileURL(for: tab.fileURL)
    }

    func normalizedEditorFontFileURL(for fileURL: URL?) -> URL? {
        guard let fileURL else {
            return nil
        }

        return persistenceService.normalizedFileURL(for: fileURL)
    }

    func applyEditorFontPreferenceForSelectedTab() {
        guard let selectedTabID,
              let tab = tabs.first(where: { $0.id == selectedTabID }),
              !tab.isSettings else {
            return
        }

        preferences.applyRememberedEditorFontSize(
            for: normalizedEditorFontFileURL(for: tab.fileURL)
        )
    }
}
