import Foundation
import Testing

@testable import NeatEditor

struct DocumentFilePublicationTests {
    @Test("publication retries only collisions and preserves the final extension", arguments: [
        "note", "note.", "notes.archive.md", "笔记.txt"
    ])
    func collisionCandidates(fileName: String) throws {
        let directory = FileManager.default.temporaryDirectory
        let service = DocumentPersistenceService(defaultDirectory: directory)
        var attempts: [String] = []
        let result = try service.publishFile(named: fileName, in: directory) { destination in
            attempts.append(destination.lastPathComponent)
            if attempts.count < 3 {
                throw CocoaError(.fileWriteFileExists)
            }
        }
        let baseName = (fileName as NSString).deletingPathExtension
        let pathExtension = (fileName as NSString).pathExtension
        let extensionSuffix = pathExtension.isEmpty ? "" : ".\(pathExtension)"
        #expect(attempts == [fileName, "\(baseName) 2\(extensionSuffix)", "\(baseName) 3\(extensionSuffix)"])
        #expect(result == service.normalizedFileURL(for: directory.appendingPathComponent(attempts[2])))
    }

    @Test("publication propagates non-collision errors without retrying")
    func publicationFailureStopsImmediately() throws {
        let service = DocumentPersistenceService()
        var attempts = 0
        do {
            _ = try service.publishFile(named: "note.txt", in: service.defaultDirectory) { _ in
                attempts += 1
                throw CocoaError(.fileWriteNoPermission)
            }
            Issue.record("Expected the original publication failure")
        } catch let error as CocoaError {
            #expect(error.code == .fileWriteNoPermission)
        }
        #expect(attempts == 1)
    }

    @Test("exhausted publication reports the last attempted name after exactly 1000 candidates")
    func exhaustedCandidatesStayBounded() throws {
        let service = DocumentPersistenceService()
        var attempts = 0
        do {
            _ = try service.publishFile(named: "note.md", in: service.defaultDirectory) { _ in
                attempts += 1
                throw CocoaError(.fileWriteFileExists)
            }
            Issue.record("Expected exhausted candidates to fail")
        } catch DocumentPersistenceService.PersistenceError.destinationAlreadyExists(let destination) {
            #expect(destination.lastPathComponent == "note 1000.md")
        }
        #expect(attempts == 1000)
    }

    @Test("disk and live-buffer duplicates share numbered names and preserve every file", arguments: [
        "note.md", "notes", "笔记.archive.txt"
    ])
    func duplicatesShareCollisionPolicy(fileName: String) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NeatEditorPublication-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent(fileName)
        try "original".write(to: source, atomically: true, encoding: .utf8)
        let service = DocumentPersistenceService(defaultDirectory: directory)

        let first = try service.duplicateSidebarFile(at: source)
        let second = try service.duplicateSidebarFile(at: source, content: "unsaved 中文 👨‍👩‍👧‍👦")
        let third = try service.duplicateSidebarFile(at: source)
        let baseName = (fileName as NSString).deletingPathExtension
        let pathExtension = (fileName as NSString).pathExtension
        let extensionSuffix = pathExtension.isEmpty ? "" : ".\(pathExtension)"
        #expect(first.lastPathComponent == "\(baseName) copy\(extensionSuffix)")
        #expect(second.lastPathComponent == "\(baseName) copy 2\(extensionSuffix)")
        #expect(third.lastPathComponent == "\(baseName) copy 3\(extensionSuffix)")
        #expect(try String(contentsOf: first, encoding: .utf8) == "original")
        #expect(try String(contentsOf: second, encoding: .utf8) == "unsaved 中文 👨‍👩‍👧‍👦")
        #expect(try String(contentsOf: third, encoding: .utf8) == "original")
        #expect(try String(contentsOf: source, encoding: .utf8) == "original")
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 4)
    }
}
