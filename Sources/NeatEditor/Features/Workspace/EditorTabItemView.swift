import AppKit

/// Product-owned stepped tab; the native field, fill and outline share one frame.
final class EditorTabItemView: NSControl, NSTextFieldDelegate {
    let id: UUID
    weak var strip: EditorTabStripView?
    private(set) var descriptor: EditorTabDescriptor
    let titleField = NSTextField(labelWithString: "")
    private var isSelected = false

    var tabBounds: CGRect {
        CGRect(x: ConnectedTabGeometry.baselineOutset, y: 0,
               width: max(0, bounds.width - 2 * ConnectedTabGeometry.baselineOutset),
               height: EditorTabLayout.tabHeight)
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(descriptor: EditorTabDescriptor) {
        id = descriptor.id
        self.descriptor = descriptor
        super.init(frame: .zero)
        focusRingType = .none
        titleField.isBordered = false
        titleField.drawsBackground = false
        titleField.focusRingType = .none
        titleField.alignment = .center
        titleField.lineBreakMode = .byTruncatingTail
        titleField.usesSingleLineMode = true
        titleField.delegate = self
        titleField.setAccessibilityElement(false)
        addSubview(titleField)
        setAccessibilityElement(true)
        setAccessibilityRole(.radioButton)
        setAccessibilityIdentifier("document-tab-\(id)")
        update(descriptor: descriptor, selected: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(descriptor: EditorTabDescriptor, selected: Bool) {
        self.descriptor = descriptor
        isSelected = selected
        if strip?.editingTabID != id { titleField.stringValue = descriptor.title }
        titleField.font = .systemFont(ofSize: EditorTabLayout.titleFontSize)
        titleField.textColor = selected ? .labelColor : .secondaryLabelColor
        setAccessibilityLabel(descriptor.title)
        setAccessibilityValue(selected ? 1 : 0)
        toolTip = descriptor.title
        needsLayout = true
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        let rect = tabBounds
        let titleHeight = ceil(titleField.intrinsicContentSize.height)
        titleField.frame = CGRect(x: rect.minX + EditorTabLayout.horizontalPadding,
                                  y: EditorTabLayout.tabTitleCenterY - titleHeight / 2,
                                  width: max(0, rect.width - 2 * EditorTabLayout.horizontalPadding),
                                  height: titleHeight)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        // Whether the titlebar clips below the band varies with window state;
        // the outline's lowest row always belongs to the editor's top rule.
        context.clip(to: CGRect(x: 0, y: 0, width: bounds.width, height: EditorTabLayout.tabHeight))
        if isSelected {
            context.addPath(ConnectedTabGeometry.fill(in: tabBounds))
            context.setFillColor(EditorChrome.editorSurfaceColor.cgColor)
            context.fillPath()
            context.addPath(ConnectedTabGeometry.outline(in: tabBounds))
            context.setStrokeColor(EditorChrome.tabOutlineColor.cgColor)
            context.setLineWidth(EditorChrome.lineWidth)
            context.strokePath()
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        if strip?.editingTabID == id { return hit }
        return hit == nil ? nil : self
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        strip?.trackPointer(event, tabID: id)
    }

    override func otherMouseUp(with event: NSEvent) {
        if event.buttonNumber == 2 { strip?.actions.onClose(id) }
        else { super.otherMouseUp(with: event) }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        strip?.contextMenu(for: descriptor)
    }

    override func accessibilityPerformPress() -> Bool {
        strip?.selectTab(id)
        return strip != nil
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 123 { strip?.actions.onSelectRelative(-1) }
        else if event.keyCode == 124 { strip?.actions.onSelectRelative(1) }
        else if event.keyCode == 49 || event.keyCode == 36 { strip?.selectTab(id) }
        else { super.keyDown(with: event) }
    }

    func setEditing(_ editing: Bool) {
        titleField.isEditable = editing
        titleField.isSelectable = editing
        titleField.setAccessibilityElement(editing)
        if editing {
            titleField.stringValue = descriptor.title
            window?.makeFirstResponder(titleField)
            titleField.currentEditor()?.selectedRange = NSRange(
                location: 0, length: titleField.stringValue.utf16.count
            )
        } else {
            titleField.abortEditing()
            titleField.stringValue = descriptor.title
        }
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard strip?.editingTabID == id else { return }
        strip?.finishRename(commit: true)
    }

    func control(_ control: NSControl, textView: NSTextView,
                 doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            strip?.finishRename(commit: false)
            return true
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            strip?.finishRename(commit: true)
            return true
        }
        return false
    }
}
