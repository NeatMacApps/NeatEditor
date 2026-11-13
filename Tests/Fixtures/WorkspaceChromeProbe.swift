import AppKit
import SwiftUI

@testable import NeatEditor

/// Simulates application-active drawing. The window must become key BEFORE
/// toolbar attachment: activating it afterwards misses the cold-launch white cap.
/// Cache drawing can repaint the defect. Use --cold-launch with winshot, then
/// --verify-capture, for compositor acceptance. This is not physical input evidence.
private final class ChromeProbeApplication: NSApplication {
    override var isActive: Bool { true }
}

@MainActor
private enum ChromeProbeState {
    static var keyAtAttachment = false

    static func prepare(_ window: NSWindow) {
        window.becomeKey()
        keyAtAttachment = window.isKeyWindow
    }
}

private struct ChromeProbeApp: App {
    private let store: WorkspaceStore
    private let directory: URL
    private let defaults: UserDefaults
    private let suite: String
    private let arguments = ProcessInfo.processInfo.arguments
    @State private var isDark: Bool

    init() {
        _isDark = State(initialValue: arguments.contains("--dark"))
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NeatEditorChromeProbe-\(UUID())", isDirectory: true)
        suite = "NeatEditorChromeProbe-\(UUID())"
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            fatalError("Cannot create isolated document folder: \(error)")
        }
        guard let defaults = UserDefaults(suiteName: suite) else {
            fatalError("Cannot create isolated preferences")
        }
        self.defaults = defaults
        store = WorkspaceStore(
            persistenceService: DocumentPersistenceService(defaultDirectory: directory),
            userDefaults: defaults
        )
        store.tabs = [EditorTab(title: "Chrome test.txt", content: "Chrome test")]
        store.selectedTabID = store.tabs.first?.id
        store.preferences.editorTheme = arguments.contains("--neutral") ? .whiteBlack : .warm
        store.preferences.isSidebarVisible = arguments.contains("--sidebar")
    }

    var body: some Scene {
        Window("Workspace Chrome Probe", id: "probe") {
            WorkspaceView()
                .environment(store)
                .preferredColorScheme(isDark ? .dark : .light)
                .frame(minWidth: 470, minHeight: 400)
                .task {
                    do {
                        try await Task.sleep(for: .milliseconds(250))
                        let window = try requireWindow()
                        guard ChromeProbeState.keyAtAttachment else {
                            throw ProbeFailure("Cold launch was not key before toolbar attachment")
                        }
                        // WindowServer can resign an occluded fixture under screen lock.
                        // Restore key drawing without changing its initial toolbar state.
                        window.becomeKey()
                        if arguments.contains("--cold-launch") {
                            // Leave the initial compositor surface untouched for winshot.
                            // No resize, sidebar transition, forced layout or cache drawing.
                            print("COLD READY theme=\(store.preferences.editorTheme.rawValue) "
                                + "dark=\(isDark) sidebar=\(store.preferences.isSidebarVisible) "
                                + "width=\(window.frame.width) key=\(window.isKeyWindow)")
                            fflush(nil)
                            try await Task.sleep(for: .seconds(20))
                        } else {
                            // This checks cached drawing/routing, NOT first-frame pixels.
                            try verify(window: window, initialState: true)
                            if arguments.contains("--matrix") {
                                for theme in EditorTheme.allCases {
                                    for dark in [false, true] {
                                        for sidebar in [false, true] {
                                            for narrow in [false, true] {
                                                store.preferences.editorTheme = theme
                                                store.preferences.isSidebarVisible = sidebar
                                                try await verifyTransition(dark: dark, narrow: narrow)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        cleanup()
                        exit(0)
                    } catch {
                        print("FAIL: \(error)")
                        cleanup()
                        exit(1)
                    }
                }
        }
        .windowStyle(.titleBar)
        .windowBackgroundDragBehavior(.enabled)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.presented)
        .defaultSize(width: arguments.contains("--narrow") ? 470 : 900, height: 500)
    }

    @MainActor
    private func requireWindow() throws -> NSWindow {
        try require(NSApplication.shared.windows.first { $0.title == "Workspace Chrome Probe" })
    }

    @MainActor
    private func verifyTransition(dark: Bool, narrow: Bool) async throws {
        try await Task.sleep(for: .milliseconds(100))
        let window = try requireWindow()
        isDark = dark
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.setContentSize(CGSize(width: narrow ? 470 : 900, height: 500))
        try await Task.sleep(for: .milliseconds(200))
        window.layoutIfNeeded()
        window.contentView?.superview?.layoutSubtreeIfNeeded()
        try verify(window: window, initialState: false)
    }

    @MainActor
    private func verify(window: NSWindow, initialState: Bool) throws {
        let frame = try require(window.contentView?.superview)
        let bitmap = try require(frame.bitmapImageRepForCachingDisplay(in: frame.bounds))
        frame.cacheDisplay(in: frame.bounds, to: bitmap)
        let peer = try verifyBand(bitmap, width: frame.bounds.width, dark: isDark)
        guard !window.titlebarAppearsTransparent, window.toolbarStyle == .unifiedCompact,
              window.toolbar?.isVisible == true, window.toolbar?.items.isEmpty == true,
              abs(window.frame.height - window.contentLayoutRect.height - EditorTabLayout.stripHeight) < 0.5 else {
            throw ProbeFailure("Native compact toolbar was not preserved: "
                + "transparent=\(window.titlebarAppearsTransparent), style=\(window.toolbarStyle.rawValue), "
                + "height=\(window.frame.height - window.contentLayoutRect.height)")
        }
        let content = try require(window.contentView)
        // The traffic-light gutter must still hit native chrome, not a
        // transparent content-side substitute. The full-height sidebar button
        // legitimately owns its own slot, even above its visible symbol.
        for x: CGFloat in [75] {
            let point = NSPoint(x: x, y: frame.bounds.maxY - 4)
            let hit = try require(frame.hitTest(point))
            guard hit !== content, !hit.isDescendant(of: content), hit.mouseDownCanMoveWindow else {
                throw ProbeFailure("Blank leading titlebar hit \(type(of: hit)); "
                    + "content=\(hit === content || hit.isDescendant(of: content)) "
                    + "movable=\(hit.mouseDownCanMoveWindow)")
            }
        }
        // Keep output paths out of CLI arguments: Cocoa treats them as open requests.
        if let outputPath = ProcessInfo.processInfo.environment["NEATEDITOR_CHROME_OUTPUT"] {
            let png = try require(bitmap.representation(using: .png, properties: [:]))
            var output = URL(fileURLWithPath: outputPath)
            if arguments.contains("--matrix") {
                output = output.deletingLastPathComponent().appendingPathComponent(
                    "chrome-\(store.preferences.editorTheme.rawValue)-\(isDark)-\(store.preferences.isSidebarVisible)-\(window.frame.width)-\(initialState).png")
            }
            try png.write(to: output)
        }
        print("PASS cached initial=\(initialState) theme=\(store.preferences.editorTheme.rawValue) dark=\(isDark) "
            + "sidebar=\(store.preferences.isSidebarVisible) width=\(window.frame.width) "
            + "key=\(window.isKeyWindow) band=\(peer) nativeToolbarMovable=true")
        fflush(nil)
    }

    private func cleanup() {
        WorkspaceSplitViewController.prepareWindowForTesting = nil
        store.pendingSaveStateTask?.cancel()
        defaults.removePersistentDomain(forName: suite)
        do {
            if FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
            }
        } catch {
            print("Fixture cleanup failed: \(error)")
            exit(1)
        }
    }
}

private func verifyBand(_ bitmap: NSBitmapImageRep, width: CGFloat, dark: Bool) throws -> NSColor {
    let scale = CGFloat(bitmap.pixelsWide) / width
    func color(x: CGFloat, y: CGFloat) throws -> NSColor {
        try require(bitmap.colorAt(x: Int(x * scale), y: Int(y * scale))?.usingColorSpace(.sRGB))
    }
    let peer = try color(x: width - 60, y: 8)
    let luminance = (peer.redComponent + peer.greenComponent + peer.blueComponent) / 3
    guard dark ? luminance < 0.5 : luminance > 0.5 else {
        throw ProbeFailure("Requested appearance did not render: dark=\(dark), band=\(peer)")
    }
    for x: CGFloat in [10, 75, 110] {
        let leading = try color(x: x, y: 8)
        for (actual, expected) in zip(
            [leading.redComponent, leading.greenComponent, leading.blueComponent],
            [peer.redComponent, peer.greenComponent, peer.blueComponent]
        ) where abs(actual - expected) > 1.0 / 255 {
            throw ProbeFailure("Top-left \(leading) differs from tab band \(peer)")
        }
    }
    return peer
}

private struct ProbeFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

private func require<T>(_ value: T?) throws -> T {
    guard let value else { throw ProbeFailure("Required fixture value is missing") }
    return value
}

@main
private enum ChromeProbeEntry {
    static func main() {
        if CommandLine.arguments.contains("--verify-capture") {
            do {
                let path = try require(ProcessInfo.processInfo.environment["NEATEDITOR_CHROME_CAPTURE"])
                let data = try Data(contentsOf: URL(fileURLWithPath: path))
                let bitmap = try require(NSBitmapImageRep(data: data))
                let defaultWidth = CommandLine.arguments.contains("--narrow") ? 470.0 : 900.0
                let width = CGFloat(ProcessInfo.processInfo.environment["NEATEDITOR_CHROME_WIDTH"].flatMap(Double.init) ?? defaultWidth)
                guard width >= 240 else { throw ProbeFailure("Invalid capture width") }
                let peer = try verifyBand(bitmap, width: width, dark: CommandLine.arguments.contains("--dark"))
                print("PASS compositor capture band=\(peer)")
                exit(0)
            } catch {
                print("FAIL compositor capture: \(error)")
                exit(1)
            }
        }
        _ = ChromeProbeApplication.shared
        WorkspaceSplitViewController.prepareWindowForTesting = ChromeProbeState.prepare
        ChromeProbeApp.main()
    }
}
