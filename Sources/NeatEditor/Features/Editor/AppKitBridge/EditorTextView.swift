import AppKit
import Foundation
import SwiftUI

struct EditorTextView: NSViewRepresentable {
    let tabID: UUID
    @Binding var text: String
    let fontSize: CGFloat
    let isEditable: Bool
    let tabBehavior: TabBehavior
    let textSoftness: WorkspacePreferences.EditorTextSoftnessConfiguration
    let searchState: WorkspaceSearchState

    let onTextChange: (_ isComposing: Bool) -> Void
    let onCompositionEnd: () -> Void
    let onIncreaseFontSize: () -> Void
    let onDecreaseFontSize: () -> Void
    let onOpenFiles: ([URL]) -> Void
    let onRegisterCommitHandler: (@escaping @MainActor (UUID) -> Void) -> Void
    var externalRevision: UInt64 = 0
    var onCharacterCountChange: (UUID, String) -> Void = { _, _ in }
    var onRegisterCompositionCheck: (@escaping @MainActor (UUID) -> Bool) -> Void = { _ in }
    var onRegisterExternalChangeHandler: (@escaping @MainActor (UUID, String, UInt64) -> Void) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> EditorTextContainerView {
        let containerView = EditorTextContainerView(
            onIncreaseFontSize: onIncreaseFontSize,
            onDecreaseFontSize: onDecreaseFontSize
        )
        let textView = containerView.textView

        textView.delegate = context.coordinator
        textView.string = text
        textView.isEditable = isEditable
        context.coordinator.sync.notePushedText(text, for: tabID, externalRevision: externalRevision)
        containerView.synchronizeLineNumbersToCurrentText()
        textView.onOpenFiles = onOpenFiles
        textView.tabBehavior = tabBehavior
        containerView.textSoftness = textSoftness
        containerView.applyEditorTextAttributes()
        textView.onCompositionEnd = {
            [weak containerView, weak coordinator = context.coordinator, weak textView] in
            guard let containerView, let coordinator, let textView else {
                return
            }

            coordinator.handleCompositionEnd(in: textView, containerView: containerView)
        }
        containerView.applyFontSize(fontSize)

        context.coordinator.registerCommitHandler(for: textView)
        context.coordinator.scheduleCharacterCountReport(for: textView)

        return containerView
    }

