import AppKit
import Testing

@testable import NeatEditor

@MainActor
struct EditorRegexSearchTests {
    @Test("a fast evaluator applies its ranges")
    func fastEvaluatorAppliesRanges() async {
        let container = EditorTextContainerView()
        container.textView.string = "alpha beta"
        let recorder = SearchStatusRecorder()
        container.onSearchTimeoutChange = { recorder.record($0) }
        container.searchEvaluator = { _, _, _ in
            .matches([NSRange(location: 6, length: 4)])
        }

        container.performSearch(for: "b.*a", usesRegularExpression: true, navigate: false)
        await recorder.waitForStatus()

        #expect(recorder.statuses == [false])
        #expect(hasHighlight(container, at: NSRange(location: 6, length: 4)))
        #expect(!hasHighlight(container, at: NSRange(location: 0, length: 5)))
    }

    @Test("a timed-out uncooperative evaluator stays tracked until it ends")
    func slowEvaluatorTimesOut() async {
        let container = EditorTextContainerView()
        container.textView.string = "alpha beta"
        let recorder = SearchStatusRecorder()
        let gate = SearchEvaluatorGate()
        container.onSearchTimeoutChange = { recorder.record($0) }
        container.searchEvaluator = { _, _, _ in
            await gate.wait()
            return .matches([NSRange(location: 0, length: 5)])
        }

        container.performSearch(for: "(a+)+$", usesRegularExpression: true, navigate: false)
        await gate.waitUntilStarted()
        await recorder.waitForStatus()
        #expect(recorder.statuses == [true])
        #expect(container.retainedRegularExpressionRequestCount == 1)
        #expect(!hasHighlight(container, at: NSRange(location: 0, length: 5)))

        container.searchEvaluator = { _, _, _ in
            .matches([NSRange(location: 6, length: 4)])
        }
        container.performSearch(for: "beta", usesRegularExpression: true, navigate: false)
        #expect(container.retainedRegularExpressionRequestCount == 2)
        await gate.release()
        await recorder.waitForStatus(count: 2)

        #expect(recorder.statuses == [true, false])
        #expect(hasHighlight(container, at: NSRange(location: 6, length: 4)))
        #expect(!hasHighlight(container, at: NSRange(location: 0, length: 5)))
        #expect(container.retainedRegularExpressionRequestCount == 0)
    }

    @Test("newer requests replace one pending slot instead of starting more evaluators")
    func newerRequestsAreCoalesced() async {
        let container = EditorTextContainerView()
        container.textView.string = "alpha beta"
        let recorder = SearchStatusRecorder()
        let firstGate = SearchEvaluatorGate()
        let history = SearchEvaluationHistory()
        container.onSearchTimeoutChange = { recorder.record($0) }
        container.searchEvaluator = { pattern, _, _ in
            await history.begin(pattern)
            if pattern == "alpha" { await firstGate.wait() }
            await history.end()
            return .matches([NSRange(location: pattern == "alpha" ? 0 : 6, length: 4)])
        }
        container.performSearch(for: "alpha", usesRegularExpression: true, navigate: false)
        await firstGate.waitUntilStarted()

        for index in 1...50 {
            container.performSearch(for: "new-\(index)", usesRegularExpression: true, navigate: false)
            #expect(container.retainedRegularExpressionRequestCount == 2)
        }
        await firstGate.release()
        await recorder.waitForStatus()

        let snapshot = await history.snapshot()
        #expect(snapshot.patterns == ["alpha", "new-50"])
        #expect(snapshot.peak == 1)
        #expect(snapshot.active == 0)
        #expect(recorder.statuses == [false])
        #expect(hasHighlight(container, at: NSRange(location: 6, length: 4)))
        #expect(!hasHighlight(container, at: NSRange(location: 0, length: 5)))
    }

