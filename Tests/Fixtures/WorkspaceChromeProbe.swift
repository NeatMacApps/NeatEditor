import AppKit
import SwiftUI

@testable import NeatEditor

/// Exercises scene-owned toolbar preferences, which NSHostingController alone
/// cannot apply. Active application drawing is simulated; this is not an
/// unlocked, key-window interaction or WindowServer capture acceptance.
private final class ChromeProbeApplication: NSApplication {
    override var isActive: Bool { true }
}

private struct ChromeProbeApp: App {
    private let store: WorkspaceStore
    private let directory: URL
    private let defaults: UserDefaults
    private let suite: String
    private let arguments = ProcessInfo.processInfo.arguments
    @State private var isDark = false

    init() {
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
                        if arguments.contains("--matrix") {
                            for theme in EditorTheme.allCases {
                                for dark in [false, true] {
                                    for sidebar in [false, true] {
                                        for narrow in [false, true] {
                                            store.preferences.editorTheme = theme
                                            store.preferences.isSidebarVisible = sidebar
                                            try await verify(dark: dark, narrow: narrow)
                                        }
                                    }
                                }
                            }
                        } else {
                            try await verify(dark: arguments.contains("--dark"),
                                             narrow: arguments.contains("--narrow"))
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
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.presented)
        .defaultSize(width: arguments.contains("--narrow") ? 470 : 900, height: 500)
    }

    @MainActor
    private func verify(dark: Bool, narrow: Bool) async throws {
        try await Task.sleep(for: .milliseconds(100))
        let window = try require(NSApplication.shared.windows.first { $0.title == "Workspace Chrome Probe" })
        isDark = dark
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.setContentSize(CGSize(width: narrow ? 470 : 900, height: 500))
        try await Task.sleep(for: .milliseconds(200))
        window.layoutIfNeeded()
        let frame = try require(window.contentView?.superview)
        frame.layoutSubtreeIfNeeded()
        let bitmap = try require(frame.bitmapImageRepForCachingDisplay(in: frame.bounds))
        frame.cacheDisplay(in: frame.bounds, to: bitmap)
        let scale = CGFloat(bitmap.pixelsWide) / frame.bounds.width
        func color(x: CGFloat, y: CGFloat) throws -> NSColor {
            try require(bitmap.colorAt(x: Int(x * scale), y: Int(y * scale))?.usingColorSpace(.sRGB))
        }
        let peer = try color(x: frame.bounds.width - 60, y: 8)
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
        guard !window.titlebarAppearsTransparent, window.toolbarStyle == .unifiedCompact,
              window.toolbar?.items.isEmpty == true,
              abs(window.frame.height - window.contentLayoutRect.height - EditorTabLayout.stripHeight) < 0.5 else {
            throw ProbeFailure("Native compact opaque toolbar was not preserved: "
                + "transparent=\(window.titlebarAppearsTransparent), style=\(window.toolbarStyle.rawValue), "
                + "height=\(window.frame.height - window.contentLayoutRect.height), "
                + "items=\(String(describing: window.toolbar?.items.count))")
        }
        let point = NSPoint(x: 75, y: frame.bounds.maxY - 4)
        let hit = try require(frame.hitTest(point))
        let content = try require(window.contentView)
        guard hit !== content, !hit.isDescendant(of: content) else {
            throw ProbeFailure("Blank traffic-light region routes into content")
        }
        // Cocoa can interpret a bare CLI output path as a document-open request
        // and suppress the initial Window scene. Keep paths out of launch arguments.
        if let outputPath = ProcessInfo.processInfo.environment["NEATEDITOR_CHROME_OUTPUT"] {
            let png = try require(bitmap.representation(using: .png, properties: [:]))
            var output = URL(fileURLWithPath: outputPath)
            if arguments.contains("--matrix") {
                output = output.deletingLastPathComponent().appendingPathComponent(
                    "chrome-\(store.preferences.editorTheme.rawValue)-\(dark)-\(store.preferences.isSidebarVisible)-\(narrow).png")
            }
            try png.write(to: output)
        }
        print("PASS theme=\(store.preferences.editorTheme.rawValue) dark=\(dark) "
              + "sidebar=\(store.preferences.isSidebarVisible) width=\(window.frame.width) "
              + "band=\(peer) nativeHit=\(type(of: hit))")
        fflush(nil)
    }

    private func cleanup() {
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
        _ = ChromeProbeApplication.shared
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            print("PROBE windows=\(NSApplication.shared.windows.map { ($0.title, $0.isVisible, $0.frame) })")
            fflush(nil)
        }
        ChromeProbeApp.main()
    }
}
