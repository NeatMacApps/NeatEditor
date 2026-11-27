import AppKit
import SwiftUI

struct EditorSearchBarView: View {
    @Binding var searchState: WorkspaceSearchState
    let theme: EditorTheme
    var interfaceFontSize: InterfaceFontSize = .defaultValue
    let onFindNext: () -> Void
    let onFindPrevious: () -> Void
    let onToggleCaseSensitive: () -> Void
    let onToggleRegex: () -> Void
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var focusInputRequestID = 0

    private var searchFieldFontSize: CGFloat {
        interfaceFontSize.scaledFontSize(from: 12.5)
    }

    private var inputWellHeight: CGFloat {
        max(28, ceil(searchFieldFontSize + 13))
    }

    var body: some View {
        HStack(spacing: 4) {
            inputWell

            HStack(spacing: 2) {
                SearchToggleButton(
                    title: "Aa",
                    isMonospaced: false,
                    fontSize: interfaceFontSize.scaledFontSize(from: 11.5),
                    isOn: searchState.isCaseSensitive,
                    accessibilityLabel: "search.caseSensitive",
                    accessibilityIdentifier: "search.caseSensitive",
                    action: onToggleCaseSensitive
                )

                SearchToggleButton(
                    title: ".*",
                    isMonospaced: true,
                    fontSize: interfaceFontSize.scaledFontSize(from: 11.5),
                    isOn: searchState.isRegexEnabled,
                    accessibilityLabel: "search.regex",
                    accessibilityIdentifier: "search.regex",
                    action: onToggleRegex
                )
            }

            Rectangle()
                .fill(EditorChrome.tabOutline)
                .frame(width: 1, height: 16)
                .padding(.horizontal, 1)

            HStack(spacing: 2) {
                SearchIconButton(
                    systemImage: "chevron.up",
                    isDisabled: !searchState.hasMatches,
                    accessibilityLabel: "search.previous",
                    accessibilityIdentifier: "search.previous",
                    action: onFindPrevious
                )

                SearchIconButton(
                    systemImage: "chevron.down",
                    isDisabled: !searchState.hasMatches,
                    accessibilityLabel: "search.next",
                    accessibilityIdentifier: "search.next",
                    action: onFindNext
                )

                SearchIconButton(
                    systemImage: "xmark",
                    isDisabled: false,
                    accessibilityLabel: "Close Search",
                    accessibilityIdentifier: "search.close",
                    action: onDismiss
                )
            }
        }
        .padding(4)
        .frame(height: inputWellHeight + 8)
        .frame(maxWidth: 420)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(EditorChrome.tabBarBackground(for: theme))
                .shadow(
                    color: .black.opacity(colorScheme == .dark ? 0.36 : 0.12),
                    radius: 10,
                    x: 0,
                    y: 3
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(EditorChrome.tabOutline, lineWidth: EditorChrome.lineWidth)
        }
        .focusEffectDisabled()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("search.bar")
    }

    private var inputWell: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            SearchTextField(
                text: $searchState.query,
                fontSize: searchFieldFontSize,
                focusRequestID: searchState.focusRequestID + focusInputRequestID,
                onFindNext: onFindNext,
                onFindPrevious: onFindPrevious,
                onDismiss: onDismiss
            )
            .fixedSize(horizontal: false, vertical: true)
            .frame(minWidth: 48, maxWidth: .infinity)

