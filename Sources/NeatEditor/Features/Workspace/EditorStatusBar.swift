import SwiftUI

struct EditorStatusBar: View {
    let snapshot: EditorStatusSnapshot?
    let fontSize: CGFloat
    let onIncreaseFontSize: () -> Void
    let onDecreaseFontSize: () -> Void
    let onResetFontSize: () -> Void
    @State private var showsStatistics = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(showsLines: true, showsFont: true)
            row(showsLines: false, showsFont: true)
            row(showsLines: false, showsFont: false)
        }
        .font(.system(size: 11))
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .frame(height: 26)
        .background(EditorChrome.editorSurface)
        .focusEffectDisabled()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("status.bar"))
    }

    private func row(showsLines: Bool, showsFont: Bool) -> some View {
        HStack(spacing: 16) {
            HStack(spacing: 8) {
                Button {
                    showsStatistics = true
                } label: {
                    Text(characterLabel)
                }
                .buttonStyle(.plain)
                .disabled(snapshot == nil)
                .help(Text("status.statistics"))
                .accessibilityLabel(Text("status.statistics"))
                .accessibilityValue(characterLabel)
                .popover(isPresented: $showsStatistics) {
                    statistics
                }

                if showsLines, let snapshot {
                    Text("·").accessibilityHidden(true)
                    Text(format("status.lines", snapshot.lines))
                }
            }
            .fixedSize()

            Spacer(minLength: 8)

            Text(positionLabel)
                .fixedSize()

            if showsFont {
                fontMenu.fixedSize()
            }
        }
    }

    private var characterLabel: String {
        guard let snapshot else { return "…" }
        if snapshot.selectedCharacters > 0 {
            return format("status.selection", snapshot.selectedCharacters, snapshot.characters)
        }
        return format("status.characters", snapshot.characters)
    }

    private var positionLabel: String {
        guard let snapshot else { return "…" }
        return format("status.position", snapshot.line, snapshot.column)
    }

    private var fontMenu: some View {
        Menu {
            Button("Zoom In", action: onIncreaseFontSize)
                .disabled(fontSize >= 36)
            Button("Zoom Out", action: onDecreaseFontSize)
                .disabled(fontSize <= 10)
            Divider()
            Button("status.defaultFontSize", action: onResetFontSize)
        } label: {
            Text(String(format: String(localized: "status.fontSize"), fontSize.formatted()))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)
        .accessibilityLabel(Text("status.font"))
        .accessibilityValue(fontSize.formatted())
        .help(Text("status.font"))
    }

    private var statistics: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("status.statistics").font(.headline)
            if let snapshot {
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                    statistic("status.totalCharacters", value: snapshot.characters)
                    statistic("status.nonWhitespaceCharacters", value: snapshot.nonWhitespaceCharacters)
                    statistic("status.words", value: snapshot.words)
                    statistic("status.totalLines", value: snapshot.lines)
                    if snapshot.selectedCharacters > 0 {
                        statistic("status.selectedCharacters", value: snapshot.selectedCharacters)
                    }
                }
            }
            HStack {
                Spacer()
                Button("status.done") { showsStatistics = false }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .font(.system(size: 12))
        .monospacedDigit()
        .padding(16)
        .focusEffectDisabled()
    }

    private func statistic(_ key: LocalizedStringKey, value: Int) -> some View {
        GridRow {
            Text(key).foregroundStyle(.secondary)
            Text(value.formatted()).gridColumnAlignment(.trailing)
        }
    }

    private func format(_ key: String, _ values: Int...) -> String {
        String(format: NSLocalizedString(key, comment: "Editor status bar"),
               arguments: values.map { $0.formatted() })
    }
}
