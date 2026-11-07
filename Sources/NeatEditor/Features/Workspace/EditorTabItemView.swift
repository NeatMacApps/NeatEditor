import AppKit

/// Product-owned stepped tab; the native field, fill and outline share one frame.
final class EditorTabItemView: NSControl, NSTextFieldDelegate {
    let id: UUID
    weak var strip: EditorTabStripView?
    private(set) var descriptor: EditorTabDescriptor
    let titleField = NSTextField(labelWithString: "")
    private var isSelected = false
    let closeButton = NSButton()
    private let closeFade = CAGradientLayer()
    private var hoverArea: NSTrackingArea?
    private var isPointerInside = false

    var tabBounds: CGRect {
        CGRect(x: ConnectedTabGeometry.baselineOutset, y: 0,
               width: max(0, bounds.width - 2 * ConnectedTabGeometry.baselineOutset),
               height: EditorTabLayout.tabHeight)
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    // The tab forwards a confirmed drag through NSView's native background
    // handling. Native close/rename children still block window movement.
    override var mouseDownCanMoveWindow: Bool { true }

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
        wantsLayer = true
        closeFade.startPoint = CGPoint(x: 0, y: 0.5)
        closeFade.endPoint = CGPoint(x: 1, y: 0.5)
        closeFade.locations = [0, 0.45, 1]
        closeFade.zPosition = 1
        layer?.addSublayer(closeFade)
        let closeLabel = String(localized: "Close Tab")
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: closeLabel)
        closeButton.symbolConfiguration = .init(pointSize: 10, weight: .medium)
        closeButton.isBordered = false
        closeButton.imagePosition = .imageOnly
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.focusRingType = .none
        closeButton.toolTip = closeLabel
        closeButton.setAccessibilityLabel(closeLabel)
        closeButton.setAccessibilityIdentifier("close-tab-\(id)")
        closeButton.target = self
        closeButton.action = #selector(closeTab(_:))
        closeButton.wantsLayer = true
        closeButton.layer?.zPosition = 2
        addSubview(closeButton)
        updateCloseVisibility()
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
        closeButton.frame = CGRect(x: rect.maxX - EditorTabLayout.horizontalPadding - 20,
                                   y: EditorTabLayout.tabTitleCenterY - 10, width: 20, height: 20)
        updateCloseFade()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
        if let window {
            isPointerInside = visibleRect.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
        } else {
            isPointerInside = false
        }
        updateCloseVisibility()
    }

    override func mouseEntered(with event: NSEvent) {
        isPointerInside = true
        updateCloseVisibility()
    }

    override func mouseExited(with event: NSEvent) {
        isPointerInside = false
        updateCloseVisibility()
    }

    private func updateCloseVisibility() {
        let hidden = !isPointerInside || strip?.editingTabID == id
        closeButton.isHidden = hidden
        closeFade.isHidden = hidden
    }

    private func updateCloseFade() {
        let theme = strip?.theme ?? .defaultValue
        let background = EditorChrome.resolvedColor(
            isSelected ? EditorChrome.editorSurfaceColor(for: theme) : EditorChrome.tabBarBackgroundColor(for: theme),
            for: effectiveAppearance
        )
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        closeFade.frame = CGRect(x: closeButton.frame.minX - EditorTabLayout.fadeWidth,
                                 y: closeButton.frame.minY - 2,
                                 width: EditorTabLayout.fadeWidth + closeButton.frame.width + 2,
                                 height: closeButton.frame.height + 4)
        closeFade.colors = [background.withAlphaComponent(0).cgColor, background.cgColor, background.cgColor]
        CATransaction.commit()
    }

    @objc private func closeTab(_ sender: Any?) {
        strip?.actions.onClose(id)
    }

    override func draw(_ dirtyRect: NSRect) {
        updateCloseFade()
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        // Whether the titlebar clips below the band varies with window state;
        // the outline's lowest row always belongs to the editor's top rule.
        context.clip(to: CGRect(x: 0, y: 0, width: bounds.width, height: EditorTabLayout.tabHeight))
        if isSelected {
            context.addPath(ConnectedTabGeometry.fill(in: tabBounds))
            context.setFillColor(EditorChrome.editorSurfaceColor(for: strip?.theme ?? .defaultValue).cgColor)
            context.fillPath()
            context.addPath(ConnectedTabGeometry.outline(in: tabBounds))
            context.setStrokeColor(EditorChrome.tabOutlineColor.cgColor)
            context.setLineWidth(EditorChrome.lineWidth)
            context.strokePath()
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        if strip?.editingTabID == id || hit === closeButton { return hit }
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
        closeButton.isHidden = editing || !isPointerInside
        closeFade.isHidden = closeButton.isHidden
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