            if searchState.hasQuery {
                statusIndicator
                    .fixedSize()
                    .accessibilityIdentifier("search.status")

                Button {
                    searchState.query = ""
                    focusInputRequestID += 1
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .help(Text("search.clear"))
                .accessibilityLabel(Text("search.clear"))
                .accessibilityIdentifier("search.clear")
            }
        }
        .padding(.horizontal, 7)
        .frame(height: inputWellHeight)
        .background(
            EditorChrome.editorSurface(for: theme),
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(EditorChrome.tabOutline, lineWidth: EditorChrome.lineWidth)
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        let statusFontSize = interfaceFontSize.scaledFontSize(from: 11)
        switch searchState.status {
        case .idle:
            EmptyView()
        case .matches(let current, let total):
            Text(verbatim: "\(current)/\(total)")
                .font(.system(size: statusFontSize))
                .monospacedDigit()
                .foregroundStyle(total == 0 ? Color(nsColor: .systemRed) : .secondary)
        case .invalidRegularExpression:
            Text("search.status.invalidRegex")
                .font(.system(size: statusFontSize))
                .foregroundStyle(.orange)
                .help(Text("search.status.invalidRegex.help"))
        case .timedOut:
            Text("search.status.regexTimedOut")
                .font(.system(size: statusFontSize))
                .foregroundStyle(.orange)
        }
    }
}

private struct SearchToggleButton: View {
    let title: String
    let isMonospaced: Bool
    let fontSize: CGFloat
    let isOn: Bool
    let accessibilityLabel: LocalizedStringKey
    let accessibilityIdentifier: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(
                    isMonospaced
                        ? .system(size: fontSize, weight: .medium, design: .monospaced)
                        : .system(size: fontSize, weight: .medium)
                )
                .foregroundStyle(isOn ? Color.accentColor : .secondary)
                .frame(width: 26, height: 26)
                .background(
                    backgroundColor,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(Text(accessibilityLabel))
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var backgroundColor: Color {
        if isOn {
            return Color.accentColor.opacity(0.16)
        }
        if isHovered {
            return EditorChrome.hoverFill
        }
        return .clear
    }
}

private struct SearchIconButton: View {
    let systemImage: String
    let isDisabled: Bool
    let accessibilityLabel: LocalizedStringKey
    let accessibilityIdentifier: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(foregroundStyle)
                .frame(width: 24, height: 26)
                .background(
                    !isDisabled && isHovered ? EditorChrome.hoverFill : .clear,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { isHovered = $0 }
        .help(Text(accessibilityLabel))
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var foregroundStyle: AnyShapeStyle {
        if isDisabled {
            return AnyShapeStyle(.tertiary)
        }
        if isHovered {
            return AnyShapeStyle(.primary)
        }
        return AnyShapeStyle(.secondary)
    }
}

private struct SearchTextField: NSViewRepresentable {
    @Binding var text: String
    let fontSize: CGFloat
    let focusRequestID: Int
    let onFindNext: () -> Void
    let onFindPrevious: () -> Void
    let onDismiss: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.delegate = context.coordinator
        field.isBordered = false
        field.drawsBackground = false
        field.isBezeled = false
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingTail
        field.font = .systemFont(ofSize: fontSize)
        field.textColor = .labelColor
        field.placeholderString = String(localized: "Search")
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.setAccessibilityIdentifier("search.field")
        field.setAccessibilityLabel(String(localized: "Search"))
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self

        if field.font?.pointSize != fontSize {
            field.font = .systemFont(ofSize: fontSize)
        }

        let isComposing = (field.currentEditor() as? NSTextView)?.hasMarkedText() == true
        if !isComposing, field.stringValue != text {
            field.stringValue = text
        }

        if context.coordinator.lastHandledFocusRequestID != focusRequestID {
            context.coordinator.lastHandledFocusRequestID = focusRequestID
            Task { @MainActor [weak field] in
                guard let field, let window = field.window else { return }
                window.makeFirstResponder(field)
                field.currentEditor()?.selectAll(nil)
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SearchTextField
        var lastHandledFocusRequestID = -1

        init(parent: SearchTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else {
                return
            }
            if (field.currentEditor() as? NSTextView)?.hasMarkedText() == true {
                return
            }
            let value = field.stringValue
            if parent.text != value {
                parent.text = value
            }
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            guard !textView.hasMarkedText() else {
                return false
            }

            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                    parent.onFindPrevious()
                } else {
                    parent.onFindNext()
                }
                return true
            }

            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onDismiss()
                return true
            }

            return false
        }
    }
}
