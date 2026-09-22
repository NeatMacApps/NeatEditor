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
        context.coordinator.sync.notePushedText(text, for: tabID)
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

        return containerView
    }

    func updateNSView(_ containerView: EditorTextContainerView, context: Context) {
        let coordinator = context.coordinator
        let textView = containerView.textView

        // A tab switch reuses this view for a different binding. Flush any
        // in-flight IME composition to the OLD tab first (the coordinator
        // still points at it here); otherwise the composition lands in the
        // newly selected tab. Also drop the previous tab's undo history: the
        // text view carries a single shared undo stack, and replaying another
        // tab's edits into this buffer deletes seemingly unrelated lines.
        if coordinator.sync.boundTabID != tabID {
            if textView.hasMarkedText() {
                textView.unmarkText()
            }
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
            hasMarkedText: textView.hasMarkedText()
        ) {
        case .keepTextView:
            break
        case .pushToTextView(let newText):
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

        init(parent: EditorTextView) {
            self.parent = parent
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
