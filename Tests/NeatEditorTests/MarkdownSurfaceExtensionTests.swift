import Foundation
import SwiftUI
import Testing
@testable import NeatEditor

@MainActor
private final class StubMarkdownSurfaceProvider: MarkdownSurfaceProviding {
    var capability: MarkdownEditCapability

    init(capability: MarkdownEditCapability) {
        self.capability = capability
    }

    func makeEditorView(configuration: MarkdownSurfaceConfiguration) -> AnyView {
        AnyView(EmptyView())
    }
}

@MainActor
@Suite("MarkdownSurfaceExtension")
struct MarkdownSurfaceExtensionTests {
    private func makeTemporaryDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("neateditor-md-seam-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeIsolatedStore(directory: URL) -> WorkspaceStore {
        let suiteName = "com.x0c.NeatEditor.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        return WorkspaceStore(
            persistenceService: DocumentPersistenceService(
                defaultDirectory: directory,
                recoveryDirectory: directory.appendingPathComponent("recovery", isDirectory: true)
            ),
            userDefaults: defaults,
            enablesAutomaticDefaultAppPrompts: false
        )
    }

    @Test("Default standalone build has no registered Markdown provider")
    func defaultRegistryIsEmpty() {
        #expect(EditorExtensionRegistry.markdownProvider == nil)
    }

    @Test("EditorTab detects Markdown extensions accurately")
    func markdownDocumentDetection() {
        let md = EditorTab(title: "README.md", fileURL: URL(fileURLWithPath: "/tmp/README.md"))
        let markdownUpper = EditorTab(title: "GUIDE.MARKDOWN", fileURL: URL(fileURLWithPath: "/tmp/GUIDE.MARKDOWN"))
        let unsavedMD = EditorTab(title: "Draft.md", fileURL: nil)
        let txt = EditorTab(title: "notes.txt", fileURL: URL(fileURLWithPath: "/tmp/notes.txt"))
        let untitled = EditorTab(title: "Untitled", fileURL: nil)
        let settings = EditorTab(title: "Settings", isSettings: true)

        #expect(md.isMarkdownDocument == true)
        #expect(markdownUpper.isMarkdownDocument == true)
        #expect(unsavedMD.isMarkdownDocument == true)
        #expect(txt.isMarkdownDocument == false)
        #expect(untitled.isMarkdownDocument == false)
        #expect(settings.isMarkdownDocument == false)
    }

    @Test("WorkspaceStore source toggle and formatting eligibility follow capability and selection")
    func storeSourceToggleAndCapability() async throws {
        let original = EditorExtensionRegistry.markdownProvider
        defer { EditorExtensionRegistry.markdownProvider = original }

        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = makeIsolatedStore(directory: dir)
        let mdURL = dir.appendingPathComponent("sample.md")
        try "# Hello".write(to: mdURL, atomically: true, encoding: .utf8)
        store.openFiles(at: [mdURL])
        guard let mdTabID = store.selectedTabID else {
            Issue.record("Expected selected tab")
            return
        }

        // Wait for async lazy file load to complete.
        for _ in 0..<40 {
            if store.selectedTab?.isContentLoaded == true { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(store.selectedTab?.isContentLoaded == true)

        // Without provider: Markdown surface unavailable
        EditorExtensionRegistry.markdownProvider = nil
        #expect(store.isMarkdownSurfaceAvailable == false)
        #expect(store.isSelectedTabMarkdown == false)
        #expect(store.canPerformMarkdownFormatting == false)

        // Read-only preview provider: Markdown tab active, source toggle works, formatting blocked
        let previewProvider = StubMarkdownSurfaceProvider(capability: .readOnlyPreview)
        EditorExtensionRegistry.markdownProvider = previewProvider
        #expect(store.isMarkdownSurfaceAvailable == true)
        #expect(store.isSelectedTabMarkdown == true)
        #expect(store.canPerformMarkdownFormatting == false)

        store.toggleMarkdownSourceMode()
        #expect(store.isSelectedTabInSourceMode == true)
        store.toggleMarkdownSourceMode()
        #expect(store.isSelectedTabInSourceMode == false)

        // Full editing provider: formatting eligible only on Markdown tabs
        let fullProvider = StubMarkdownSurfaceProvider(capability: .fullEditing)
        EditorExtensionRegistry.markdownProvider = fullProvider
        var recordedAction: MarkdownFormattingAction?
        store.performMarkdownFormatAction = { action in
            recordedAction = action
        }
        #expect(store.canPerformMarkdownFormatting == true)
        store.performMarkdownFormatting(.bold)
        #expect(recordedAction == .bold)

        // Plain-text untitled tab stays non-Markdown and blocks Markdown formatting
        store.createNewDocument()
        #expect(store.selectedTabID != mdTabID)
        #expect(store.isSelectedTabMarkdown == false)
        #expect(store.canPerformMarkdownFormatting == false)
    }
}
