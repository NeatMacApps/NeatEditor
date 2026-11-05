import AppKit
import SwiftUI
import Testing

@testable import NeatEditor

/// External reconciliation must only advance the accepted revision when the
/// native replacement actually happened. A lazy tab switch suspends the
/// outgoing editor (`isEditable = false`), and AppKit refuses the replacement
/// during that window.
@MainActor
struct EditorExternalChangeTests {
    @Test("a deferred external change is not recorded as applied")
    func deferredExternalChangeStaysPending() throws {
        let tabID = UUID()
        let container = EditorTextContainerView()
        let textView = container.textView
        textView.string = "BEFORE"
        let (coordinator, deliver) = try makeCoordinator(tabID: tabID, container: container)
        coordinator.sync.notePushedText("BEFORE", for: tabID, externalRevision: 0)
        coordinator.suspendForPendingDocument(in: container)
        #expect(!textView.isEditable)

        // Reconciliation lands while the editor is suspended: AppKit refuses
        // the replacement, so nothing may be recorded as reconciled.
        deliver(tabID, "AFTER", 1)
        #expect(textView.string == "BEFORE")
        #expect(coordinator.sync.appliedExternalRevision == 0)
        #expect(coordinator.sync.boundTabID == tabID)

        // Returning to the tab makes the editor editable. The pending revision
        // is newer than the accepted one, so the existing revision comparison
        // delivers it without a second queue.
        textView.isEditable = true
        let update = coordinator.sync.update(
            for: tabID,
            text: "AFTER",
            hasMarkedText: false,
            externalRevision: 1
        )
        guard case .pushToTextView(let pushed) = update else {
            Issue.record("the deferred external revision must push once editable")
            return
        }
        #expect(pushed == "AFTER")
        textView.string = pushed
        #expect(textView.string == "AFTER")
        #expect(coordinator.sync.appliedExternalRevision == 1)
    }

    @Test("an editable external change applies immediately and advances the revision")
    func editableExternalChangeApplies() throws {
        let tabID = UUID()
        let container = EditorTextContainerView()
        let textView = container.textView
        textView.string = "BEFORE"
        let (coordinator, deliver) = try makeCoordinator(tabID: tabID, container: container)
        coordinator.sync.notePushedText("BEFORE", for: tabID, externalRevision: 0)

        deliver(tabID, "AFTER", 1)
        #expect(textView.string == "AFTER")
        #expect(coordinator.sync.appliedExternalRevision == 1)

        // The accepted revision turns the follow-up SwiftUI echo into a no-op
        // instead of a second replacement.
        let echo = coordinator.sync.update(
            for: tabID,
            text: "AFTER",
            hasMarkedText: false,
            externalRevision: 1
        )
        guard case .keepTextView = echo else {
            Issue.record("the echo of an applied revision must not push again")
            return
        }
    }

    private func makeCoordinator(
        tabID: UUID,
        container: EditorTextContainerView
    ) throws -> (EditorTextView.Coordinator, @MainActor (UUID, String, UInt64) -> Void) {
        var externalHandler: (@MainActor (UUID, String, UInt64) -> Void)?
        var view = EditorTextView(
            tabID: tabID,
            text: .constant(container.textView.string),
            fontSize: 13,
            isEditable: true,
            tabBehavior: .spaces2,
            textSoftness: .init(),
            searchState: WorkspaceSearchState(),
            onTextChange: { _ in },
            onCompositionEnd: {},
            onIncreaseFontSize: {},
            onDecreaseFontSize: {},
            onOpenFiles: { _ in },
            onRegisterCommitHandler: { _ in }
        )
        view.onRegisterExternalChangeHandler = { handler in
            externalHandler = handler
        }
        let coordinator = view.makeCoordinator()
        coordinator.registerCommitHandler(for: container.textView)
        return (coordinator, try #require(externalHandler))
    }
}
