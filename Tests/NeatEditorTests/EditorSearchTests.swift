import AppKit
import SwiftUI
import Testing

@testable import NeatEditor

@MainActor
struct EditorSearchTests {
    @Test("WorkspaceSearchState handles present, seed, toggles, navigation, and status transitions")
    func searchStateTransitions() {
        var state = WorkspaceSearchState()
        #expect(!state.isPresented)
        #expect(state.status == .idle)
        #expect(!state.hasQuery)
        #expect(!state.hasMatches)

        state.present(seedQuery: "hello")
        #expect(state.isPresented)
        #expect(state.query == "hello")
        #expect(state.focusRequestID == 1)
        #expect(state.hasQuery)

        state.updateStatus(.matches(current: 2, total: 5))
        #expect(state.hasMatches)

        state.navigateNext()
        #expect(state.navigationDirection == .next)
        #expect(state.requestID == 1)

        state.navigatePrevious()
        #expect(state.navigationDirection == .previous)
        #expect(state.requestID == 2)

        state.toggleCaseSensitive()
        #expect(state.isCaseSensitive)

        state.toggleRegex()
        #expect(state.isRegexEnabled)

        state.markRegexSearchTimedOut(true)
        #expect(state.isRegexSearchTimedOut)
        #expect(state.status == .timedOut)

        // Changing query clears timeout/invalid error and empty query resets to idle.
        state.query = "world"
        #expect(state.status == .idle)
        state.updateStatus(.invalidRegularExpression)
        state.toggleRegex()
        #expect(state.status == .idle)

        state.updateStatus(.matches(current: 1, total: 3))
        state.query = ""
        #expect(state.status == .idle)

        state.dismiss()
        #expect(!state.isPresented)
        #expect(state.status == .idle)
    }

