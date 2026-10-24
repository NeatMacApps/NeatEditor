import AppKit
import SwiftUI

struct EditorTabStripView: NSViewRepresentable {
    static let titleBarHeight: CGFloat = 38
    static let minimumWindowEdge: CGFloat = 470

    @Binding var tabs: [EditorTab]
    let selectedTabID: UUID?
    let onSelectTab: (UUID) -> Void
    let onSelectTabRelative: (Int) -> Void
    let onRenameTab: (UUID, String) -> Void
    let onCloseTab: (UUID) -> Void
    let onDeleteTab: (UUID) -> Void
    let onCloseOtherTabs: (UUID) -> Void

    func makeNSView(context: Context) -> NativeDocumentTabsView {
        let view = NativeDocumentTabsView()
        view.update(configuration: self)
        return view
    }

    func updateNSView(_ view: NativeDocumentTabsView, context: Context) {
        view.update(configuration: self)
    }
}

/// Native segmented tabs supply all artwork, selection and keyboard behavior.
/// Only document-specific rename, menus and scroll-to-selection live here.
final class NativeDocumentTabsView: NSView, NSTextFieldDelegate {
    private static let segmentWidth: CGFloat = 168
    private let scrollView = NSScrollView()
    private let control = DocumentSegmentedControl()
    private var configuration: EditorTabStripView?
    private var displayedIDs: [UUID] = []
    private var displayedTitles: [String] = []
    private var renameField: NSTextField?
    private var renamingID: UUID?
    private var eventMonitor: Any?
    private var resignObserver: Any?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.horizontalScrollElasticity = .none
        scrollView.verticalScrollElasticity = .none
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        control.trackingMode = .selectOne
        control.segmentStyle = .automatic
        control.controlSize = .regular
        control.focusRingType = .none
        if #available(macOS 27, *) {
            control.role = .tabs
        }
        control.target = self
        control.action = #selector(selectSegment(_:))
        control.onRename = { [weak self] in self?.beginRename() }
        control.onMiddleClick = { [weak self] index in
            guard let self, displayedIDs.indices.contains(index) else { return }
            configuration?.onCloseTab(displayedIDs[index])
        }
        control.makeMenu = { [weak self] index in self?.menu(forSegment: index) }
        control.onStep = { [weak self] offset in self?.configuration?.onSelectTabRelative(offset) }
        scrollView.documentView = control
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, eventMonitor == nil {
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                guard let self, let field = renameField else { return event }
                if event.window !== window || !field.bounds.contains(field.convert(event.locationInWindow, from: nil)) {
                    finishRename()
                }
                return event
            }
            resignObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.finishRename() }
            }
        } else if window == nil {
            if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
            if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
            eventMonitor = nil
            resignObserver = nil
        }
    }

    override func layout() {
        super.layout()
        resizeControl()
        revealSelection()
    }

    func update(configuration: EditorTabStripView) {
        self.configuration = configuration
        let ids = configuration.tabs.map(\.id)
        let titles = configuration.tabs.map(\.title)
        if ids != displayedIDs || titles != displayedTitles {
            if let renamingID, !ids.contains(renamingID) {
                cancelRename()
            }
            displayedIDs = ids
            displayedTitles = titles
            control.segmentCount = ids.count
            for index in ids.indices {
                control.setLabel(titles[index], forSegment: index)
                control.setToolTip(titles[index], forSegment: index)
                control.setWidth(Self.segmentWidth, forSegment: index)
            }
            resizeControl()
        }
        control.selectedSegment = ids.firstIndex { $0 == configuration.selectedTabID } ?? -1
        revealSelection()
    }

    private func resizeControl() {
        control.sizeToFit()
        control.frame.origin = NSPoint(x: 0, y: max(0, (bounds.height - control.frame.height) / 2))
    }

    private func revealSelection() {
        guard displayedIDs.indices.contains(control.selectedSegment), renameField == nil else { return }
        let rect = segmentRect(control.selectedSegment)
        // Center only when clipped, keeping selection stable through resizes.
        if !scrollView.contentView.bounds.contains(rect) {
            control.scrollToVisible(rect)
        }
    }

    private func segmentRect(_ index: Int) -> NSRect {
        NSRect(
            x: CGFloat(index) * Self.segmentWidth,
            y: 0,
            width: Self.segmentWidth,
            height: control.bounds.height
        )
    }

    @objc private func selectSegment(_ sender: NSSegmentedControl) {
        guard displayedIDs.indices.contains(sender.selectedSegment) else { return }
        finishRename()
        configuration?.onSelectTab(displayedIDs[sender.selectedSegment])
        revealSelection()
    }

    private func beginRename() {
        let index = control.selectedSegment
        guard displayedIDs.indices.contains(index) else { return }
        finishRename()
        renamingID = displayedIDs[index]
        let field = NSTextField(string: displayedTitles[index])
        field.focusRingType = .none
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.delegate = self
        field.frame = segmentRect(index).insetBy(dx: 5, dy: 2)
        control.addSubview(field)
        renameField = field
        window?.makeFirstResponder(field)
        field.selectText(nil)
    }

    private func finishRename() {
        guard let id = renamingID, let field = renameField else { return }
        let title = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        cancelRename()
        if !title.isEmpty {
            configuration?.onRenameTab(id, title)
        }
    }

    private func cancelRename() {
        let field = renameField
        renameField = nil
        renamingID = nil
        if let field, window?.firstResponder === field.currentEditor() {
            window?.makeFirstResponder(nil)
        }
        field?.removeFromSuperview()
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        finishRename()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            cancelRename()
            return true
        }
        if selector == #selector(NSResponder.insertNewline(_:)) {
            finishRename()
            return true
        }
        return false
    }

    private func menu(forSegment index: Int) -> NSMenu? {
        guard let configuration, configuration.tabs.indices.contains(index) else { return nil }
        let tab = configuration.tabs[index]
        let menu = NSMenu()
        func add(_ title: String, _ symbol: String, _ selector: Selector) {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
            item.target = self
            item.representedObject = tab.id
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            menu.addItem(item)
        }
        if tab.fileURL != nil {
            add(String(localized: "Show in Finder"), "folder", #selector(revealDocument(_:)))
            menu.addItem(.separator())
        }
        add(String(localized: "Rename…"), "pencil", #selector(renameDocument(_:)))
        add(String(localized: "Close Tab"), "xmark", #selector(closeDocument(_:)))
        if configuration.tabs.count > 1 {
            add(String(localized: "Close Other Tabs"), "xmark.rectangle.portrait", #selector(closeOthers(_:)))
        }
        if tab.fileURL != nil, !tab.isSettings {
            menu.addItem(.separator())
            add(String(localized: "Move to Trash"), "trash", #selector(trashDocument(_:)))
        }
        return menu
    }

    @objc private func closeDocument(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? UUID { configuration?.onCloseTab(id) }
    }

    @objc private func closeOthers(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? UUID { configuration?.onCloseOtherTabs(id) }
    }

    @objc private func trashDocument(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? UUID { configuration?.onDeleteTab(id) }
    }

    @objc private func revealDocument(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let url = configuration?.tabs.first(where: { $0.id == id })?.fileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func renameDocument(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let index = displayedIDs.firstIndex(of: id) else { return }
        configuration?.onSelectTab(id)
        control.selectedSegment = index
        beginRename()
    }
}

private final class DocumentSegmentedControl: NSSegmentedControl {
    var onRename: (() -> Void)?
    var onMiddleClick: ((Int) -> Void)?
    var makeMenu: ((Int) -> NSMenu?)?
    var onStep: ((Int) -> Void)?
    private var firstClickWasSelected = false
    private var accumulatedDelta: CGFloat = 0
    private var lastScrollTimestamp: TimeInterval = 0

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 1 {
            firstClickWasSelected = segmentIndex(at: event) == selectedSegment
        }
        super.mouseDown(with: event)
        if event.clickCount == 2, firstClickWasSelected {
            onRename?()
        }
    }

    override func otherMouseUp(with event: NSEvent) {
        if event.buttonNumber == 2, let index = segmentIndex(at: event) {
            onMiddleClick?(index)
        } else {
            super.otherMouseUp(with: event)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        segmentIndex(at: event).flatMap { makeMenu?($0) }
    }

    private func segmentIndex(at event: NSEvent) -> Int? {
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return nil }
        var edge: CGFloat = 0
        for index in 0..<segmentCount {
            edge += width(forSegment: index)
            if point.x < edge { return index }
        }
        return nil
    }

    override func scrollWheel(with event: NSEvent) {
        guard event.momentumPhase.isEmpty else { return }
        if event.timestamp - lastScrollTimestamp > 0.35 {
            accumulatedDelta = 0
        }
        lastScrollTimestamp = event.timestamp
        let delta = abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX)
            ? event.scrollingDeltaY : event.scrollingDeltaX
        let scaled = delta * (event.hasPreciseScrollingDeltas ? 1 / 36 : 0.005)
        if accumulatedDelta.sign != scaled.sign { accumulatedDelta = 0 }
        accumulatedDelta += scaled
        while abs(accumulatedDelta) >= 1 {
            onStep?(accumulatedDelta > 0 ? -1 : 1)
            accumulatedDelta += accumulatedDelta > 0 ? -1 : 1
        }
    }
}
