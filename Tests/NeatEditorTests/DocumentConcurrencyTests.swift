import Foundation
import Synchronization
import Testing

@testable import NeatEditor

struct DocumentConcurrencyTests {
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
}
