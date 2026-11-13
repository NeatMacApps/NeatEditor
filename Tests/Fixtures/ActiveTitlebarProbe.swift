import AppKit
import SwiftUI

@testable import NeatEditor

/// A standalone native control: unlike the SwiftUI scene fixture, this reproduces
/// the active native titlebar's white cap. Public application/window getters are
/// overridden for deterministic rendering under lock; physical input is not proven.
private final class ActiveTitlebarApplication: NSApplication {
    override var isActive: Bool { true }
}

private final class ActiveTitlebarWindow: NSWindow {
    override var isKeyWindow: Bool { true }
    override var isMainWindow: Bool { true }
}

@main
private enum ActiveTitlebarProbe {
    @MainActor
    static func main() {
        let arguments = CommandLine.arguments
        let app = ActiveTitlebarApplication.shared
        let dark = arguments.contains("--dark")
        app.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let theme: EditorTheme = arguments.contains("--neutral") ? .whiteBlack : .warm
        let tab = EditorTabDescriptor(id: UUID(), title: "Titlebar test.txt")
        let configuration = WorkspaceSplitView(
            sidebar: AnyView(Color(nsColor: EditorChrome.tabBarBackgroundColor(for: theme))),
            detail: AnyView(Color(nsColor: EditorChrome.editorSurfaceColor(for: theme))),
            tabs: [tab], selectedTabID: tab.id, tabActions: EditorTabActions(),
            isSidebarVisible: arguments.contains("--sidebar"),
            isSettingsSelected: false, isWindowPinned: false,
            onSidebarVisibilityChange: { _ in }, onTogglePin: {}, theme: theme
        )
        let width: CGFloat = arguments.contains("--narrow") ? 470 : 900
        let window = ActiveTitlebarWindow(
            contentRect: NSRect(x: 100, y: 100, width: width, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.title = "Active Titlebar Probe"
        window.isReleasedWhenClosed = false
        window.appearance = app.appearance
        let controller = WorkspaceSplitViewController(configuration: configuration)
        window.contentViewController = controller
        // Initial sizing, before ordering/display. No post-display resize, sidebar
        // toggle, forced display or cache drawing is permitted in the cold probe.
        window.setContentSize(NSSize(width: width, height: 500))
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard let content = window.contentView, let root = content.superview,
                  let sidebar = window.titlebarAccessoryViewControllers.first(where: { $0.layoutAttribute == .leading })?.view as? NSButton,
                  let close = window.standardWindowButton(.closeButton) else {
                fatalError("Native titlebar controls are missing")
            }
            for button in [sidebar, close] {
                let point = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: root)
                guard root.hitTest(point) === button else { fatalError("Native button hit changed") }
            }
            for x: CGFloat in [75, 16] {
                let point = NSPoint(x: x, y: window.frame.height - 3)
                guard let hit = root.hitTest(root.convert(point, from: nil)),
                      hit !== content, !hit.isDescendant(of: content) else {
                    fatalError("Native blank titlebar routing changed")
                }
            }
            guard !window.titlebarAppearsTransparent, window.toolbar?.isVisible == true,
                  window.toolbar?.items.isEmpty == true,
                  window.toolbarStyle == .unifiedCompact,
                  window.frame.height - window.contentLayoutRect.height == EditorTabLayout.stripHeight else {
                fatalError("Native compact titlebar contract changed")
            }
            print("NATIVE READY theme=\(theme.rawValue) dark=\(dark) sidebar=\(arguments.contains("--sidebar")) "
                + "width=\(window.frame.width) active=\(app.isActive) key=\(window.isKeyWindow) nativeHits=true")
            fflush(nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { app.terminate(nil) }
        app.run()
        withExtendedLifetime((window, controller)) {}
    }
}
