import AppKit
import SwiftUI

/// Written by EditorTabItemView before editing ends, read by
/// EditorTabStripView's dismiss callback to call onRenameTab.
@MainActor var tabStripPendingRename: String?

struct EditorTabStripView: View {
    static let titleBarHeight: CGFloat = 38
    static let leadingPadding: CGFloat = 76
    static let trailingTabScrollPadding: CGFloat = 12
    static let trailingAccessoryWidth: CGFloat = 52
    static let overflowFadeWidth: CGFloat = 16
    static let overflowVisibilityThreshold: CGFloat = 1
    static let minimumWindowEdge: CGFloat = {
        // Keep the window large enough for traffic lights, two tabs, and the pin accessory.
        ceil(
            leadingPadding + trailingTabScrollPadding + trailingAccessoryWidth
                + (EditorTabItemView.minimumTabWidth * 2) + 24
        )
    }()

    @Binding var tabs: [EditorTab]
    let selectedTabID: UUID?
    let onSelectTab: (UUID) -> Void
    let onSelectTabRelative: (Int) -> Void
    let onRenameTab: (UUID, String) -> Void
    let onCloseTab: (UUID) -> Void
    let onDeleteTab: (UUID) -> Void
    let onCloseOtherTabs: (UUID) -> Void
    @State private var selectedTabFrame: CGRect = .null
    @State private var tabFrames: [UUID: CGRect] = [:]
    @State private var tabScrollViewportFrame: CGRect = .null
    @State private var editingTabID: UUID? = nil

    var body: some View {
        HStack(spacing: 0) {
            ScrollViewReader { scrollProxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach($tabs) { $tab in
                            EditorTabItemView(
                                tab: $tab,
                                isSelected: selectedTabID == tab.id,
                                tabCount: tabs.count,
                                isEditing: Binding(
                                    get: { editingTabID == tab.id },
                                    set: { isEditing in
                                        if isEditing {
                                            editingTabID = tab.id
                                        } else if editingTabID == tab.id {
                                            editingTabID = nil
                                        }
                                    }
                                )
                            ) {
                                if editingTabID != nil && editingTabID != tab.id {
                                    dismissEditing()
                                    NSApp.keyWindow?.makeFirstResponder(nil)
                                }
                                onSelectTab(tab.id)
                            } onRename: { newTitle in
                                onRenameTab(tab.id, newTitle)
                            } onClose: {
                                onCloseTab(tab.id)
                            } onDelete: {
                                onDeleteTab(tab.id)
                            } onCloseOthers: {
                                onCloseOtherTabs(tab.id)
                            }
                            .id(tab.id)
                        }
                    }
                    .padding(.trailing, Self.trailingTabScrollPadding)
                    .padding(.top, 6)
                }
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: TabScrollViewportFramePreferenceKey.self,
                            value: proxy.frame(in: .named(TabBarLayout.coordinateSpaceName))
                        )
                    }
                }
                .overlay(alignment: .leading) {
                    if showsLeadingOverflowFade {
                        TabStripOverflowFade(edge: .leading)
                    }
                }
                .overlay(alignment: .trailing) {
                    if showsTrailingOverflowFade {
                        TabStripOverflowFade(edge: .trailing)
                    }
                }
                .overlay {
                    TabStripScrollInterceptor(
                        isEditing: editingTabID != nil,
                        onSelectTabRelative: onSelectTabRelative
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .onChange(of: selectedTabID) { _, _ in
                    scrollSelectedTabIntoView(using: scrollProxy)
                }
                .onChange(of: tabFrames) { _, _ in
                    scrollSelectedTabIntoView(using: scrollProxy)
                }
                .onChange(of: tabScrollViewportFrame) { _, _ in
                    scrollSelectedTabIntoView(using: scrollProxy)
                }
                .onAppear {
                    scrollSelectedTabIntoView(using: scrollProxy)
                }
            }

            TitleBarAccessoryBackground()
                .frame(width: Self.trailingTabScrollPadding)
        }
        .coordinateSpace(name: TabBarLayout.coordinateSpaceName)
        .onPreferenceChange(SelectedTabFramePreferenceKey.self) { frame in
            Task { @MainActor in
                selectedTabFrame = frame
            }
        }
        .onPreferenceChange(TabFramesPreferenceKey.self) { frames in
            Task { @MainActor in
                tabFrames = frames
            }
        }
        .onPreferenceChange(TabScrollViewportFramePreferenceKey.self) { frame in
            Task { @MainActor in
                tabScrollViewportFrame = frame
            }
        }
        .background(EditorChrome.tabBarBackground)
        .overlay {
            TabBarOutlineShape(selectedTabFrame: selectedTabFrame)
                .stroke(Color.primary.opacity(0.22), lineWidth: EditorChrome.lineWidth)
                .allowsHitTesting(false)
        }
        .clipped()
        .background {
            TitleBarEventMonitor(
                isEditing: editingTabID != nil,
                tabFrames: tabFrames,
                onDismissEditing: { dismissEditing() },
                onCloseTab: onCloseTab
            )
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)
        ) { _ in
            dismissEditing()
        }
        .frame(height: Self.titleBarHeight)
    }

    private var showsLeadingOverflowFade: Bool {
        guard !tabScrollViewportFrame.isNull else {
            return false
        }

        return tabFrames.values.contains { frame in
            !frame.isNull
                && frame.minX < (
                    tabScrollViewportFrame.minX - Self.overflowVisibilityThreshold)
        }
    }

    private var showsTrailingOverflowFade: Bool {
        guard !tabScrollViewportFrame.isNull else {
            return false
        }

        return tabFrames.values.contains { frame in
            !frame.isNull
                && frame.maxX > (
                    tabScrollViewportFrame.maxX + Self.overflowVisibilityThreshold)
        }
    }

    private func dismissEditing() {
        guard let tabID = editingTabID else { return }
        // Read the pending rename that EditorTabItemView wrote before we clear editing.
        if let newTitle = tabStripPendingRename {
            tabStripPendingRename = nil
            onRenameTab(tabID, newTitle)
        }
        editingTabID = nil
    }

    private func scrollSelectedTabIntoView(using scrollProxy: ScrollViewProxy) {
        guard let selectedTabID,
            let selectedFrame = tabFrames[selectedTabID],
            !tabScrollViewportFrame.isNull
        else {
            return
        }

        let isLeadingClipped = selectedFrame.minX < tabScrollViewportFrame.minX
        let isTrailingClipped = selectedFrame.maxX > tabScrollViewportFrame.maxX
        guard isLeadingClipped || isTrailingClipped else {
            return
        }

        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.14)) {
                scrollProxy.scrollTo(selectedTabID, anchor: .center)
            }
        }
    }
}

