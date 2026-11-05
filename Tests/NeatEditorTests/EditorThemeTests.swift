import AppKit
import Testing

@testable import NeatEditor

@MainActor
struct EditorThemeTests {
    @Test("legacy and unknown theme values preserve other preferences and use Warm",
          arguments: ["{}", #"{"editorFontSize":19,"editorTheme":"future-theme"}"#])
    func fallback(json: String) throws {
        let preferences = try JSONDecoder().decode(WorkspacePreferences.self, from: Data(json.utf8))
        #expect(preferences.editorTheme == .warm)
        #expect(preferences.editorFontSize == (json == "{}" ? 13 : 19))
    }

    @Test("both theme choices round trip with existing preferences", arguments: EditorTheme.allCases)
    func roundTrip(theme: EditorTheme) throws {
        let preferences = WorkspacePreferences(editorFontSize: 17, tabBehavior: .spaces2, editorTheme: theme)
        let restored = try JSONDecoder().decode(
            WorkspacePreferences.self, from: JSONEncoder().encode(preferences)
        )
        #expect(restored == preferences)
    }

    @Test("neutral theme is white by day and black at night, including high contrast",
          arguments: [NSAppearance.Name.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua])
    func neutralPalette(appearanceName: NSAppearance.Name) throws {
        let appearance = try #require(NSAppearance(named: appearanceName))
        let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let surface = EditorChrome.resolvedColor(EditorChrome.editorSurfaceColor(for: .whiteBlack), for: appearance)
        let band = EditorChrome.resolvedColor(EditorChrome.tabBarBackgroundColor(for: .whiteBlack), for: appearance)
        for component in [surface.redComponent, surface.greenComponent, surface.blueComponent] {
            #expect(abs(component - (dark ? 0 : 1)) < 0.0001)
        }
        #expect(band != surface)
        #expect(abs(band.redComponent - band.greenComponent) < 0.0001)
    }

    @Test("live theme changes repaint the native editor and gutter without changing text, selection or undo",
          arguments: [NSAppearance.Name.aqua, .darkAqua])
    func liveEditorRepaint(appearanceName: NSAppearance.Name) throws {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let container = EditorTextContainerView()
        window.contentView = container
        let appearance = try #require(NSAppearance(named: appearanceName))
        window.appearance = appearance
        container.textView.string = "Theme test\n中文 👋"
        container.applyEditorTextAttributes()
        let selection = NSRange(location: 2, length: 3)
        container.textView.setSelectedRange(selection)
        let undo = container.textView.undoManager
        let couldUndo = undo?.canUndo
        let originalText = container.textView.string
        let gutter = try #require(container.subviews.compactMap { $0 as? LineNumberGutterView }.first)

        for theme in [EditorTheme.whiteBlack, .warm, .whiteBlack] {
            container.theme = theme
            let expected = EditorChrome.resolvedColor(
                EditorChrome.editorSurfaceColor(for: theme), for: container.effectiveAppearance
            )
            #expect(container.textView.backgroundColor == expected)
            #expect(gutter.theme == theme)
            let color = try #require(gutter.layer?.backgroundColor).converted(
                to: try #require(CGColorSpace(name: CGColorSpace.sRGB)), intent: .defaultIntent, options: nil
            )
            #expect(try #require(color?.components).prefix(3).elementsEqual(
                [expected.redComponent, expected.greenComponent, expected.blueComponent],
                by: { abs($0 - $1) < 0.0001 }
            ))
            #expect(container.textView.string == originalText)
            #expect(container.textView.selectedRange() == selection)
            #expect(container.textView.undoManager === undo)
            #expect(container.textView.undoManager?.canUndo == couldUndo)
        }
    }

    @Test("theme selection persists through the workspace save and reload path", arguments: EditorTheme.allCases)
    func storePersistence(theme: EditorTheme) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NeatEditorThemeTests-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "NeatEditorThemeTests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = WorkspaceStore(
            persistenceService: DocumentPersistenceService(defaultDirectory: directory),
            userDefaults: defaults
        )
        store.tabs = [EditorTab(title: "note.txt", content: "hello")]
        store.selectedTabID = store.tabs[0].id
        store.preferences.editorTheme = theme
        store.flushPendingSaveState()

        let restored = WorkspaceStore(
            persistenceService: DocumentPersistenceService(defaultDirectory: directory),
            userDefaults: defaults
        )
        #expect(restored.preferences.editorTheme == theme)
        restored.pendingSaveStateTask?.cancel()
    }

    @Test("changing themes invalidates unchanged selected tab descriptors")
    func tabRepaint() throws {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 40),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let strip = EditorTabStripView(frame: CGRect(x: 0, y: 0, width: 800, height: 40))
        window.contentView = strip
        let tab = EditorTabDescriptor(id: UUID(), title: "Theme")
        strip.update(tabs: [tab], selectedTabID: tab.id, actions: EditorTabActions())
        strip.layoutSubtreeIfNeeded()
        let item = try #require(strip.tabViews[tab.id])
        item.needsDisplay = false
        strip.theme = .whiteBlack
        #expect(item.needsDisplay)
        #expect(strip.selectedTabID == tab.id)
        #expect(strip.tabs == [tab])
        let bitmap = try #require(item.bitmapImageRepForCachingDisplay(in: item.bounds))
        item.cacheDisplay(in: item.bounds, to: bitmap)
        let pixel = try #require(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh - 3)?.usingColorSpace(.sRGB))
        let expected = EditorChrome.resolvedColor(EditorChrome.editorSurfaceColor(for: .whiteBlack), for: item.effectiveAppearance)
        #expect(abs(pixel.redComponent - expected.redComponent) < 0.01)
        #expect(abs(pixel.greenComponent - expected.greenComponent) < 0.01)
        #expect(abs(pixel.blueComponent - expected.blueComponent) < 0.01)
    }
}
