import AppKit

/// Plain scroll view hosting the editor text view.
///
/// Command+scroll / trackpad-gesture font zoom used to live here and was
/// intentionally removed: with Command held for shortcuts, incidental
/// trackpad contact kept changing the font size by accident. Font size is now
/// adjusted only via Command + +/- (see `ZoomableTextView` and the View
/// menu). This subclass remains as the gutter scroll-forwarding target and a
/// seam for future scroll behavior.
final class EditorScrollView: NSScrollView {}
