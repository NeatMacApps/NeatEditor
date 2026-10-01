import Foundation
import Testing

@testable import NeatEditor

/// Scheduler regression tests: replacing or cancelling a pending autosave
/// must never drop the replacement's cancellation handle, and pending tasks
/// must not retain the scheduler.
@MainActor
struct AutoSaveSchedulerTests {
    @Test("cancelling before the delay prevents the operation")
    func cancelPreventsFiring() async throws {
        let scheduler = AutoSaveScheduler(delay: .milliseconds(100))
        let id = UUID()
        var fired = 0

        scheduler.schedule(for: id) { fired += 1 }
        scheduler.cancel(for: id)

        try await Task.sleep(for: .milliseconds(300))
        #expect(fired == 0)
    }

    @Test("a scheduled operation fires exactly once")
    func firesExactlyOnce() async throws {
        let scheduler = AutoSaveScheduler(delay: .milliseconds(50))
        let id = UUID()
        var fired = 0

        scheduler.schedule(for: id) { fired += 1 }
        try await Task.sleep(for: .milliseconds(250))
        #expect(fired == 1)

        scheduler.schedule(for: id) { fired += 1 }
        try await Task.sleep(for: .milliseconds(250))
        #expect(fired == 2)
    }

    @Test("replacing then cancelling prevents the replacement from firing")
    func replacementCancelPreventsFiring() async throws {
        let scheduler = AutoSaveScheduler(delay: .milliseconds(200))
        let id = UUID()
        var first = 0
        var second = 0

        scheduler.schedule(for: id) { first += 1 }
        scheduler.schedule(for: id) { second += 1 }
        scheduler.cancel(for: id)

        try await Task.sleep(for: .milliseconds(500))
        #expect(first == 0)
        #expect(second == 0)
    }

    @Test("reentrant reschedule keeps a cancellable handle")
    func reentrantRescheduleStaysCancellable() async throws {
        let scheduler = AutoSaveScheduler(delay: .milliseconds(150))
        let id = UUID()
        var firstFired = false
        var second = 0

        scheduler.schedule(for: id) {
            firstFired = true
            scheduler.schedule(for: id) { second += 1 }
        }

        var waited = 0
        while !firstFired, waited < 100 {
            try await Task.sleep(for: .milliseconds(20))
            waited += 1
        }
        #expect(firstFired)

        scheduler.cancel(for: id)
        try await Task.sleep(for: .milliseconds(400))
        #expect(second == 0)
    }

    @Test("pending tasks do not retain the scheduler")
    func pendingTaskDoesNotRetainScheduler() throws {
        var scheduler: AutoSaveScheduler? = AutoSaveScheduler(delay: .seconds(10))
        weak var weakScheduler = scheduler

        scheduler?.schedule(for: UUID()) {}
        scheduler = nil

        #expect(weakScheduler == nil)
    }
}
