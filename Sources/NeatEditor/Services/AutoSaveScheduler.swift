import Foundation

@MainActor
final class AutoSaveScheduler {
    /// One pending entry per id. The token is a fresh UUID per schedule and
    /// is never reused, so a stale task finishing late can be told apart from
    /// its replacement (no ABA on reused counters) and cancellation drops all
    /// bookkeeping for the id.
    private struct Pending {
        let token: UUID
        let task: Task<Void, Never>
    }

    private let delay: Duration
    private var pendings: [UUID: Pending] = [:]

    init(delay: Duration = .seconds(2)) {
        self.delay = delay
    }

    deinit {
        for pending in pendings.values {
            pending.task.cancel()
        }
    }

    func cancel(for id: UUID) {
        guard let pending = pendings.removeValue(forKey: id) else {
            return
        }
        pending.task.cancel()
    }

    func schedule(for id: UUID, operation: @escaping @MainActor () -> Void) {
        pendings[id]?.task.cancel()
        let token = UUID()

        // Weak capture: a pending task must not keep the scheduler (and
        // through it the store) alive, and the scheduler must stay
        // deallocatable while tasks are in flight.
        let task = Task { @MainActor [weak self, delay] in
            do {
                try await Task.sleep(for: delay)
                guard let self, !Task.isCancelled else {
                    return
                }
                // Only the still-current token may fire.
                guard self.pendings[id]?.token == token else {
                    return
                }

                operation()
            } catch {
                // Task.sleep throws CancellationError when the predecessor was
                // superseded or explicitly cancelled; that is the expected
                // path, not a failure.
            }

            // Only the still-current token may clear the entry: a cancelled
            // predecessor finishing after its replacement was scheduled must
            // not drop the replacement, and an operation that reentrantly
            // rescheduled must keep the new entry cancellable.
            guard let self, self.pendings[id]?.token == token else {
                return
            }
            self.pendings.removeValue(forKey: id)
        }
        pendings[id] = Pending(token: token, task: task)
    }
}
