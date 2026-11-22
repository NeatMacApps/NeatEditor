import AppKit
import SwiftUI

/// Keeps the window title on the document that is actually showing.
///
/// The scene declares one constant title, so Mission Control, the Window menu,
/// window restoration and every accessibility client see "NeatEditor" for all
/// documents. The visible title stays hidden; this only owns the window's
/// title string.
struct WindowTitleSyncView: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> WindowTitleHostingView {
        WindowTitleHostingView(title: title)
    }

    func updateNSView(_ nsView: WindowTitleHostingView, context: Context) {
        nsView.title = title
    }
}

final class WindowTitleHostingView: NSView {
    var title: String {
        didSet {
            guard title != oldValue else { return }
            apply()
        }
    }

    init(title: String) {
        self.title = title
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        apply()
    }

    private func apply() {
        guard let window, !title.isEmpty, window.title != title else { return }
        window.title = title
    }
}