    @Test("WorkspaceStore disables search on Settings tab, seeds selection, and restores editor focus on dismiss")
    func workspaceStoreSearchLifecycle() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NeatEditorSearchTests-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let suite = "NeatEditorSearchTests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = WorkspaceStore(
            persistenceService: DocumentPersistenceService(defaultDirectory: directory),
            userDefaults: defaults
        )
        defer {
            store.pendingSaveStateTask?.cancel()
            store.pendingAdaptiveFontTask?.cancel()
            store.pendingDefaultAppTask?.cancel()
        }

        var didFocusEditor = false
        store.editorSelectedSearchSeed = { "selected" }
        store.focusEditor = { didFocusEditor = true }

        store.openSettings()
        #expect(store.isSettingsSelected)
        store.presentSearchBar()
        #expect(!store.searchState.isPresented)

        store.createNewDocument()
        #expect(!store.isSettingsSelected)
        store.presentSearchBar()
        #expect(store.searchState.isPresented)
        #expect(store.searchState.query == "selected")

        store.dismissSearchBar(restoreEditorFocus: true)
        #expect(!store.searchState.isPresented)
        #expect(didFocusEditor)
    }

    @Test("literal and regex search respect case sensitivity")
    func caseSensitivity() async {
        let container = EditorTextContainerView()
        container.textView.string = "Alpha alpha ALPHA"

        var statuses: [WorkspaceSearchState.Status] = []
        container.onSearchStatusChange = { statuses.append($0) }

        container.performSearch(
            for: "alpha",
            usesRegularExpression: false,
            isCaseSensitive: false,
            navigation: .nearest
        )
        #expect(statuses.last == .matches(current: 1, total: 3))

        container.performSearch(
            for: "alpha",
            usesRegularExpression: false,
            isCaseSensitive: true,
            navigation: .nearest
        )
        #expect(statuses.last == .matches(current: 1, total: 1))
        #expect(container.textView.selectedRange() == NSRange(location: 6, length: 5))

        container.performSearch(
            for: "ALPHA",
            usesRegularExpression: true,
            isCaseSensitive: true,
            navigation: .nearest
        )
        // Wait briefly for off-main regex evaluation.
        for _ in 0..<100 where container.retainedRegularExpressionRequestCount > 0 {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(statuses.last == .matches(current: 1, total: 1))
        #expect(container.textView.selectedRange() == NSRange(location: 12, length: 5))
    }

    @Test("next and previous navigation wraps cleanly without stealing window first responder")
    func navigationWrapAndResponderPreservation() throws {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }

        let container = EditorTextContainerView()
        container.frame = CGRect(x: 0, y: 0, width: 480, height: 280)
        let searchField = NSTextField(frame: CGRect(x: 0, y: 280, width: 200, height: 24))
        let root = NSView(frame: CGRect(x: 0, y: 0, width: 480, height: 320))
        root.addSubview(container)
        root.addSubview(searchField)
        window.contentView = root
        window.makeFirstResponder(searchField)

        container.textView.string = "one two one three one"
        var latestStatus: WorkspaceSearchState.Status = .idle
        container.onSearchStatusChange = { latestStatus = $0 }

        container.performSearch(for: "one", usesRegularExpression: false, isCaseSensitive: false, navigation: .nearest)
        #expect(latestStatus == .matches(current: 1, total: 3))
        #expect(container.textView.selectedRange() == NSRange(location: 0, length: 3))
        #expect(window.firstResponder !== container.textView)

        container.performSearch(for: "one", usesRegularExpression: false, isCaseSensitive: false, navigation: .next)
        #expect(latestStatus == .matches(current: 2, total: 3))
        #expect(container.textView.selectedRange() == NSRange(location: 8, length: 3))

        container.performSearch(for: "one", usesRegularExpression: false, isCaseSensitive: false, navigation: .next)
        #expect(latestStatus == .matches(current: 3, total: 3))
        #expect(container.textView.selectedRange() == NSRange(location: 18, length: 3))

        // Wrap forward to first match.
        container.performSearch(for: "one", usesRegularExpression: false, isCaseSensitive: false, navigation: .next)
        #expect(latestStatus == .matches(current: 1, total: 3))
        #expect(container.textView.selectedRange() == NSRange(location: 0, length: 3))

        // Wrap backward to last match.
        container.performSearch(for: "one", usesRegularExpression: false, isCaseSensitive: false, navigation: .previous)
        #expect(latestStatus == .matches(current: 3, total: 3))
        #expect(container.textView.selectedRange() == NSRange(location: 18, length: 3))
    }

    @Test("active match highlight is visually stronger than secondary matches")
    func activeVsSecondaryHighlight() throws {
        let container = EditorTextContainerView()
        container.textView.string = "cat dog cat"
        container.performSearch(for: "cat", usesRegularExpression: false, isCaseSensitive: false, navigation: .nearest)

        let storage = try #require(container.textView.textStorage)
        let firstColor = try #require(storage.attribute(.backgroundColor, at: 0, effectiveRange: nil) as? NSColor)
        let secondColor = try #require(storage.attribute(.backgroundColor, at: 8, effectiveRange: nil) as? NSColor)
        #expect(firstColor.alphaComponent > secondColor.alphaComponent)

        container.performSearch(for: "cat", usesRegularExpression: false, isCaseSensitive: false, navigation: .next)
        let afterFirst = try #require(storage.attribute(.backgroundColor, at: 0, effectiveRange: nil) as? NSColor)
        let afterSecond = try #require(storage.attribute(.backgroundColor, at: 8, effectiveRange: nil) as? NSColor)
        #expect(afterSecond.alphaComponent > afterFirst.alphaComponent)
    }

    @Test("invalid regular expression reports invalid status and paints no highlights")
    func invalidRegexReportsStatus() async {
        let container = EditorTextContainerView()
        container.textView.string = "alpha beta"
        var statuses: [WorkspaceSearchState.Status] = []
        var timeoutStatuses: [Bool] = []
        container.onSearchStatusChange = { statuses.append($0) }
        container.onSearchTimeoutChange = { timeoutStatuses.append($0) }

        container.performSearch(for: "(", usesRegularExpression: true, isCaseSensitive: false, navigation: .nearest)
        for _ in 0..<100 where container.retainedRegularExpressionRequestCount > 0 {
            try? await Task.sleep(for: .milliseconds(10))
        }

        #expect(statuses.last == .invalidRegularExpression)
        #expect(timeoutStatuses.last == false)
        #expect(container.lastSearchMatches.isEmpty)
        #expect(container.textView.textStorage?.attribute(.backgroundColor, at: 0, effectiveRange: nil) == nil)
    }

    @Test("reapplying highlights after edit updates count without moving caret")
    func reapplyUpdatesCountWithoutMovingSelection() {
        let container = EditorTextContainerView()
        container.textView.string = "foo bar foo"
        var latestStatus: WorkspaceSearchState.Status = .idle
        container.onSearchStatusChange = { latestStatus = $0 }

        container.textView.setSelectedRange(NSRange(location: 4, length: 0))
        container.reapplySearchHighlightsIfNeeded(
            query: "foo",
            usesRegularExpression: false,
            isCaseSensitive: false,
            isPresented: true
        )

        #expect(latestStatus == .matches(current: 2, total: 2))
        #expect(container.textView.selectedRange() == NSRange(location: 4, length: 0))
    }

    @Test("selectedSearchSeed returns single-line selections and skips multiline or oversized ranges")
    func selectedSearchSeedRules() {
        let container = EditorTextContainerView()
        container.textView.string = "first line\nsecond line\n" + String(repeating: "x", count: 210)

        container.textView.setSelectedRange(NSRange(location: 0, length: 0))
        #expect(container.selectedSearchSeed() == nil)

        container.textView.setSelectedRange(NSRange(location: 0, length: 5))
        #expect(container.selectedSearchSeed() == "first")

        container.textView.setSelectedRange(NSRange(location: 5, length: 8))
        #expect(container.selectedSearchSeed() == nil)

        container.textView.setSelectedRange(NSRange(location: 23, length: 201))
        #expect(container.selectedSearchSeed() == nil)
    }

    @Test("EditorSearchBarView lays out cleanly across states, widths, and appearances",
          arguments: [NSAppearance.Name.aqua, .darkAqua])
    func searchBarLayout(appearanceName: NSAppearance.Name) throws {
        let statuses: [WorkspaceSearchState.Status] = [
            .idle,
            .matches(current: 2, total: 15),
            .matches(current: 0, total: 0),
            .invalidRegularExpression,
            .timedOut,
        ]
        for width in [CGFloat(240), 480] {
            for status in statuses {
                var state = WorkspaceSearchState()
                state.isPresented = true
                state.query = status == .idle ? "" : "pattern"
                state.updateStatus(status)
                let view = EditorSearchBarView(
                    searchState: .constant(state),
                    theme: .warm,
                    onFindNext: {},
                    onFindPrevious: {},
                    onToggleCaseSensitive: {},
                    onToggleRegex: {},
                    onDismiss: {}
                )
                .padding(.horizontal, 12)
                .frame(width: width)

                let host = NSHostingView(rootView: view)
                host.appearance = NSAppearance(named: appearanceName)
                host.frame = CGRect(x: 0, y: 0, width: width, height: 60)
                host.layoutSubtreeIfNeeded()

                let fitting = host.fittingSize
                #expect(fitting.height == 36)
                #expect(fitting.width <= width)
            }
        }
    }
}
