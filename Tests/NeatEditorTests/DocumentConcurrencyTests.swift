import Foundation
import Synchronization
import Testing

@testable import NeatEditor

struct DocumentConcurrencyTests: Sendable {
    private func fixture() throws -> (DocumentPersistenceService, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("NeatEditorConcurrency-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (DocumentPersistenceService(defaultDirectory: root,
            recoveryDirectory: root.appendingPathComponent("recovery")), root)
    }

    private func opened(_ service: DocumentPersistenceService, root: URL, content: String) throws -> EditorTab {
        let url = root.appendingPathComponent("shared.txt")
        try content.write(to: url, atomically: true, encoding: .utf8)
        return try service.openDocument(at: url)
    }

    private func hasSignal(_ semaphore: DispatchSemaphore) -> Bool {
        semaphore.wait(timeout: .now()) == .success
    }

    private func waitForSignal(
        _ semaphore: DispatchSemaphore, timeout: Duration = .seconds(5)
    ) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if hasSignal(semaphore) { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    private struct TimeoutError: Error {}

    private struct ControlledFailure: Error {}

    private struct DeadlineState<T: Sendable>: Sendable {
        var completed = false
        var cancelRequested = false
        var continuation: CheckedContinuation<T, Error>?
        var worker: Task<Void, Never>?
        var timer: Task<Void, Never>?
    }

    /// Checked gate for the deadline race. A single `Mutex` guards all state so
    /// child registration races against completion atomically: a child stored
    /// after a winner is cancelled immediately instead of leaking a full-timeout
    /// timer, and a win clears stored handles. Heap-allocated so unstructured
    /// workers can safely outlive the helper's return.
    private final class DeadlineGate<T: Sendable>: Sendable {
        private let state: Mutex<DeadlineState<T>>

        init() {
            state = Mutex(DeadlineState())
        }

        func setContinuation(_ value: CheckedContinuation<T, Error>) {
            state.withLock { $0.continuation = value }
        }

        func markCancelRequested() {
            state.withLock { $0.cancelRequested = true }
        }

        func hasContinuation() -> Bool {
            state.withLock { $0.continuation != nil }
        }

        func isCancelRequested() -> Bool {
            state.withLock { $0.cancelRequested }
        }

        /// Stores `task` unless a winner already claimed completion, in which
        /// case the late child is cancelled immediately. Returns whether a
        /// winner had already completed.
        @discardableResult
        func registerWorker(_ task: Task<Void, Never>) -> Bool {
            let already: Bool = state.withLock {
                if $0.completed { return true }
                $0.worker = task
                return false
            }
            if already { task.cancel() }
            return already
        }

        @discardableResult
        func registerTimer(_ task: Task<Void, Never>) -> Bool {
            let already: Bool = state.withLock {
                if $0.completed { return true }
                $0.timer = task
                return false
            }
            if already { task.cancel() }
            return already
        }

        /// Atomically claim the single win and clear stored handles. Only the
        /// first caller receives a non-nil continuation; losers receive nil and
        /// must do nothing.
        func claimWin() -> (CheckedContinuation<T, Error>?, Task<Void, Never>?, Task<Void, Never>?) {
            state.withLock {
                if $0.completed { return (nil, nil, nil) }
                $0.completed = true
                let cont = $0.continuation
                $0.continuation = nil
                let currentWorker = $0.worker
                $0.worker = nil
                let currentTimer = $0.timer
                $0.timer = nil
                return (cont, currentWorker, currentTimer)
            }
        }
    }

    /// Bounds a result that depends on file coordination so a claim that is
    /// never released fails the case instead of hanging the suite.
    ///
    /// A throwing task group cannot bound a non-cooperative wait: exiting the
    /// group joins every child, so `cancelAll` still waits for the child
    /// blocked in `task.value` (`Task.cancel()` is cooperative and awaiting
    /// `Task.value` does not unblock on cancel). This helper therefore races
    /// the underlying value against the deadline with unstructured workers and
    /// a single exactly-once continuation. The caller resumes as soon as the
    /// first branch wins; the loser is cancelled best-effort and never joined.
    private func boundedValue<T: Sendable>(
        of task: Task<T, Error>, timeout: Duration = .seconds(20)
    ) async throws -> T {
        let gate = DeadlineGate<T>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
                gate.setContinuation(continuation)
                let worker = Task.detached {
                    do {
                        let value = try await task.value
                        let (cont, _, timer) = gate.claimWin()
                        guard let cont else { return }
                        timer?.cancel()
                        cont.resume(returning: value)
                    } catch {
                        let (cont, _, timer) = gate.claimWin()
                        guard let cont else { return }
                        timer?.cancel()
                        cont.resume(throwing: error)
                    }
                }
                gate.registerWorker(worker)
                let timer = Task.detached {
                    do {
                        try await Task.sleep(for: timeout)
                    } catch {
                        return
                    }
                    let (cont, workerToCancel, _) = gate.claimWin()
                    guard let cont else { return }
                    task.cancel()
                    workerToCancel?.cancel()
                    cont.resume(throwing: TimeoutError())
                }
                gate.registerTimer(timer)
                if Task.isCancelled || gate.isCancelRequested() {
                    let (cont, workerToCancel, timerToCancel) = gate.claimWin()
                    guard let cont else { return }
                    workerToCancel?.cancel()
                    timerToCancel?.cancel()
                    task.cancel()
                    cont.resume(throwing: CancellationError())
                }
            }
        } onCancel: {
            gate.markCancelRequested()
            guard gate.hasContinuation() else { return }
            let (cont, workerToCancel, timerToCancel) = gate.claimWin()
            guard let cont else { return }
            workerToCancel?.cancel()
            timerToCancel?.cancel()
            task.cancel()
            cont.resume(throwing: CancellationError())
        }
    }

    @Test("stable observation ignores sibling writes but catches replacement re-arm races and direct writes")
    func stableObservationTracksOnlyItsFile() async throws {
        let (service, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let tab = try opened(service, root: root, content: "aaaa")
        let url = try #require(tab.fileURL)
        let sibling = root.appendingPathComponent("sibling.txt")
        try "sibling".write(to: sibling, atomically: true, encoding: .utf8)
        let changes = Mutex(0)
        let observer = DocumentFileObserver(url: url) { _ in changes.withLock { $0 += 1 } }
        defer { observer.stop() }
        try "unrelated".write(to: sibling, atomically: true, encoding: .utf8)
        try await Task.sleep(for: .milliseconds(200))
        #expect(changes.withLock { $0 } == 0)

        let stamp = try #require(url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        try "cccc".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: stamp], ofItemAtPath: url.path)
        observer.refreshFileObservation()
        #expect(changes.withLock { $0 } > 0)
        try await Task.sleep(for: .milliseconds(200))
        changes.withLock { $0 = 0 }
        try "dddd".write(to: url, atomically: false, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: stamp], ofItemAtPath: url.path)
        for _ in 0..<100 where changes.withLock({ $0 }) == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(changes.withLock { $0 } > 0)
        #expect(try String(contentsOf: url, encoding: .utf8) == "dddd")
    }

    @Test("attribute-only changes do not trigger reconciliation but content writes still do")
    func attributeOnlyChangesDoNotTriggerReconciliation() async throws {
        let (service, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let tab = try opened(service, root: root, content: "aaaa")
        let url = try #require(tab.fileURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        let changes = Mutex(0)
        let observer = DocumentFileObserver(url: url) { _ in changes.withLock { $0 += 1 } }
        defer { observer.stop() }
        try await Task.sleep(for: .milliseconds(100))
        changes.withLock { $0 = 0 }

        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        try await Task.sleep(for: .milliseconds(250))
        #expect(changes.withLock { $0 } == 0)

        try "bbbb".write(to: url, atomically: false, encoding: .utf8)
        for _ in 0..<100 where changes.withLock({ $0 }) == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(changes.withLock { $0 } > 0)
        #expect(try String(contentsOf: url, encoding: .utf8) == "bbbb")
    }

    @Test("an initiating presenter stays registered and detects subsequent external writes")
    func saveKeepsItsPresenterActive() async throws {
        let (service, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let tab = try opened(service, root: root, content: "unchanged")
        let changes = Mutex(0)
        let observer = DocumentFileObserver(url: try #require(tab.fileURL)) { _ in changes.withLock { $0 += 1 } }
        defer { observer.stop() }
        let result = try service.save(tab: tab, filePresenter: observer)
        try await Task.sleep(for: .milliseconds(200))
        #expect(result.content == tab.content)
        #expect(NSFileCoordinator.filePresenters.contains { $0 === observer })
        changes.withLock { $0 = 0 }
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: try #require(tab.fileURL), options: [],
                                       error: &coordinationError) { url in
            do { try "external".write(to: url, atomically: true, encoding: .utf8) }
            catch { writeError = error }
        }
        if let error = coordinationError ?? writeError { throw error }
        for _ in 0..<100 where changes.withLock({ $0 }) == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(changes.withLock { $0 } > 0)
        #expect(try String(contentsOf: #require(tab.fileURL), encoding: .utf8) == "external")
    }

    @Test("clean external edits reload without rewriting the disk", arguments: [false, true])
    func cleanExternalEdit(atomic: Bool) throws {
        let (service, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let tab = try opened(service, root: root, content: "original")
        let url = try #require(tab.fileURL)
        try "external".write(to: url, atomically: atomic, encoding: .utf8)
        let stamp = Date(timeIntervalSince1970: 1000)
        try FileManager.default.setAttributes([.modificationDate: stamp], ofItemAtPath: url.path)
        let saved = try service.save(tab: tab)
        #expect(saved.content == "external")
        #expect(saved.fileURL == url)
        #expect(saved.diskContent == "external")
        #expect(try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate == stamp)
        #expect(!FileManager.default.fileExists(atPath: service.recoveryDirectory.path))
    }

    @Test("equal-size writes are checked even with preserved or backward timestamps", arguments: [0.0, -3600.0])
    func sameSizeAndOldTimestamp(delta: TimeInterval) throws {
        let (service, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        var tab = try opened(service, root: root, content: "aaaa")
        let url = try #require(tab.fileURL)
        let stamp = try #require(url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        tab.content = "bbbb"
        try "cccc".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: stamp.addingTimeInterval(delta)], ofItemAtPath: url.path)
        let saved = try service.save(tab: tab)
        #expect(saved.fileURL != url)
        #expect(try String(contentsOf: url, encoding: .utf8) == "cccc")
        #expect(try String(contentsOf: #require(saved.fileURL), encoding: .utf8) == "bbbb")
    }

    @Test("independent edits merge without changing native line terminators",
          arguments: ["\n", "\r\n", "\r", "\u{85}", "\u{2028}", "\u{2029}"])
    func disjointMerge(newline: String) throws {
        let (service, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        var tab = try opened(service, root: root, content: ["one", "middle", "three"].joined(separator: newline))
        let url = try #require(tab.fileURL)
        tab.content = ["LOCAL", "middle", "three"].joined(separator: newline)
        try ["one", "middle", "DISK"].joined(separator: newline).write(to: url, atomically: true, encoding: .utf8)
        let saved = try service.save(tab: tab)
        let expected = ["LOCAL", "middle", "DISK"].joined(separator: newline)
        #expect(saved.content == expected)
        #expect(try String(contentsOf: url, encoding: .utf8) == expected)
        #expect(saved.preservedFileURLs.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: service.recoveryDirectory.path).count == 1)
    }

    @Test("overlapping edits keep both files and a durable baseline/local/disk recovery")
    func conflictingEditsSurviveRestart() throws {
        let (service, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        var tab = try opened(service, root: root, content: "baseline\n")
        let original = try #require(tab.fileURL)
        tab.content = "local\n"
        try "disk\n".write(to: original, atomically: true, encoding: .utf8)
        let saved = try service.save(tab: tab)
        #expect(saved.fileURL != original)
        #expect(saved.preservedFileURLs == [original])
        let restarted = DocumentPersistenceService(defaultDirectory: root, recoveryDirectory: service.recoveryDirectory)
        #expect(try restarted.openDocument(at: #require(saved.fileURL)).content == "local\n")
        #expect(try restarted.openDocument(at: original).content == "disk\n")
        let recordURL = try #require(FileManager.default.contentsOfDirectory(at: service.recoveryDirectory,
            includingPropertiesForKeys: nil).first)
        let record = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: recordURL)) as? [String: Any])
        #expect(record["base"] as? String == "baseline\n")
        #expect(record["local"] as? String == "local\n")
        let disk = try #require(record["disk"] as? String)
        #expect(Data(base64Encoded: disk) == Data("disk\n".utf8))
        let mode = try FileManager.default.attributesOfItem(atPath: recordURL.path)[.posixPermissions] as? NSNumber
        #expect(mode?.intValue == 0o600)
    }

    @Test("identical concurrent content does not create a conflict")
    func identicalChanges() throws {
        let (service, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        var tab = try opened(service, root: root, content: "base")
        let url = try #require(tab.fileURL)
        tab.content = "same"
        try tab.content.write(to: url, atomically: true, encoding: .utf8)
        let saved = try service.save(tab: tab)
        #expect(saved.fileURL == url)
        #expect(saved.preservedFileURLs.isEmpty)
    }

    @Test("deleted sources are not recreated and local text is recoverable")
    func deletedSource() throws {
        let (service, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        var tab = try opened(service, root: root, content: "base")
        let url = try #require(tab.fileURL)
        tab.content = "unsaved"
        try FileManager.default.removeItem(at: url)
        #expect(throws: (any Error).self) { try service.save(tab: tab) }
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: service.recoveryDirectory.path).count == 1)
    }

    @Test("invalid external UTF-8 is preserved instead of being overwritten")
    func invalidExternalBytes() throws {
        let (service, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        var tab = try opened(service, root: root, content: "base")
        let url = try #require(tab.fileURL)
        let invalid = Data([0xff, 0xfe, 0x00])
        try invalid.write(to: url)
        tab.content = "local"
        let saved = try service.save(tab: tab)
        #expect(try Data(contentsOf: url) == invalid)
        #expect(saved.fileURL != url)
        #expect(saved.content == "local")
    }

    @Test("recovery failure refuses both overwrite and conflict publication")
    func recoveryFailure() throws {
        let (service, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        var tab = try opened(service, root: root, content: "base")
        let url = try #require(tab.fileURL)
        tab.content = "local"
        try "disk".write(to: url, atomically: true, encoding: .utf8)
        try Data().write(to: service.recoveryDirectory)
        #expect(throws: (any Error).self) { try service.save(tab: tab) }
        #expect(try String(contentsOf: url, encoding: .utf8) == "disk")
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).sorted() == ["recovery", "shared.txt"])
    }

    @Test("a queued first autosave cannot overtake a newer synchronous save")
    func orderedFirstSave() async throws {
        let (service, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let gate = DispatchSemaphore(value: 0)
        service.fileAccess.enqueue { gate.wait() }
        let old = EditorTab(title: "ordered", content: "old")
        var latest = old
        latest.content = "latest"
        let completion = Mutex<EditorTab?>(nil)
        service.enqueueSave(tab: old, in: root) { result in
            if case .success(let saved) = result { completion.withLock { $0 = saved } }
        }
        let snapshot = latest
        let flush = Task.detached { try service.save(tab: snapshot) }
        gate.signal()
        let saved = try await flush.value
        #expect(try String(contentsOf: #require(saved.fileURL), encoding: .utf8) == "latest")
        #expect(completion.withLock { $0?.fileURL } == saved.fileURL)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).count == 1)
    }

    @Test("rename drains pending writes and later saves follow the same file identity")
    func renameDuringAutosave() async throws {
        let (service, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let gate = DispatchSemaphore(value: 0)
        service.fileAccess.enqueue { gate.wait() }
        let tab = EditorTab(title: "first", content: "pending")
        service.enqueueSave(tab: tab, in: root) { _ in }
        let rename = Task.detached { try service.rename(tab: tab, to: "renamed.txt") }
        gate.signal()
        var renamed = try await rename.value
        renamed.content = "newer"
        let saved = try service.save(tab: renamed)
        #expect(saved.fileURL?.lastPathComponent == "renamed.txt")
        #expect(try String(contentsOf: #require(saved.fileURL), encoding: .utf8) == "newer")
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("first.txt").path))
    }

    @Test("background reconciliation never applies a merge against a stale editor snapshot")
    func backgroundDefersExternalMerge() async throws {
        let (service, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let tab = try opened(service, root: root, content: "old")
        let url = try #require(tab.fileURL)
        try "external".write(to: url, atomically: true, encoding: .utf8)
        let result = await withCheckedContinuation { continuation in
            service.enqueueSave(tab: tab, in: root) { continuation.resume(returning: $0) }
        }
        guard case .failure(DocumentPersistenceService.FileAccessError.reconciliationRequired) = result else {
            Issue.record("external changes must be reconciled with the latest main-actor buffer")
            return
        }
        #expect(try String(contentsOf: url, encoding: .utf8) == "external")
    }

    @Test("blank edits never overwrite an externally changed file")
    func blankContract() throws {
        let (service, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        var tab = try opened(service, root: root, content: "base")
        let url = try #require(tab.fileURL)
        tab.content = " \n"
        try "external".write(to: url, atomically: true, encoding: .utf8)
        let saved = try service.save(tab: tab)
        #expect(saved.content == " \n")
        #expect(try String(contentsOf: url, encoding: .utf8) == "external")
    }

    @Test("independent cooperating editors keep both overlapping intentions", arguments: 0..<12)
    func cooperatingEditors(iteration: Int) async throws {
        let (first, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let second = DocumentPersistenceService(defaultDirectory: root, recoveryDirectory: root.appendingPathComponent("recovery"))
        var a = try opened(first, root: root, content: "base")
        let url = try #require(a.fileURL)
        var b = try second.openDocument(at: url)
        a.content = "editor A \(iteration)"
        b.content = "editor B \(iteration)"
        let snapshotA = a
        let snapshotB = b
        async let savedA = Task.detached { try first.save(tab: snapshotA) }.value
        async let savedB = Task.detached { try second.save(tab: snapshotB) }.value
        let outcomes = try await [savedA, savedB]
        let contents = try outcomes.map { try String(contentsOf: #require($0.fileURL), encoding: .utf8) }
        #expect(Set(contents) == Set([a.content, b.content]))
        #expect(outcomes[0].fileURL != outcomes[1].fileURL)
    }

    @Test("symlink aliases use one opened document identity")
    func symlinkAlias() throws {
        let (service, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        var tab = try opened(service, root: root, content: "base")
        let original = try #require(tab.fileURL)
        let link = root.appendingPathComponent("alias.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: original)
        #expect(service.normalizedFileURL(for: link) == original)
        tab.content = "local"
        try "disk".write(to: link, atomically: false, encoding: .utf8)
        let saved = try service.save(tab: tab)
        #expect(saved.fileURL != original)
        #expect(try String(contentsOf: original, encoding: .utf8) == "disk")
    }

    @Test("conflict publication never clobbers a prior conflict copy")
    func conflictCopyCollision() throws {
        let (service, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        var tab = try opened(service, root: root, content: "base")
        let url = try #require(tab.fileURL)
        let existing = root.appendingPathComponent("shared (Conflict).txt")
        try "older conflict".write(to: existing, atomically: true, encoding: .utf8)
        tab.content = "local"
        try "disk".write(to: url, atomically: true, encoding: .utf8)
        let saved = try service.save(tab: tab)
        #expect(saved.fileURL?.lastPathComponent == "shared (Conflict) 2.txt")
        #expect(try String(contentsOf: existing, encoding: .utf8) == "older conflict")
    }

    @Test("duplicating an unopened file copies under a coordinated read instead of torn bytes")
    func duplicateWaitsForCoordinatedWriter() async throws {
        let (service, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("shared.txt")
        let destination = root.appendingPathComponent("shared copy.txt")
        let before = Data(repeating: UInt8(ascii: "a"), count: 8 * 1024 * 1024)
        let final = Data(repeating: UInt8(ascii: "b"), count: 8 * 1024 * 1024)
        try before.write(to: source)

        let claimHeld = DispatchSemaphore(value: 0)
        let releaseClaim = DispatchSemaphore(value: 0)
        let writer = Task.detached { () -> Error? in
            var coordinationError: NSError?
            var writeError: Error?
            NSFileCoordinator().coordinate(writingItemAt: source, options: [],
                                           error: &coordinationError) { coordinatedURL in
                claimHeld.signal()
                releaseClaim.wait()
                do { try final.write(to: coordinatedURL) } catch { writeError = error }
            }
            return coordinationError ?? writeError
        }
        guard await waitForSignal(claimHeld) else {
            releaseClaim.signal()
            Issue.record("the coordinated writer never acquired its claim")
            return
        }
        // Safety net for early exits; the duplicate below needs the explicit
        // release so the copy can proceed.
        defer { releaseClaim.signal() }

        let isFinished = Mutex(false)
        let duplicate = Task.detached { () -> URL in
            defer { isFinished.withLock { $0 = true } }
            return try service.duplicateSidebarFile(at: source)
        }
        // A copy that ignores the claim returns the old bytes at once, while
        // the writer still owns the source.
        try await Task.sleep(for: .milliseconds(400))
        let finishedEarly = isFinished.withLock { $0 }
        #expect(!finishedEarly, "the duplicate must wait for the coordinated claim")
        #expect(!FileManager.default.fileExists(atPath: destination.path),
                "a partial destination must never be published")

        releaseClaim.signal()
        let copyURL = try await boundedValue(of: duplicate)
        #expect(copyURL.lastPathComponent == "shared copy.txt")
        #expect(try Data(contentsOf: copyURL) == final)
        #expect(try Data(contentsOf: source) == final)
        if let writerError = await writer.value { throw writerError }
    }

    @Test("save copy recovers a missing source without clobbering a chosen destination")
    func saveCopyRecovery() throws {
        let (service, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        var tab = try opened(service, root: root, content: "base")
        let source = try #require(tab.fileURL)
        try FileManager.default.removeItem(at: source)
        tab.content = "recover me"
        let destination = root.appendingPathComponent("rescued.txt")
        try "unrelated".write(to: destination, atomically: true, encoding: .utf8)
        let saved = try service.saveCopy(tab: tab, to: destination)
        #expect(saved.fileURL?.lastPathComponent == "rescued 2.txt")
        #expect(try String(contentsOf: destination, encoding: .utf8) == "unrelated")
        #expect(try String(contentsOf: #require(saved.fileURL), encoding: .utf8) == "recover me")
        #expect(!FileManager.default.fileExists(atPath: source.path))
        var blank = tab
        blank.content = " \n"
        let untouched = try service.saveCopy(tab: blank, to: root.appendingPathComponent("blank.txt"))
        #expect(untouched.fileURL == source)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("blank.txt").path))
    }

    @Test("large simultaneous rewrites fall back to retained conflict copies")
    func boundedMerge() {
        let base = String(repeating: "base\n", count: 20_001)
        let local = "local\n" + base
        let disk = base + "disk\n"
        #expect(DocumentTextMerge.merge(base: base, local: local, disk: disk) == nil)
        #expect(DocumentTextMerge.merge(base: base, local: base, disk: disk) == disk)
    }

    @Test("conservative merge handles insert/delete, duplicates and overlapping insertions")
    func mergeBoundaries() {
        #expect(DocumentTextMerge.merge(base: "a\nb\nc\n", local: "a\nc\n", disk: "a\nb\nC\n") == "a\nC\n")
        #expect(DocumentTextMerge.merge(base: "a\nb\nc\n", local: "A\nb\nc\n", disk: "a\nb\nc\nnew\n") == "A\nb\nc\nnew\n")
        #expect(DocumentTextMerge.merge(base: "a\n", local: "x\na\n", disk: "y\na\n") == nil)
        #expect(DocumentTextMerge.merge(base: "same\nsame\nend", local: "new\nsame\nend", disk: "same\nsame\nEND") == "new\nsame\nEND")
    }

    @Test("deadline returns while a controlled task is still pending, then drains it")
    func deadlineReturnsWhilePending() async throws {
        let gate = Mutex<CheckedContinuation<Void, Never>?>(nil)
        let finished = Mutex(false)
        let pending: Task<String, Error> = Task.detached {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                gate.withLock { $0 = continuation }
            }
            finished.withLock { $0 = true }
            return "late"
        }
        var registered = false
        for _ in 0..<500 where !registered {
            registered = gate.withLock { $0 != nil }
            if !registered {
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        #expect(registered)
        let start = ContinuousClock.now
        do {
            _ = try await boundedValue(of: pending, timeout: .milliseconds(50))
            Issue.record("boundedValue must time out while the controlled task is still pending")
        } catch is TimeoutError {
        } catch {
            Issue.record("expected TimeoutError, got \(type(of: error))")
        }
        let elapsed = ContinuousClock.now - start
        #expect(elapsed < .seconds(2))
        #expect(finished.withLock { $0 } == false)
        #expect(gate.withLock { $0 != nil })
        gate.withLock { $0 }?.resume()
        let drained = try await pending.value
        #expect(drained == "late")
        #expect(finished.withLock { $0 } == true)
    }

    @Test("deadline passes through success before expiry, including already-completed close races")
    func deadlineSuccess() async throws {
        let fast: Task<String, Error> = Task.detached { "fast" }
        let value = try await boundedValue(of: fast, timeout: .seconds(5))
        #expect(value == "fast")
        for _ in 0..<50 {
            let immediate: Task<String, Error> = Task.detached { "ok" }
            _ = try await immediate.value
            let raced = try await boundedValue(of: immediate, timeout: .milliseconds(20))
            #expect(raced == "ok")
        }
    }

    @Test("deadline propagates the original error, including already-failed close races")
    func deadlineError() async throws {
        let failing: Task<String, Error> = Task.detached { throw ControlledFailure() }
        do {
            _ = try await boundedValue(of: failing, timeout: .seconds(5))
            Issue.record("expected ControlledFailure")
        } catch is ControlledFailure {
        } catch {
            Issue.record("expected ControlledFailure, got \(type(of: error))")
        }
        for _ in 0..<20 {
            let alreadyFailed: Task<String, Error> = Task.detached { throw ControlledFailure() }
            do {
                _ = try await boundedValue(of: alreadyFailed, timeout: .milliseconds(20))
                Issue.record("expected ControlledFailure")
            } catch is ControlledFailure {
            } catch {
                Issue.record("expected ControlledFailure, got \(type(of: error))")
            }
        }
    }

    @Test("caller cancellation returns without joining pending work, then drains it")
    func deadlineCallerCancellation() async throws {
        let gate = Mutex<CheckedContinuation<Void, Never>?>(nil)
        let finished = Mutex(false)
        let pending: Task<String, Error> = Task.detached {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                gate.withLock { $0 = continuation }
            }
            finished.withLock { $0 = true }
            return "late"
        }
        var registered = false
        for _ in 0..<500 where !registered {
            registered = gate.withLock { $0 != nil }
            if !registered {
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        #expect(registered)
        let caller: Task<String, Error> = Task.detached {
            try await boundedValue(of: pending, timeout: .seconds(5))
        }
        try await Task.sleep(for: .milliseconds(20))
        caller.cancel()
        do {
            _ = try await caller.value
            Issue.record("expected CancellationError")
        } catch is CancellationError {
        } catch {
            Issue.record("expected CancellationError, got \(type(of: error))")
        }
        #expect(finished.withLock { $0 } == false)
        gate.withLock { $0 }?.resume()
        let drained = try await pending.value
        #expect(drained == "late")
        #expect(finished.withLock { $0 } == true)
    }

    @Test("pre-cancelled caller throws CancellationError without running pending work")
    func deadlinePreCancelledCaller() async throws {
        let gate = Mutex<CheckedContinuation<Void, Never>?>(nil)
        let finished = Mutex(false)
        let pending: Task<String, Error> = Task.detached {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                gate.withLock { $0 = continuation }
            }
            finished.withLock { $0 = true }
            return "late"
        }
        var pendingRegistered = false
        for _ in 0..<500 where !pendingRegistered {
            pendingRegistered = gate.withLock { $0 != nil }
            if !pendingRegistered {
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        #expect(pendingRegistered)
        let startGate = Mutex<CheckedContinuation<Void, Never>?>(nil)
        let caller: Task<String, Error> = Task.detached {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                startGate.withLock { $0 = continuation }
            }
            return try await boundedValue(of: pending, timeout: .seconds(5))
        }
        var callerParked = false
        for _ in 0..<500 where !callerParked {
            callerParked = startGate.withLock { $0 != nil }
            if !callerParked {
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        #expect(callerParked)
        caller.cancel()
        #expect(caller.isCancelled)
        startGate.withLock { $0 }?.resume()
        do {
            _ = try await caller.value
            Issue.record("expected CancellationError")
        } catch is CancellationError {
        } catch {
            Issue.record("expected CancellationError, got \(type(of: error))")
        }
        #expect(finished.withLock { $0 } == false)
        gate.withLock { $0 }?.resume()
        let drained = try await pending.value
        #expect(drained == "late")
        #expect(finished.withLock { $0 } == true)
    }

    @Test("gate cancels children registered after a win and clears handles")
    func deadlineGateLateRegistration() async throws {
        let gate = DeadlineGate<String>()
        let dummyWorker: Task<Void, Never> = Task.detached {}
        #expect(gate.registerWorker(dummyWorker) == false)
        await dummyWorker.value
        let (firstCont, firstWorker, firstTimer) = gate.claimWin()
        #expect(firstCont == nil)
        #expect(firstWorker != nil)
        #expect(firstTimer == nil)
        let lateTimer: Task<Void, Never> = Task.detached {
            try? await Task.sleep(for: .seconds(5))
        }
        #expect(gate.registerTimer(lateTimer) == true)
        #expect(lateTimer.isCancelled)
        lateTimer.cancel()
        await lateTimer.value
        let lateWorker: Task<Void, Never> = Task.detached {
            try? await Task.sleep(for: .seconds(5))
        }
        #expect(gate.registerWorker(lateWorker) == true)
        #expect(lateWorker.isCancelled)
        lateWorker.cancel()
        await lateWorker.value
        let (secondCont, secondWorker, secondTimer) = gate.claimWin()
        #expect(secondCont == nil && secondWorker == nil && secondTimer == nil)
    }
}
