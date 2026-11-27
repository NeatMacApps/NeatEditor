import AppKit
import SwiftUI
import Testing

@testable import NeatEditor

@MainActor
struct InterfaceFontSizeTests {
    @Test("discrete step indices round-trip and clamp out-of-range inputs")
    func stepIndexRoundTripAndClamp() {
        #expect(InterfaceFontSize.allCases.count == 5)
        for (index, size) in InterfaceFontSize.allCases.enumerated() {
            #expect(size.stepIndex == index)
            #expect(InterfaceFontSize(stepIndex: index) == size)
        }
        #expect(InterfaceFontSize(stepIndex: -5) == .extraSmall)
        #expect(InterfaceFontSize(stepIndex: 99) == .extraLarge)
    }

    @Test("font sizes and sidebar row heights increase monotonically and fit inside the tab strip")
    func monotonicScalingAndBounds() {
        let levels = InterfaceFontSize.allCases
        for pair in zip(levels, levels.dropFirst()) {
            #expect(pair.0.scaleFactor < pair.1.scaleFactor)
            #expect(pair.0.tabTitleFontSize < pair.1.tabTitleFontSize)
            #expect(pair.0.sidebarHeaderFontSize < pair.1.sidebarHeaderFontSize)
            #expect(pair.0.sidebarTitleFontSize < pair.1.sidebarTitleFontSize)
            #expect(pair.0.sidebarPreviewFontSize < pair.1.sidebarPreviewFontSize)
            #expect(pair.0.sidebarTitleLineHeight < pair.1.sidebarTitleLineHeight)
            #expect(pair.0.sidebarPreviewHeight < pair.1.sidebarPreviewHeight)
        }
        #expect(InterfaceFontSize.standard.tabTitleFontSize == EditorTabLayout.titleFontSize)
        #expect(InterfaceFontSize.extraLarge.tabTitleFontSize <= 16)
    }

    @Test("missing or unknown interfaceFontSize decodes to standard without disturbing other preferences",
          arguments: ["{}", #"{"editorFontSize":19,"interfaceFontSize":"future-step"}"#])
    func decodeFallback(json: String) throws {
        let preferences = try JSONDecoder().decode(WorkspacePreferences.self, from: Data(json.utf8))
        #expect(preferences.interfaceFontSize == .standard)
        #expect(preferences.editorFontSize == (json == "{}" ? 13 : 19))
    }

    @Test("all interface font size levels round-trip in WorkspacePreferences", arguments: InterfaceFontSize.allCases)
    func preferencesRoundTrip(size: InterfaceFontSize) throws {
        let preferences = WorkspacePreferences(editorFontSize: 15, interfaceFontSize: size)
        let restored = try JSONDecoder().decode(
            WorkspacePreferences.self,
            from: JSONEncoder().encode(preferences)
        )
        #expect(restored == preferences)
        #expect(restored.editorFontSize == 15)
    }

    @Test("interface font size persists through WorkspaceStore save and reload without changing editor font size",
          arguments: InterfaceFontSize.allCases)
    func storePersistence(size: InterfaceFontSize) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NeatEditorInterfaceFontTests-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "NeatEditorInterfaceFontTests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = WorkspaceStore(
            persistenceService: DocumentPersistenceService(defaultDirectory: directory),
            userDefaults: defaults
        )
        store.tabs = [EditorTab(title: "note.txt", content: "hello")]
        store.selectedTabID = store.tabs[0].id
        let originalEditorFontSize = store.preferences.editorFontSize
        store.preferences.interfaceFontSize = size
        store.flushPendingSaveState()

        let restored = WorkspaceStore(
            persistenceService: DocumentPersistenceService(defaultDirectory: directory),
            userDefaults: defaults
        )
        #expect(restored.preferences.interfaceFontSize == size)
        #expect(restored.preferences.editorFontSize == originalEditorFontSize)
        restored.pendingSaveStateTask?.cancel()
    }

