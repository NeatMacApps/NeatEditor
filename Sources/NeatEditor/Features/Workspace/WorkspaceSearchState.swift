import Foundation

struct WorkspaceSearchState: Equatable {
    enum NavigationDirection: Equatable, Sendable {
        case next
        case previous
    }

    enum Status: Equatable, Sendable {
        case idle
        case matches(current: Int, total: Int)
        case invalidRegularExpression
        case timedOut
    }

    var isPresented = false
    var query = "" {
        didSet {
            // A new pattern supersedes the previous result, including a
            // reported regex error or timeout.
            if query != oldValue {
                if query.isEmpty {
                    status = .idle
                } else if status == .timedOut || status == .invalidRegularExpression {
                    status = .idle
                }
            }
        }
    }
    var isRegexEnabled = false
    var isCaseSensitive = false
    var navigationDirection: NavigationDirection = .next
    var requestID = 0
    var focusRequestID = 0
    /// Status reported by the active editor for the current query.
    private(set) var status: Status = .idle

    var isRegexSearchTimedOut: Bool {
        status == .timedOut
    }

    var hasQuery: Bool {
        !query.isEmpty
    }

    var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canSubmit: Bool {
        hasQuery
    }

    var hasMatches: Bool {
        if case .matches(_, let total) = status {
            return total > 0
        }
        return false
    }

    mutating func updateStatus(_ newStatus: Status) {
        guard status != newStatus else { return }
        status = newStatus
    }

    mutating func markRegexSearchTimedOut(_ isTimedOut: Bool) {
        if isTimedOut {
            updateStatus(.timedOut)
        } else if status == .timedOut {
            status = .idle
        }
    }

    mutating func present(seedQuery: String? = nil) {
        isPresented = true
        if let seedQuery, !seedQuery.isEmpty {
            query = seedQuery
        }
        focusRequestID += 1
    }

    mutating func dismiss() {
        isPresented = false
        status = .idle
    }

    mutating func toggleRegex() {
        isRegexEnabled.toggle()
        if status == .timedOut || status == .invalidRegularExpression {
            status = .idle
        }
    }

    mutating func toggleCaseSensitive() {
        isCaseSensitive.toggle()
        if status == .timedOut || status == .invalidRegularExpression {
            status = .idle
        }
    }

    mutating func navigateNext() {
        guard hasQuery else {
            present()
            return
        }
        navigationDirection = .next
        isPresented = true
        requestID += 1
    }

    mutating func navigatePrevious() {
        guard hasQuery else {
            present()
            return
        }
        navigationDirection = .previous
        isPresented = true
        requestID += 1
    }

    mutating func submit() {
        navigateNext()
    }
}
