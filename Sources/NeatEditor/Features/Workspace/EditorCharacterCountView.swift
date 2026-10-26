import SwiftUI

/// Non-interactive count floating over the document editor.
struct EditorCharacterCountView: View {
    let characters: Int

    var body: some View {
        Text(String(format: String(localized: "status.characters"), characters.formatted()))
            .font(.system(size: 11))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize()
            .padding(.trailing, EditorCharacterCountLayout.trailingInset)
            .padding(.bottom, EditorCharacterCountLayout.bottomInset)
            .allowsHitTesting(false)
    }
}