    func updateNSView(_ containerView: EditorTextContainerView, context: Context) {
        let coordinator = context.coordinator
        let textView = containerView.textView
        var needsCharacterCountReport = coordinator.parent.tabID != tabID || coordinator.parent.isEditable != isEditable

        // A tab switch reuses this view for a different binding. Uncommitted
        // IME text (e.g. pinyin awaiting a candidate) is not document content,
        // so discard it instead of committing it into either tab. Also drop
        // the previous tab's undo history: the text view carries a single
        // shared undo stack, and replaying another tab's edits into this
        // buffer deletes seemingly unrelated lines.
        if coordinator.sync.boundTabID != tabID {
            coordinator.discardComposition(in: textView)
            textView.breakUndoCoalescing()
            textView.undoManager?.removeAllActions()
            containerView.clearSearchHighlights()
        }

        coordinator.parent = self
        containerView.onIncreaseFontSize = onIncreaseFontSize
        containerView.onDecreaseFontSize = onDecreaseFontSize
        containerView.textView.onOpenFiles = onOpenFiles
        containerView.textView.tabBehavior = tabBehavior
        containerView.textSoftness = textSoftness
        containerView.textView.isEditable = isEditable

        switch coordinator.sync.update(
            for: tabID,
            text: text,
            hasMarkedText: textView.hasMarkedText(),
            externalRevision: externalRevision
        ) {
        case .keepTextView:
            break
        case .pushToTextView(let newText):
            needsCharacterCountReport = true
            coordinator.isSyncingFromSwiftUI = true
            textView.string = newText
            coordinator.isSyncingFromSwiftUI = false
            textView.breakUndoCoalescing()
            containerView.synchronizeLineNumbersToCurrentText()
            containerView.applyEditorTextAttributes()
            coordinator.syncSearchTrackingAfterPush(searchState)
            containerView.reapplySearchHighlightsIfNeeded(
                query: searchState.trimmedQuery,
                usesRegularExpression: searchState.isRegexEnabled,
                isPresented: searchState.isPresented
            )
        }

        if needsCharacterCountReport {
            coordinator.scheduleCharacterCountReport(for: textView)
        }

        containerView.applyFontSize(fontSize)
        // Color/typing-attribute upkeep is driven by textSoftness didSet and
        // viewDidChangeEffectiveAppearance; repeating it on every SwiftUI
        // redraw was the dominant CPU source during long sessions.

        let query = searchState.trimmedQuery
        let isRegex = searchState.isRegexEnabled
        let isPresented = searchState.isPresented

        if coordinator.lastSearchWasPresented && !isPresented {
            containerView.clearSearchHighlights()
        }

        coordinator.lastSearchWasPresented = isPresented

        if isPresented {
            let requestChanged = coordinator.lastSearchRequestID != searchState.requestID
            let queryChanged = coordinator.lastAppliedSearchQuery != query
            let regexChanged = coordinator.lastAppliedIsRegex != isRegex

            if requestChanged || queryChanged || regexChanged {
                coordinator.lastSearchRequestID = searchState.requestID
                coordinator.lastAppliedSearchQuery = query
                coordinator.lastAppliedIsRegex = isRegex
                containerView.performSearch(
                    for: query,
                    usesRegularExpression: isRegex,
                    navigate: requestChanged
                )
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: EditorTextView
        var sync = EditorTextSyncState()
        var isSyncingFromSwiftUI = false
        var lastSearchRequestID = 0
        var lastAppliedSearchQuery = ""
        var lastAppliedIsRegex = false
        var lastSearchWasPresented = false
        private var pendingCharacterCountReport: Task<Void, Never>?

        init(parent: EditorTextView) {
            self.parent = parent
        }

        func registerCommitHandler(for textView: ZoomableTextView) {
            parent.onRegisterCompositionCheck { [weak self, weak textView] id in
                self?.sync.boundTabID == id && (textView?.hasMarkedText() ?? false)
            }
            parent.onRegisterExternalChangeHandler { [weak self, weak textView] id, text, revision in
                guard let self, let textView, self.sync.boundTabID == id,
                      !textView.hasMarkedText() else { return }
                self.applyExternalText(text, revision: revision, to: textView)
            }
            parent.onRegisterCommitHandler { [weak self, weak textView] id in
                // While composing, the binding already holds the committed
                // text; forcing a commit here would save raw pinyin and leave
                // the input method composing a buffer it no longer owns.
                guard let self, let textView, textView.isEditable,
                      sync.boundTabID == id, !textView.hasMarkedText() else { return }
                if textView.string != sync.lastKnownText {
                    reportAppKitText(textView.string)
                }
            }
        }

        /// Apply external content immediately on the same actor as edits, not
        /// through a delayed binding snapshot. AppKit's editing notifications
        /// and text storage retain native undo instead of simulating user input.
        func applyExternalText(_ text: String, revision: UInt64, to textView: NSTextView) {
            guard let container = textView.enclosingScrollView?.superview as? EditorTextContainerView,
                  !textView.hasMarkedText(), textView.string != text else { return }
            let old = Array(textView.string.utf16)
            let new = Array(text.utf16)
            let prefix = zip(old, new).prefix(while: { $0 == $1 }).count
            let suffix = zip(old.dropFirst(prefix).reversed(), new.dropFirst(prefix).reversed())
                .prefix(while: { $0 == $1 }).count
            func map(_ offset: Int) -> Int {
                if offset <= prefix { return offset }
                if offset >= old.count - suffix { return max(0, offset + new.count - old.count) }
                return min(offset, new.count - suffix)
            }
            let selections = textView.selectedRanges.map { value in
                let range = value.rangeValue
                let start = map(range.location)
                return NSValue(range: NSRange(location: start, length: max(0, map(NSMaxRange(range)) - start)))
            }
            let origin = textView.enclosingScrollView?.contentView.bounds.origin
            textView.breakUndoCoalescing()
            isSyncingFromSwiftUI = true
            let replacementRange = NSRange(location: 0, length: old.count)
            if textView.shouldChangeText(in: replacementRange, replacementString: text) {
                textView.textStorage?.replaceCharacters(in: replacementRange, with: text)
                textView.didChangeText()
            }
            isSyncingFromSwiftUI = false
            textView.breakUndoCoalescing()
            textView.undoManager?.setActionName(String(localized: "External Changes"))
            textView.selectedRanges = selections
            if let origin { textView.enclosingScrollView?.contentView.scroll(to: origin) }
            sync.notePushedText(text, for: sync.boundTabID ?? parent.tabID, externalRevision: revision)
            container.synchronizeLineNumbersToCurrentText()
            container.applyEditorTextAttributes()
            container.reapplySearchHighlightsIfNeeded(query: lastAppliedSearchQuery,
                usesRegularExpression: lastAppliedIsRegex, isPresented: lastSearchWasPresented)
            scheduleCharacterCountReport(for: textView)
        }

        /// Ends an in-flight composition without committing it anywhere:
        /// the input method is told to drop its state, and any marked
        /// characters left in the view are released silently so the next
        /// push replaces them.
        func discardComposition(in textView: NSTextView) {
            guard textView.hasMarkedText() else { return }
            isSyncingFromSwiftUI = true
            defer { isSyncingFromSwiftUI = false }
            textView.inputContext?.discardMarkedText()
            if textView.hasMarkedText() {
                textView.unmarkText()
            }
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            guard let containerView = textView.enclosingScrollView?.superview as? EditorTextContainerView else {
                return true
            }

            containerView.prepareTypingAttributes(for: replacementString)
            return true
        }

        /// Defer observation writes until after NSViewRepresentable's update, and
        /// report the live buffer only when the queued update still owns this tab.
        func scheduleCharacterCountReport(for textView: NSTextView) {
            pendingCharacterCountReport?.cancel()
            let tabID = parent.tabID
            pendingCharacterCountReport = Task { @MainActor [weak self, weak textView] in
                guard !Task.isCancelled, let self, let textView,
                      parent.tabID == tabID, sync.boundTabID == tabID,
                      textView.isEditable, !textView.hasMarkedText() else { return }
                parent.onCharacterCountChange(tabID, textView.string)
            }
        }

        func textDidChange(_ notification: Notification) {
            guard !isSyncingFromSwiftUI,
                  let textView = notification.object as? NSTextView,
                  let containerView = textView.enclosingScrollView?.superview as? EditorTextContainerView else {
                return
            }

            let isComposing = textView.hasMarkedText()
            if !isComposing {
                reportAppKitText(textView.string)
                // Edits shift match ranges, so refresh the visible highlights
                // without moving the selection.
                containerView.reapplySearchHighlightsIfNeeded(
                    query: lastAppliedSearchQuery,
                    usesRegularExpression: lastAppliedIsRegex,
                    isPresented: lastSearchWasPresented
                )
            }

            scheduleCharacterCountReport(for: textView)
            parent.onTextChange(isComposing)
            containerView.refreshLineNumbers()
        }

        func handleCompositionEnd(in textView: NSTextView, containerView: EditorTextContainerView) {
            guard !isSyncingFromSwiftUI else {
                return
            }

            reportAppKitText(textView.string)
            containerView.reapplySearchHighlightsIfNeeded(
                query: lastAppliedSearchQuery,
                usesRegularExpression: lastAppliedIsRegex,
                isPresented: lastSearchWasPresented
            )
            containerView.applyEditorTextAttributes()
            scheduleCharacterCountReport(for: textView)
            parent.onCompositionEnd()
        }

        /// Forward a string that originated in the text view to the SwiftUI
        /// binding and record the agreement, so the next `updateNSView` echo
        /// does not push it back and clobber newer keystrokes.
        func reportAppKitText(_ string: String) {
            parent.text = string
            sync.noteTextViewContent(string, for: sync.boundTabID ?? parent.tabID)
        }

        /// After a programmatic push, align the search tracking with the
        /// current request so the block in `updateNSView` does not navigate
        /// again; highlights are re-applied without moving the selection.
        func syncSearchTrackingAfterPush(_ searchState: WorkspaceSearchState) {
            lastSearchWasPresented = searchState.isPresented
            lastAppliedSearchQuery = searchState.trimmedQuery
            lastAppliedIsRegex = searchState.isRegexEnabled
            lastSearchRequestID = searchState.requestID
        }
    }
}
