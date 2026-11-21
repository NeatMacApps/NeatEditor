import Foundation

extension WorkspaceStore {
    // MARK: - Search

    func presentSearchBar() {
        guard selectedTabID != nil, !isSettingsSelected else {
            return
        }
        let seed = editorSelectedSearchSeed?()
        searchState.present(seedQuery: seed)
    }

    func dismissSearchBar(restoreEditorFocus: Bool = true) {
        searchState.dismiss()
        if restoreEditorFocus {
            focusEditor?()
        }
    }

    func toggleRegexSearch() {
        searchState.toggleRegex()
    }

    func toggleCaseSensitiveSearch() {
        searchState.toggleCaseSensitive()
    }

    func findNextMatch() {
        guard selectedTabID != nil, !isSettingsSelected else {
            return
        }
        searchState.navigateNext()
    }

    func findPreviousMatch() {
        guard selectedTabID != nil, !isSettingsSelected else {
            return
        }
        searchState.navigatePrevious()
    }

    func submitSearch() {
        findNextMatch()
    }

    func updateSearchStatus(_ status: WorkspaceSearchState.Status) {
        searchState.updateStatus(status)
    }
}
