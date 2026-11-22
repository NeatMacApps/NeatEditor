import SwiftUI

struct EditorMarkdownModeToggleView: View {
    let capability: MarkdownEditCapability
    let isSourceMode: Bool
    let theme: EditorTheme
    let onSelectMode: (EditorRenderMode) -> Void

    private var renderedTitleKey: LocalizedStringKey {
        capability == .readOnlyPreview ? "markdown.mode.preview" : "markdown.mode.rendered"
    }

    private var selectionBinding: Binding<EditorRenderMode> {
        Binding(
            get: { isSourceMode ? .source : .rendered },
            set: { newMode in
                guard (newMode == .source) != isSourceMode else { return }
                onSelectMode(newMode)
            }
        )
    }

    var body: some View {
        Picker("Toggle Source Mode", selection: selectionBinding) {
            Text(renderedTitleKey)
                .tag(EditorRenderMode.rendered)
            Text("markdown.mode.source")
                .tag(EditorRenderMode.source)
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
        .labelsHidden()
        .fixedSize()
        .focusEffectDisabled()
        .background(
            EditorChrome.editorSurface(for: theme).opacity(0.92),
            in: Capsule()
        )
        .accessibilityIdentifier("editor.markdownModeToggle")
    }
}
