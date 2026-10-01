import Foundation

@MainActor
final class AutoSaveScheduler {
    private let delay: Duration
    private var tasks: [UUID: Task<Void, Never>] = [:]
    /// Monotonic generation per id so a stale (cancelled or already
    /// superseded) task can never clear or shadow its replacement's handle.
    /// `Task` itself is not identity-comparable, hence the explicit version.
    private var generations: [UUID: UInt64] = [:]

    init(delay: Duration = .seconds(2)) {
        self.delay = delay
    }

    deinit {
        for task in tasks.values {
            task.cancel()
        }
    }

    func cancel(for id: UUID) {
        generations[id, default: 0] &+= 1
        tasks[id]?.cancel()
        tasks[id] = nil
    }

    func schedule(for id: UUID, operation: @escaping @MainActor () -> Void) {
        tasks[id]?.cancel()
        generations[id, default: 0] &+= 1
        let generation = generations[id, default: 0]

        // Weak capture: a pending task must not keep the scheduler (and
        // through it the store) alive, and the scheduler must stay
        // deallocatable while tasks are in flight.
        tasks[id] = Task { @MainActor [weak self, delay] in
            do {
                try await Task.sleep(for: delay)
                guard let self, !Task.isCancelled else {
                    return
                }
                guard self.generations[id, default: 0] == generation else {
                    return
                }

                operation()
            } catch {
                // Task.sleep throws CancellationError when the predecessor was
                // superseded or explicitly cancelled; that is the expected
                // path, not a failure.
            }

            // Only the still-current generation may clear the handle: a
            // cancelled predecessor must not drop its replacement, and an
            // operation that reentrantly rescheduled must keep the new task
            // cancellable.
            guard let self, self.generations[id, default: 0] == generation else {
                return
            }
            self.tasks[id] = nil
            self.generations[id] = nil
        }
    }
}
