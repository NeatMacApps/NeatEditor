import Foundation

struct WorkspaceSearchState: Equatable {
    var isPresented = false
    var query = "" {
        didSet {
            // A new pattern supersedes the previous result, including a
            // reported regex timeout.
            if query != oldValue {
                markRegexSearchTimedOut(false)
            }
        }
    }
    var isRegexEnabled = false
    var requestID = 0
    var focusRequestID = 0
    /// Set when the current regular-expression evaluation exceeded the
    /// editor's deadline; the search bar shows a short status for it.
    private(set) var isRegexSearchTimedOut = false

    mutating func markRegexSearchTimedOut(_ isTimedOut: Bool) {
        guard isRegexSearchTimedOut != isTimedOut else { return }
        isRegexSearchTimedOut = isTimedOut
    }

    var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canSubmit: Bool {
        !trimmedQuery.isEmpty
    }

    mutating func present() {
        isPresented = true
        focusRequestID += 1
    }

    mutating func dismiss() {
        isPresented = false
        markRegexSearchTimedOut(false)
    }

    mutating func toggleRegex() {
        isRegexEnabled.toggle()
        markRegexSearchTimedOut(false)
        guard normalizeQueryIfNeeded() else {
            return
        }

        isPresented = true
        requestID += 1
    }

    mutating func submit() {
        guard normalizeQueryIfNeeded() else {
            present()
            return
        }

        isPresented = true
        requestID += 1
    }

    @discardableResult
    private mutating func normalizeQueryIfNeeded() -> Bool {
        let trimmedQuery = trimmedQuery
        guard !trimmedQuery.isEmpty else {
            return false
        }

        if query != trimmedQuery {
            query = trimmedQuery
        }

        return true
    }
}
