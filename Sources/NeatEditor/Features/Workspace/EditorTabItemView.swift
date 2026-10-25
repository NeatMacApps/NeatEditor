import AppKit

/// Product-owned stepped tab; the native field, fill and outline share one frame.
final class EditorTabItemView: NSControl, NSTextFieldDelegate {
    let id: UUID
    weak var strip: EditorTabStripView?
    private(set) var descriptor: EditorTabDescriptor
    let titleField = NSTextField(labelWithString: "")
    private var isSelected = false
    private var isHovering = false
    private var hoverTracking: NSTrackingArea?

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
        titleField.lineBreakMode = .byTruncatingMiddle
        titleField.usesSingleLineMode = true
        titleField.delegate = self
        titleField.setAccessibilityElement(false)
        addSubview(titleField)
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
        titleField.font = .systemFont(ofSize: EditorTabLayout.titleFontSize,
                                      weight: selected ? .medium : .regular)
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
        // Native text cells inset their glyphs by two points on each side.
        titleField.frame = CGRect(x: rect.minX + EditorTabLayout.horizontalPadding - 2,
                                  y: 6,
                                  width: max(0, rect.width - 2 * EditorTabLayout.horizontalPadding + 4),
                                  height: 18)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        if isSelected {
            context.addPath(ConnectedTabGeometry.fill(in: tabBounds))
            context.setFillColor(NSColor.controlBackgroundColor.cgColor)
            context.fillPath()
            context.addPath(ConnectedTabGeometry.outline(in: tabBounds))
            context.setStrokeColor(NSColor.labelColor.withAlphaComponent(0.22).cgColor)
            context.setLineWidth(1)
            context.strokePath()
        } else if isHovering {
            NSColor.secondaryLabelColor.withAlphaComponent(0.08).setFill()
            NSBezierPath(roundedRect: tabBounds.insetBy(dx: 2, dy: 4),
                         xRadius: 8, yRadius: 8).fill()
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

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self)
        addTrackingArea(area)
        hoverTracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        needsDisplay = true
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