    @Test("localized level names resolve in English and Simplified Chinese without point or pixel units",
          arguments: [
              ("en", InterfaceFontSize.extraSmall, "Extra Small"),
              ("en", InterfaceFontSize.small, "Small"),
              ("en", InterfaceFontSize.standard, "Default"),
              ("en", InterfaceFontSize.large, "Large"),
              ("en", InterfaceFontSize.extraLarge, "Extra Large"),
              ("zh-Hans", InterfaceFontSize.extraSmall, "极小"),
              ("zh-Hans", InterfaceFontSize.small, "较小"),
              ("zh-Hans", InterfaceFontSize.standard, "默认"),
              ("zh-Hans", InterfaceFontSize.large, "较大"),
              ("zh-Hans", InterfaceFontSize.extraLarge, "极大"),
          ])
    func localizedNames(locale: String, size: InterfaceFontSize, expected: String) throws {
        let lprojPath = try #require(Bundle.main.path(forResource: locale, ofType: "lproj"))
        let localizedBundle = try #require(Bundle(path: lprojPath))
        let resolved = localizedBundle.localizedString(forKey: size.localizedNameKey, value: nil, table: nil)
        #expect(resolved == expected)
        #expect(!resolved.contains("pt"))
        #expect(!resolved.contains("px"))
    }

    @Test("changing interface font size updates live tab strip fonts without recreating tabs")
    func liveTabStripFontUpdate() throws {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 800, height: 40),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }

        let strip = EditorTabStripView(frame: CGRect(x: 0, y: 0, width: 800, height: 40))
        window.contentView = strip
        let tab = EditorTabDescriptor(id: UUID(), title: "Notes.txt")
        strip.update(tabs: [tab], selectedTabID: tab.id, actions: EditorTabActions())
        strip.layoutSubtreeIfNeeded()

        let originalItem = try #require(strip.tabViews[tab.id])
        #expect(originalItem.titleField.font?.pointSize == InterfaceFontSize.standard.tabTitleFontSize)

        for level in InterfaceFontSize.allCases {
            strip.interfaceFontSize = level
            strip.layoutSubtreeIfNeeded()
            let currentItem = try #require(strip.tabViews[tab.id])
            #expect(currentItem === originalItem)
            #expect(currentItem.titleField.font?.pointSize == level.tabTitleFontSize)
        }
    }

    @Test("SettingsView and workspace chrome render cleanly across interface font size levels")
    func renderSettingsAndChromeAcrossLevels() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NeatEditorInterfaceFontRender-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try "Hello NeatEditor!\nThis is a sample document.".write(
            to: directory.appendingPathComponent("Welcome.txt"),
            atomically: true,
            encoding: .utf8
        )
        try "Weekly sync notes\n- Review UI font scale slider".write(
            to: directory.appendingPathComponent("MeetingNotes.txt"),
            atomically: true,
            encoding: .utf8
        )

        let suite = "NeatEditorInterfaceFontRender-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = WorkspaceStore(
            persistenceService: DocumentPersistenceService(defaultDirectory: directory),
            userDefaults: defaults
        )
        defer { store.pendingSaveStateTask?.cancel() }
        store.refreshSidebarFiles()
        try await Task.sleep(for: .milliseconds(150))

        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 880, height: 700),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }

        let host = NSHostingView(rootView: WorkspaceView().environment(store))
        host.frame = CGRect(x: 0, y: 0, width: 880, height: 700)
        window.contentView = host
        window.appearance = NSAppearance(named: .aqua)

        store.openSettings()
        await Task.yield()
        window.layoutIfNeeded()

        for level in [InterfaceFontSize.extraSmall, .standard, .extraLarge] {
            store.preferences.interfaceFontSize = level
            await Task.yield()
            window.layoutIfNeeded()
        }
        #expect(store.preferences.interfaceFontSize == .extraLarge)
    }
}