    @Test("dismissal drops pending work and rejects a late active result")
    func dismissalDiscardsPendingWork() async {
        let container = EditorTextContainerView()
        container.textView.string = "alpha beta"
        let gate = SearchEvaluatorGate()
        let history = SearchEvaluationHistory()
        let recorder = SearchStatusRecorder()
        container.onSearchTimeoutChange = { recorder.record($0) }
        container.searchEvaluator = { pattern, _, _ in
            await history.begin(pattern)
            await gate.wait()
            await history.end()
            return .matches([NSRange(location: 0, length: 5)])
        }
        container.performSearch(for: "alpha", usesRegularExpression: true, navigate: false)
        await gate.waitUntilStarted()
        container.performSearch(for: "beta", usesRegularExpression: true, navigate: false)
        container.clearSearchHighlights()
        #expect(container.retainedRegularExpressionRequestCount == 1)
        await gate.release()
        await waitForIdle(container)

        #expect(await history.snapshot().patterns == ["alpha"])
        #expect(recorder.statuses.isEmpty)
        #expect(!hasHighlight(container, at: NSRange(location: 0, length: 5)))
    }

    @Test("native pathological matching ends on deadline and a valid pattern recovers")
    func nativeDeadlineStopsComputation() async {
        let container = EditorTextContainerView()
        let nativeEvaluator = container.searchEvaluator
        let history = SearchEvaluationHistory()
        let recorder = SearchStatusRecorder()
        container.searchEvaluator = { pattern, text, deadline in
            await history.begin(pattern)
            let outcome = await nativeEvaluator(pattern, text, deadline)
            await history.end()
            return outcome
        }
        container.onSearchTimeoutChange = { recorder.record($0) }
        container.textView.string = String(repeating: "a", count: 64) + "!"

        for count in 1...4 {
            container.performSearch(for: "(a+)+$", usesRegularExpression: true, navigate: false)
            await recorder.waitForStatus(count: count)
            await waitForIdle(container)
            #expect(recorder.statuses == Array(repeating: true, count: count))
        }
        let snapshot = await history.snapshot()
        #expect(snapshot.peak == 1)
        #expect(snapshot.active == 0)
        #expect(snapshot.patterns.count == 4)

        container.textView.string = "alpha beta"
        container.performSearch(for: "b.*a", usesRegularExpression: true, navigate: false)
        await recorder.waitForStatus(count: 5)
        #expect(recorder.statuses.last == false)
        #expect(hasHighlight(container, at: NSRange(location: 6, length: 4)))
    }

    @Test("literal search bypasses the background evaluator")
    func literalSearchStaysSynchronous() {
        let container = EditorTextContainerView()
        container.textView.string = "alpha beta"
        container.searchEvaluator = { _, _, _ in
            Issue.record("literal search must not use the regex evaluator")
            return .matches([])
        }
        container.performSearch(for: "beta", usesRegularExpression: false, navigate: false)
        #expect(hasHighlight(container, at: NSRange(location: 6, length: 4)))
        #expect(!hasHighlight(container, at: NSRange(location: 0, length: 5)))
    }

    @Test("applied highlights are capped at the documented limit")
    func appliedMatchCountIsCapped() async {
        let container = EditorTextContainerView()
        container.textView.string = String(repeating: "a", count: 3000)
        let recorder = SearchStatusRecorder()
        container.onSearchTimeoutChange = { recorder.record($0) }
        container.searchEvaluator = { _, _, _ in
            .matches((0..<3000).map { NSRange(location: $0, length: 1) })
        }
        container.performSearch(for: "a", usesRegularExpression: true, navigate: false)
        await recorder.waitForStatus()
        #expect(highlightedLocationsAbove(2000, in: container) == 0)
        #expect(hasHighlight(container, at: NSRange(location: 1999, length: 1)))
    }

    @Test("Find Next reaches every match beyond the painting budget", arguments: [false, true])
    func navigationBeyondHighlightBudget(_ usesRegex: Bool) async {
        let container = EditorTextContainerView()
        container.textView.string = String(repeating: "a ", count: 3000)
        let recorder = SearchStatusRecorder()
        container.onSearchTimeoutChange = { recorder.record($0) }
        container.textView.setSelectedRange(NSRange(location: 3998, length: 1))
        container.performSearch(for: "a", usesRegularExpression: usesRegex)
        if usesRegex { await recorder.waitForStatus() }
        #expect(container.textView.selectedRange() == NSRange(location: 4000, length: 1))
        #expect(highlightedLocationsAbove(4000, in: container) == 0)

        container.textView.setSelectedRange(NSRange(location: 5998, length: 1))
        container.performSearch(for: "a", usesRegularExpression: usesRegex)
        if usesRegex { await recorder.waitForStatus(count: 2) }
        #expect(container.textView.selectedRange() == NSRange(location: 0, length: 1))
    }