private struct TitleBarAccessoryBackground: View {
    var body: some View {
        EditorChrome.tabBarBackground
            .allowsHitTesting(false)
    }
}

private struct TabStripOverflowFade: View {
    enum Edge {
        case leading
        case trailing
    }

    let edge: Edge

    var body: some View {
        LinearGradient(
            colors: gradientColors,
            startPoint: edge == .leading ? .leading : .trailing,
            endPoint: edge == .leading ? .trailing : .leading
        )
        .frame(width: EditorTabStripView.overflowFadeWidth)
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    private var gradientColors: [Color] {
        [
            EditorChrome.tabBarBackground,
            EditorChrome.tabBarBackground.opacity(0)
        ]
    }
}

struct TitleBarControlDragSuppression: ViewModifier {
    private static let activationDistance: CGFloat = 4

    @Binding var isSuppressingAction: Bool

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { value in
                    guard !isSuppressingAction else {
                        return
                    }

                    let translation = value.translation
                    let distance = max(abs(translation.width), abs(translation.height))
                    if distance >= Self.activationDistance {
                        isSuppressingAction = true
                    }
                }
                .onEnded { _ in
                    DispatchQueue.main.async {
                        isSuppressingAction = false
                    }
                }
        )
    }
}

private struct TabStripScrollInterceptor: NSViewRepresentable {
    let isEditing: Bool
    let onSelectTabRelative: (Int) -> Void

    func makeNSView(context: Context) -> TabStripScrollInterceptorView {
        let view = TabStripScrollInterceptorView()
        view.isEditing = isEditing
        view.onSelectTabRelative = onSelectTabRelative
        return view
    }

    func updateNSView(_ nsView: TabStripScrollInterceptorView, context: Context) {
        nsView.isEditing = isEditing
        nsView.onSelectTabRelative = onSelectTabRelative
    }

    final class TabStripScrollInterceptorView: NSView {
        private enum ScrollTabSwitching {
            static let resetInterval: TimeInterval = 0.35
            static let threshold: CGFloat = 1
            static let mouseWheelSensitivity: CGFloat = 0.005
            static let trackpadSensitivity: CGFloat = 1 / 36
        }

        var isEditing = false
        var onSelectTabRelative: ((Int) -> Void)?
        private var accumulatedScrollDelta: CGFloat = 0
        private var lastScrollTimestamp: TimeInterval = 0

        override var isFlipped: Bool {
            true
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard bounds.contains(point),
                let currentEvent = NSApp.currentEvent
            else {
                return nil
            }

            switch currentEvent.type {
            case .scrollWheel, .swipe:
                return self
            default:
                return nil
            }
        }

        override func scrollWheel(with event: NSEvent) {
            guard !isEditing else {
                super.scrollWheel(with: event)
                return
            }

            if !event.momentumPhase.isEmpty {
                resetAccumulatedScrollDelta()
                return
            }

            if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
                resetAccumulatedScrollDelta()
                return
            }

