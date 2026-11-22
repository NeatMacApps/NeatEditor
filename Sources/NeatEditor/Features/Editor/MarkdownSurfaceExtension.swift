import Foundation
import SwiftUI

enum EditorRenderMode: Hashable, Sendable {
    case rendered
    case source
}

enum MarkdownEditCapability: Equatable, Sendable {
    case readOnlyPreview
    case fullEditing
}

enum MarkdownFormattingAction: Equatable, Sendable {
    case bold
    case italic
    case underline
    case strikethrough
    case inlineCode
    case highlight
    case link
    case insertImage
    case heading(Int)
    case insertOrAlignTable
    case codeBlock
    case mathBlock
    case blockquote
    case bulletList
    case orderedList
    case taskList
    case horizontalRule
}

struct MarkdownSurfaceConfiguration {
    let tabID: UUID
    let fileURL: URL?
    let title: String
    @Binding var text: String
    let fontSize: CGFloat
    let isContentLoaded: Bool
    let isSourceMode: Bool
    let tabBehavior: TabBehavior
    let textSoftness: WorkspacePreferences.EditorTextSoftnessConfiguration
    let searchState: WorkspaceSearchState
    let theme: EditorTheme
    let externalRevision: UInt64

    let onTextChange: (_ isComposing: Bool) -> Void
    let onCompositionEnd: () -> Void
    let onIncreaseFontSize: () -> Void
    let onDecreaseFontSize: () -> Void
    let onOpenFiles: ([URL]) -> Void
    let onCharacterCountChange: (UUID, String) -> Void
    let onSearchTimeoutChange: (_ isTimedOut: Bool) -> Void
    let onSearchStatusChange: (WorkspaceSearchState.Status) -> Void
    let onDismissSearchFromEditor: () -> Bool
    let onRegisterSurfaceHandlers: (
        _ ownerID: UUID,
        _ commit: @escaping @MainActor (UUID) -> Void,
        _ hasMarkedText: @escaping @MainActor (UUID) -> Bool,
        _ applyExternal: @escaping @MainActor (UUID, String, UInt64) -> Void,
        _ selectedSearchSeed: @escaping @MainActor () -> String?,
        _ focus: @escaping @MainActor () -> Void,
        _ performFormat: @escaping @MainActor (MarkdownFormattingAction) -> Void
    ) -> Void
    let onUnregisterSurfaceHandlers: (_ ownerID: UUID) -> Void
}

@MainActor
protocol MarkdownSurfaceProviding: AnyObject {
    var capability: MarkdownEditCapability { get }
    func makeEditorView(configuration: MarkdownSurfaceConfiguration) -> AnyView
}

@MainActor
enum EditorExtensionRegistry {
    static var markdownProvider: (any MarkdownSurfaceProviding)?
}