    @Test("native matching keeps case folding, Unicode ranges, groups and invalid-pattern handling", arguments: [
        ("beta", "中🙂 BETA beta", [NSRange(location: 4, length: 4), NSRange(location: 9, length: 4)]),
        ("(foo|bar)\\d+", "foo12 bar3", [NSRange(location: 0, length: 5), NSRange(location: 6, length: 4)]),
        ("(?m)^b.*", "alpha\nbeta", [NSRange(location: 6, length: 4)]),
        ("(", "alpha beta", []),
    ])
    func nativeMatchingCases(_ testCase: (String, String, [NSRange])) async {
        let container = EditorTextContainerView()
        container.textView.string = testCase.1
        let recorder = SearchStatusRecorder()
        container.onSearchTimeoutChange = { recorder.record($0) }
        container.performSearch(for: testCase.0, usesRegularExpression: true, navigate: false)
        await recorder.waitForStatus()
        #expect(recorder.statuses == [false])
        for offset in 0..<testCase.1.utf16.count {
            let expected = testCase.2.contains { NSLocationInRange(offset, $0) }
            #expect(hasHighlight(container, at: NSRange(location: offset, length: 1)) == expected)
        }
    }

    private func waitForIdle(_ container: EditorTextContainerView) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while container.retainedRegularExpressionRequestCount > 0, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(container.retainedRegularExpressionRequestCount == 0)
    }

    private func hasHighlight(_ container: EditorTextContainerView, at range: NSRange) -> Bool {
        guard let storage = container.textView.textStorage,
              range.length > 0, NSMaxRange(range) <= storage.length else { return false }
        return (range.location..<NSMaxRange(range)).allSatisfy {
            storage.attribute(.backgroundColor, at: $0, effectiveRange: nil) != nil
        }
    }

    private func highlightedLocationsAbove(_ limit: Int, in container: EditorTextContainerView) -> Int {
        guard let storage = container.textView.textStorage else { return 0 }
        return (limit..<storage.length).filter {
            storage.attribute(.backgroundColor, at: $0, effectiveRange: nil) != nil
        }.count
    }
}

@MainActor
private final class SearchStatusRecorder {
    private(set) var statuses: [Bool] = []
    private var waiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func record(_ isTimedOut: Bool) {
        statuses.append(isTimedOut)
        let ready = waiters.filter { $0.count <= statuses.count }
        waiters.removeAll { $0.count <= statuses.count }
        for waiter in ready { waiter.continuation.resume() }
    }

    func waitForStatus(count: Int = 1, timeout: Duration = .seconds(5)) async {
        guard statuses.count < count else { return }
        let timeoutTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: timeout) } catch { return }
            guard let self else { return }
            let pending = self.waiters
            self.waiters = []
            for waiter in pending { waiter.continuation.resume() }
        }
        await withCheckedContinuation { waiters.append((count, $0)) }
        timeoutTask.cancel()
    }
}

private actor SearchEvaluatorGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var hasStarted = false
    private var isReleased = false

    func wait() async {
        hasStarted = true
        let started = startWaiters
        startWaiters = []
        for waiter in started { waiter.resume() }
        guard !isReleased else { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilStarted() async {
        guard !hasStarted else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func release() {
        isReleased = true
        continuation?.resume()
        continuation = nil
    }
}

private actor SearchEvaluationHistory {
    private var patterns: [String] = []
    private var active = 0
    private var peak = 0

    func begin(_ pattern: String) {
        patterns.append(pattern)
        active += 1
        peak = max(peak, active)
    }

    func end() { active -= 1 }

    func snapshot() -> (patterns: [String], active: Int, peak: Int) {
        (patterns, active, peak)
    }
}