            let horizontalDelta = event.hasPreciseScrollingDeltas
                ? event.scrollingDeltaX
                : event.deltaX
            let verticalDelta = event.hasPreciseScrollingDeltas
                ? event.scrollingDeltaY
                : event.deltaY
            let dominantDelta = abs(verticalDelta) >= abs(horizontalDelta) ? verticalDelta : horizontalDelta
            guard dominantDelta != 0 else {
                return
            }

            let usesTrackpadSensitivity =
                !event.phase.isEmpty
                || !event.momentumPhase.isEmpty
            accumulateTabSelectionDelta(
                dominantDelta,
                timestamp: event.timestamp,
                sensitivity: usesTrackpadSensitivity
                    ? ScrollTabSwitching.trackpadSensitivity
                    : ScrollTabSwitching.mouseWheelSensitivity
            )
        }

        override func swipe(with event: NSEvent) {
            guard !isEditing else {
                super.swipe(with: event)
                return
            }

            let dominantDelta = abs(event.deltaY) >= abs(event.deltaX) ? event.deltaY : event.deltaX
            guard dominantDelta != 0 else {
                return
            }

            resetAccumulatedScrollDelta()
            let stepDelta: CGFloat = dominantDelta > 0 ? 1 : -1
            accumulateTabSelectionDelta(stepDelta, timestamp: event.timestamp, sensitivity: 1)
        }

        private func accumulateTabSelectionDelta(
            _ delta: CGFloat,
            timestamp: TimeInterval,
            sensitivity: CGFloat
        ) {
            if (timestamp - lastScrollTimestamp) > ScrollTabSwitching.resetInterval {
                accumulatedScrollDelta = 0
            }

            let scaledDelta = delta * sensitivity
            if accumulatedScrollDelta != 0,
                scaledDelta.sign != accumulatedScrollDelta.sign
            {
                accumulatedScrollDelta = 0
            }

            accumulatedScrollDelta += scaledDelta
            lastScrollTimestamp = timestamp

            while abs(accumulatedScrollDelta) >= ScrollTabSwitching.threshold {
                let relativeOffset = accumulatedScrollDelta > 0 ? -1 : 1
                onSelectTabRelative?(relativeOffset)
                accumulatedScrollDelta += accumulatedScrollDelta > 0 ? -1 : 1
            }
        }

        private func resetAccumulatedScrollDelta() {
            accumulatedScrollDelta = 0
            lastScrollTimestamp = 0
        }
    }
}

private struct TitleBarEventMonitor: NSViewRepresentable {
    let isEditing: Bool
    let tabFrames: [UUID: CGRect]
    let onDismissEditing: () -> Void
    let onCloseTab: (UUID) -> Void

    func makeNSView(context: Context) -> TitleBarEventNSView {
        let view = TitleBarEventNSView()
        view.isEditing = isEditing
        view.tabFrames = tabFrames
        view.onDismissEditing = onDismissEditing
        view.onCloseTab = onCloseTab
        return view
    }

    func updateNSView(_ nsView: TitleBarEventNSView, context: Context) {
        nsView.isEditing = isEditing
        nsView.tabFrames = tabFrames
        nsView.onDismissEditing = onDismissEditing
        nsView.onCloseTab = onCloseTab
    }

    final class TitleBarEventNSView: NSView {
        var isEditing = false
        var tabFrames: [UUID: CGRect] = [:]
        var onDismissEditing: (() -> Void)?
        var onCloseTab: ((UUID) -> Void)?
        private var clickMonitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            installMonitor()
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if newWindow == nil {
                removeMonitor()
            }
            super.viewWillMove(toWindow: newWindow)
        }

        private func installMonitor() {
            removeMonitor()
            clickMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .otherMouseUp]
            ) { [weak self] event in
                self?.handleMouseEvent(event)
                return event
            }
        }

        private func removeMonitor() {
            if let clickMonitor {
                NSEvent.removeMonitor(clickMonitor)
                self.clickMonitor = nil
            }
        }

        private func handleMouseEvent(_ event: NSEvent) {
            if event.type == .leftMouseDown {
                // Dismiss editing when clicking outside the title bar area
                // (where the rename text field lives).
                if isEditing && !isEventInTitleBarRegion(event) {
                    DispatchQueue.main.async { [weak self] in
                        self?.onDismissEditing?()
                    }
                }
            } else if event.type == .otherMouseUp, event.buttonNumber == 2 {
                guard let tabID = tabID(at: event) else {
                    return
                }

                DispatchQueue.main.async { [weak self] in
                    if self?.isEditing == true {
                        self?.onDismissEditing?()
                    }
                    self?.onCloseTab?(tabID)
                }
            }
        }

        private func tabID(at event: NSEvent) -> UUID? {
            guard event.window === self.window else {
                return nil
            }

            let location = convert(event.locationInWindow, from: nil)
            return tabFrames.first { _, frame in
                frame.contains(location)
            }?.key
        }

        private func isEventInTitleBarRegion(_ event: NSEvent) -> Bool {
            guard event.window === window else { return false }
            // Measure the actual toolbar-hosted tab view, never a fixed
            // offset from the window's top edge.
            return bounds.contains(convert(event.locationInWindow, from: nil))
        }

    }
}

