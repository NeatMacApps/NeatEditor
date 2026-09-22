import Foundation

/// Decision state for the `NSTextView` <-> SwiftUI `String` binding.
///
/// The AppKit text view is a single long-lived instance that is reused across
/// tabs (same view identity, different binding), and SwiftUI may deliver a
/// stale `text` snapshot after rapid edits: `textDidChange` reports the new
/// string, SwiftUI re-renders, but a previously scheduled `updateNSView` can
/// still carry the older value. Blindly assigning `textView.string = text`
/// whenever the two differ then clobbers newer in-flight edits — e.g. cut a
/// few lines, keep typing, and unrelated lines appear to vanish.
///
/// The rule enforced here: only push SwiftUI -> AppKit when the binding value
/// changed for a reason *other* than echoing our own AppKit -> SwiftUI report
/// (tracked via `lastKnownText`), or when the bound tab changed. Same-tab
/// echoes never touch the text view, even if the live string already ran
/// ahead of the snapshot SwiftUI handed us.
///
/// This type is pure logic (no AppKit dependency) so the contract is covered
/// by unit tests; the `Coordinator` in `EditorTextView` is a thin adapter.
struct EditorTextSyncState {
    /// Which tab's content the text view currently displays, if known.
    private(set) var boundTabID: UUID?

    /// Last string both sides agreed on.
    private(set) var lastKnownText: String?

    enum Update {
        /// Assign this string to the text view (tab switch or external change).
        case pushToTextView(String)
        /// Leave the text view alone (echo of our own edits / no change).
        case keepTextView
    }

    /// Record a string that originated in the text view
    /// (`textDidChange` / composition end) and was forwarded to SwiftUI.
    mutating func noteTextViewContent(_ string: String, for tabID: UUID) {
        boundTabID = tabID
        lastKnownText = string
    }

    /// Record a string that was just pushed programmatically
    /// (`makeNSView` initial fill / `updateNSView` external push).
    mutating func notePushedText(_ text: String, for tabID: UUID) {
        boundTabID = tabID
        lastKnownText = text
    }

    /// Decide what `updateNSView` should do for the given binding value.
    ///
    /// - Note: on a tab switch the caller must flush in-flight IME
    ///   composition to the *old* binding *before* calling this (while the
    ///   coordinator still points at the old tab), then perform the push.
    mutating func update(for tabID: UUID, text: String, hasMarkedText: Bool) -> Update {
        guard boundTabID == tabID else {
            boundTabID = tabID
            lastKnownText = text
            return .pushToTextView(text)
        }

        guard !hasMarkedText else {
            return .keepTextView
        }

        // `text == lastKnownText` means this update is just the echo of our
        // own AppKit -> SwiftUI report (or nothing changed at all). The live
        // text view may already contain newer keystrokes than this snapshot,
        // so it must not be overwritten.
        guard text != lastKnownText else {
            return .keepTextView
        }

        lastKnownText = text
        return .pushToTextView(text)
    }
}
