import AppKit
import Testing

@testable import NeatEditor

/// Regular-expression search must never block the main actor: a pathological
/// pattern (`(a+)+$`) can run for minutes inside the engine, so evaluation is
/// off-main, single-flight and bounded by a deadline.
@MainActor
struct EditorRegexSearchTests {
    @Test("a fast evaluator applies its ranges")
    func fastEvaluatorAppliesRanges() async {
        let container = EditorTextContainerView()
        container.textView.string = "alpha beta"
        let recorder = SearchStatusRecorder()
        container.onSearchTimeoutChange = { recorder.record($0) }
        container.searchEvaluator = { _, _ in
            [NSRange(location: 6, length: 4)]
        }

        container.performSearch(for: "b.*a", usesRegularExpression: true, navigate: false)
        await recorder.waitForStatus()

        #expect(recorder.statuses == [false])
        #expect(hasHighlight(container, at: NSRange(location: 6, length: 4)))
        #expect(!hasHighlight(container, at: NSRange(location: 0, length: 5)))
    }

    @Test("a slow evaluator times out without applying or blocking")
    func slowEvaluatorTimesOut() async {
        let container = EditorTextContainerView()
        container.textView.string = "alpha beta"
        let recorder = SearchStatusRecorder()
        let gate = SearchEvaluatorGate()
        container.onSearchTimeoutChange = { recorder.record($0) }
        container.searchEvaluator = { _, _ in
            await gate.wait()
            return [NSRange(location: 0, length: 5)]
        }

        container.performSearch(for: "(a+)+$", usesRegularExpression: true, navigate: false)
        await recorder.waitForStatus()

        #expect(recorder.statuses == [true])
        #expect(!hasHighlight(container, at: NSRange(location: 0, length: 5)))

        // Release the abandoned evaluation: its result arrives after the
        // deadline and must stay discarded, without a second status.
        await gate.release()
        #expect(recorder.statuses == [true])
        #expect(!hasHighlight(container, at: NSRange(location: 0, length: 5)))
    }

    @Test("a newer request wins over an older one")
    func newerRequestWins() async {
        let container = EditorTextContainerView()
        container.textView.string = "alpha beta"
        let recorder = SearchStatusRecorder()
        let firstGate = SearchEvaluatorGate()
        container.onSearchTimeoutChange = { recorder.record($0) }
        container.searchEvaluator = { _, _ in
            await firstGate.wait()
            return [NSRange(location: 0, length: 5)]
        }
        container.performSearch(for: "alpha", usesRegularExpression: true, navigate: false)

        container.searchEvaluator = { _, _ in
            [NSRange(location: 6, length: 4)]
        }
        container.performSearch(for: "beta", usesRegularExpression: true, navigate: false)
        await recorder.waitForStatus()

        #expect(recorder.statuses == [false])
        #expect(hasHighlight(container, at: NSRange(location: 6, length: 4)))

        // The superseded evaluation returns "alpha" ranges; identity discards
        // them even though the engine finished normally.
        await firstGate.release()
        #expect(hasHighlight(container, at: NSRange(location: 6, length: 4)))
        #expect(!hasHighlight(container, at: NSRange(location: 0, length: 5)))
    }

    @Test("literal search bypasses the background evaluator")
    func literalSearchStaysSynchronous() {
        let container = EditorTextContainerView()
        container.textView.string = "alpha beta"
        container.searchEvaluator = { _, _ in
            Issue.record("literal search must not use the regex evaluator")
            return []
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
        container.searchEvaluator = { _, _ in
            (0..<3000).map { NSRange(location: $0, length: 1) }
        }

        container.performSearch(for: "a", usesRegularExpression: true, navigate: false)
        await recorder.waitForStatus()

        #expect(highlightedLocationsAbove(2001, in: container) == 0)
        #expect(hasHighlight(container, at: NSRange(location: 1999, length: 1)))
    }

    private func hasHighlight(_ container: EditorTextContainerView, at range: NSRange) -> Bool {
        guard let storage = container.textView.textStorage,
              range.length > 0,
              NSMaxRange(range) <= storage.length else {
            return false
        }
        for offset in range.location..<NSMaxRange(range) {
            if storage.attribute(.backgroundColor, at: offset, effectiveRange: nil) == nil {
                return false
            }
        }
        return true
    }

    private func highlightedLocationsAbove(
        _ limit: Int,
        in container: EditorTextContainerView
    ) -> Int {
        guard let storage = container.textView.textStorage else { return 0 }
        var count = 0
        for offset in limit..<storage.length
        where storage.attribute(.backgroundColor, at: offset, effectiveRange: nil) != nil {
            count += 1
        }
        return count
    }
}

@MainActor
private final class SearchStatusRecorder {
    private(set) var statuses: [Bool] = []
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func record(_ isTimedOut: Bool) {
        statuses.append(isTimedOut)
        let resumed = waiters
        waiters = []
        for waiter in resumed {
            waiter.resume()
        }
    }

    func waitForStatus(timeout: Duration = .seconds(5)) async {
        guard statuses.isEmpty else { return }
        // A regression that stops publishing must fail the test, not hang it.
        let timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            self?.resumeWaiters()
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
        timeoutTask.cancel()
    }

    private func resumeWaiters() {
        let resumed = waiters
        waiters = []
        for waiter in resumed {
            waiter.resume()
        }
    }
}

private actor SearchEvaluatorGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isReleased = false

    func wait() async {
        guard !isReleased else { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func release() {
        guard !isReleased else { return }
        isReleased = true
        continuation?.resume()
        continuation = nil
    }
}