/// One geometry builds both the fill and the outline, preserving the existing
/// rounded stepped silhouette without independently splicing its joins.
enum ConnectedTabGeometry {
    static func appendTopEdge(
        to path: inout Path,
        in rect: CGRect,
        topInset: CGFloat = 6,
        topCornerRadius: CGFloat = 9,
        bottomJoinRadius: CGFloat = 9
    ) {
        let inset = min(topInset, rect.width / 4)
        let topRadius = min(topCornerRadius, rect.width / 2, rect.height / 2)
        let bottomRadius = min(bottomJoinRadius, rect.width / 2, rect.height / 2)
        let bottomY = rect.maxY - 0.5
        path.addLine(to: CGPoint(x: rect.minX + inset - bottomRadius, y: bottomY))
        path.addArc(
            tangent1End: CGPoint(x: rect.minX + inset, y: bottomY),
            tangent2End: CGPoint(x: rect.minX + inset, y: rect.minY),
            radius: bottomRadius
        )
        path.addLine(to: CGPoint(x: rect.minX + inset, y: rect.minY + topRadius))
        path.addArc(
            tangent1End: CGPoint(x: rect.minX + inset, y: rect.minY),
            tangent2End: CGPoint(x: rect.maxX - inset, y: rect.minY),
            radius: topRadius
        )
        path.addLine(to: CGPoint(x: rect.maxX - inset - topRadius, y: rect.minY))
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX - inset, y: rect.minY),
            tangent2End: CGPoint(x: rect.maxX - inset, y: bottomY),
            radius: topRadius
        )
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: bottomY - bottomRadius))
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX - inset, y: bottomY),
            tangent2End: CGPoint(x: rect.maxX - inset + bottomRadius, y: bottomY),
            radius: bottomRadius
        )
    }
}

struct ConnectedTabFillShape: Shape {
    let topInset: CGFloat
    let topCornerRadius: CGFloat
    let bottomJoinRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + topInset - bottomJoinRadius, y: rect.maxY - 0.5))
        ConnectedTabGeometry.appendTopEdge(
            to: &path,
            in: rect,
            topInset: topInset,
            topCornerRadius: topCornerRadius,
            bottomJoinRadius: bottomJoinRadius
        )
        path.closeSubpath()
        return path
    }
}

struct TabBarOutlineShape: Shape {
    let selectedTabFrame: CGRect

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let baseline = rect.maxY - 0.5
        path.move(to: CGPoint(x: rect.minX, y: baseline))
        if !selectedTabFrame.isNull, selectedTabFrame.intersects(rect) {
            ConnectedTabGeometry.appendTopEdge(to: &path, in: selectedTabFrame)
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: baseline))
        return path
    }
}

#Preview {
    @Previewable @State var tabs = [
        EditorTab(id: UUID(), title: "Untitled 1"),
        EditorTab(id: UUID(), title: "Config.yml"),
        EditorTab(id: UUID(), title: "Readme.md"),
    ]
    @Previewable @State var selectedTabID: UUID?

    VStack(spacing: 0) {
        EditorTabStripView(
            tabs: $tabs,
            selectedTabID: selectedTabID,
            onSelectTab: { selectedTabID = $0 },
            onSelectTabRelative: { offset in
                guard let currentSelectedTabID = selectedTabID,
                    let selectedIndex = tabs.firstIndex(where: { $0.id == currentSelectedTabID })
                else {
                    return
                }

                let targetIndex = selectedIndex + offset
                guard tabs.indices.contains(targetIndex) else {
                    return
                }

                selectedTabID = tabs[targetIndex].id
            },
            onRenameTab: { id, newTitle in
                guard let index = tabs.firstIndex(where: { $0.id == id }) else {
                    return
                }

                tabs[index].title = newTitle
            },
            onCloseTab: { id in
                tabs.removeAll { $0.id == id }
                if selectedTabID == id {
                    selectedTabID = tabs.first?.id
                }
            },
            onDeleteTab: { _ in },
            onCloseOtherTabs: { _ in }
        )
        Spacer()
    }
    .frame(width: 400, height: 200)
    .background(EditorChrome.tabBarBackground)
    .onAppear {
        selectedTabID = tabs.first?.id
    }
}
