import AppKit
import SwiftUI

/// Reports a SwiftUI view's frame in its window's base coordinate space.
///
/// SwiftUI's `.global` space is not shared between view hierarchies hosted in
/// different AppKit containers (the toolbar tab strip and the split view's
/// editor column each reported a different origin), so cross-hierarchy geometry
/// must be compared in AppKit window coordinates instead.
struct ViewWindowFrameReader: NSViewRepresentable {
    let onChange: (CGRect) -> Void

    func makeNSView(context: Context) -> ReportingView {
        let view = ReportingView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: ReportingView, context: Context) {
        nsView.onChange = onChange
        nsView.report()
    }

    final class ReportingView: NSView {
        var onChange: ((CGRect) -> Void)?
        private var lastReportedFrame: CGRect = .null

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            report()
        }

        override func layout() {
            super.layout()
            report()
        }

        func report() {
            guard window != nil else {
                return
            }
            let frame = convert(bounds, to: nil)
            guard frame != lastReportedFrame else {
                return
            }
            lastReportedFrame = frame
            // Layout runs inside SwiftUI's update pass; publish on the next
            // turn so this cannot mutate state while the view is rendering.
            DispatchQueue.main.async { [weak self] in
                self?.onChange?(frame)
            }
        }
    }
}
