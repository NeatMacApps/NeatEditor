import AppKit

extension EditorTabStripView {
    func selectTab(_ id: UUID) {
        finishRename(commit: true)
        actions.onSelect(id)
    }

    func handleClick(tabID: UUID, clickCount: Int) {
        if clickCount == 2, renameEligibleID == tabID, selectedTabID == tabID {
            beginRename(tabID)
        } else {
            renameEligibleID = clickCount == 1 && selectedTabID == tabID ? tabID : nil
            selectTab(tabID)
        }
    }

    func trackPointer(_ mouseDown: NSEvent, tabID: UUID) {
        guard let window else { return }
        finishRename(commit: true)
        let startMouse = NSEvent.mouseLocation
        let startOrigin = window.frame.origin
        var dragged = false
        while let event = window.nextEvent(
            matching: [.leftMouseDragged, .leftMouseUp], until: .distantFuture,
            inMode: .eventTracking, dequeue: true
        ) {
            if event.type == .leftMouseUp {
                if !dragged, let tab = tabViews[tabID],
                   tab.bounds.contains(tab.convert(event.locationInWindow, from: nil)) {
                    handleClick(tabID: tabID, clickCount: mouseDown.clickCount)
                }
                return
            }
            let mouse = NSEvent.mouseLocation
            let delta = CGPoint(x: mouse.x - startMouse.x, y: mouse.y - startMouse.y)
            if max(abs(delta.x), abs(delta.y)) >= 4 { dragged = true }
            if dragged {
                renameEligibleID = nil
                var origin = CGPoint(x: startOrigin.x + delta.x, y: startOrigin.y + delta.y)
                if let screen = (window.screen ?? NSScreen.main)?.visibleFrame {
                    origin.x = min(max(origin.x, screen.minX - window.frame.width + 80),
                                   screen.maxX - 80)
                    origin.y = min(max(origin.y, screen.minY - window.frame.height + 40),
                                   screen.maxY - 40)
                }
                window.setFrameOrigin(origin)
            }
        }
    }

    func beginRename(_ id: UUID) {
        finishRename(commit: true)
        guard let tab = tabViews[id] else { return }
        actions.onSelect(id)
        window?.makeFirstResponder(nil)
        editingTabID = id
        renameEligibleID = nil
        tab.setEditing(true)
        renameClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) {
            [weak self] event in
            guard let self, let editingTabID = self.editingTabID,
                  let item = self.tabViews[editingTabID] else { return event }
            if event.window !== self.window
                || !item.bounds.contains(item.convert(event.locationInWindow, from: nil)) {
                self.finishRename(commit: true)
            }
            return event
        }
    }

    func finishRename(commit: Bool) {
        guard let id = editingTabID else { return }
        // Clear ownership before ending the native field editor: its delegate
        // may reenter this method, and the callback may replace tab descriptors.
        editingTabID = nil
        if let renameClickMonitor {
            NSEvent.removeMonitor(renameClickMonitor)
            self.renameClickMonitor = nil
        }
        guard let item = tabViews[id] else { return }
        let title = EditorTabLayout.sanitizedTitle(item.titleField.stringValue)
        item.setEditing(false)
        if commit, !title.isEmpty, title != item.descriptor.title {
            actions.onRename(id, title)
        }
    }

    func contextMenu(for tab: EditorTabDescriptor) -> NSMenu {
        let menu = NSMenu()
        if tab.fileURL != nil {
            appendMenuItem("Show in Finder", symbol: "folder", action: #selector(showInFinder(_:)),
                           id: tab.id, to: menu)
            menu.addItem(.separator())
        }
        appendMenuItem("Rename…", symbol: "pencil", action: #selector(renameFromMenu(_:)),
                       id: tab.id, to: menu)
        appendMenuItem("Close Tab", symbol: "xmark", action: #selector(closeFromMenu(_:)),
                       id: tab.id, to: menu)
        if tabs.count > 1 {
            menu.addItem(.separator())
            appendMenuItem("Close Other Tabs", symbol: "xmark.rectangle.portrait",
                           action: #selector(closeOthersFromMenu(_:)), id: tab.id, to: menu)
        }
        if tab.fileURL != nil {
            menu.addItem(.separator())
            appendMenuItem("Move to Trash", symbol: "trash", action: #selector(trashFromMenu(_:)),
                           id: tab.id, to: menu)
        }
        return menu
    }

    private func appendMenuItem(_ key: String.LocalizationValue, symbol: String,
                                action: Selector, id: UUID, to menu: NSMenu) {
        let item = NSMenuItem(title: String(localized: key), action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = id
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        menu.addItem(item)
    }

    @objc private func showInFinder(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let url = tabs.first(where: { $0.id == id })?.fileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func renameFromMenu(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? UUID { beginRename(id) }
    }

    @objc private func closeFromMenu(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? UUID { actions.onClose(id) }
    }

    @objc private func closeOthersFromMenu(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? UUID { actions.onCloseOthers(id) }
    }

    @objc private func trashFromMenu(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? UUID { actions.onDelete(id) }
    }
}
