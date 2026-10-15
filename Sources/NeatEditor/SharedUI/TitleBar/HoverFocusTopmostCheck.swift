import AppKit
import CoreGraphics

/// 悬停抢焦点前的顶层判定。
///
/// 只看同层级遮挡：两个交叠的置顶窗口同处浮动层，后窗在重叠区不得抢 key，
/// 否则来回抢焦点闪烁。菜单栏、桌面整屏覆层等更高层级的系统窗口不计入
/// （窗口列表里常驻全屏不透明系统层，计入会让悬停转移永远不触发）。
/// 与 NeatWebApp 的 WindowVisibleCoverage.isTopmostAtPoint 同规则。
enum HoverFocusTopmostCheck {
    /// 透明度低于此值的窗口当看不见，不计入遮挡。
    static let opaqueAlphaThreshold: CGFloat = 0.9
    /// 悬停抢焦点的防抖：指针持续在框内满这么久才动手，进出抖动与快速扫过不触发。
    static let dwellBeforeSteal: TimeInterval = 0.15
    /// 悬停抢焦点的静默：窗口刚发生 key 变化（抢到或被抢）后这么久内不参与抢，
    /// 等 WindowServer 排序与快照收敛，避免拿着旧排序来回抢两三次。
    static let settleAfterKeyChange: TimeInterval = 0.35

    struct WindowRecord: Equatable, Sendable {
        let windowID: CGWindowID
        let frame: CGRect
        let layer: Int
        let alpha: CGFloat
    }

    static func isTopmostAtPoint(
        _ point: CGPoint,
        targetID: CGWindowID,
        windowsFrontToBack: [WindowRecord]
    ) -> Bool {
        guard let targetIndex = windowsFrontToBack.firstIndex(where: { $0.windowID == targetID }) else {
            return false
        }
        let targetLayer = windowsFrontToBack[targetIndex].layer

        for occluder in windowsFrontToBack.prefix(targetIndex) {
            guard occluder.layer == targetLayer, occluder.alpha >= opaqueAlphaThreshold else {
                continue
            }
            if occluder.frame.contains(point) {
                return false
            }
        }
        return true
    }

    static func cgPoint(fromAppKitPoint point: CGPoint, primaryDisplayHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryDisplayHeight - point.y)
    }

    /// 悬停抢焦点的通用防抖（纯函数，便于单测）：
    /// 指针必须持续在框内满 dwell，且距离上次 key 变化已满 settle。
    /// 时钟回拨导致负间隔时按不满足处理，宁可不抢。
    static func isDebounceSatisfied(
        now: Date,
        entryDate: Date?,
        lastKeyTransition: Date,
        dwell: TimeInterval,
        settle: TimeInterval
    ) -> Bool {
        guard let entryDate else {
            return false
        }
        guard now.timeIntervalSince(lastKeyTransition) >= settle else {
            return false
        }
        return now.timeIntervalSince(entryDate) >= dwell
    }

    /// 当前鼠标点位是否落在该窗口未被遮挡的部分上。读不到窗口列表、
    /// 拿不到窗口编号、或列表里找不到自己时一律返回 false（宁可不抢，
    /// 不可在无法确认层级时参与抢 key 对打）。
    @MainActor
    static func isTopmostWindowAtMouseLocation(_ window: NSWindow) -> Bool {
        let windowNumber = window.windowNumber
        guard windowNumber > 0 else {
            return false
        }

        guard let windowsFrontToBack = captureOnScreenWindows() else {
            return false
        }

        let targetID = CGWindowID(windowNumber)
        guard windowsFrontToBack.contains(where: { $0.windowID == targetID }) else {
            return false
        }

        let primaryHeight = NSScreen.screens.first { $0.frame.origin == .zero }?.frame.height
            ?? NSScreen.screens.first?.frame.height
            ?? 0
        let cgMouse = cgPoint(fromAppKitPoint: NSEvent.mouseLocation, primaryDisplayHeight: primaryHeight)
        return isTopmostAtPoint(cgMouse, targetID: targetID, windowsFrontToBack: windowsFrontToBack)
    }

    @MainActor
    static func captureOnScreenWindows() -> [WindowRecord]? {
        guard let rawList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }

        return rawList.compactMap(parseRecord(from:))
    }

    private static func parseRecord(from dict: [String: Any]) -> WindowRecord? {
        guard let windowID = cgWindowID(from: dict[kCGWindowNumber as String]),
              let bounds = dict[kCGWindowBounds as String] as? NSDictionary,
              let frame = CGRect(dictionaryRepresentation: bounds),
              frame.width > 0,
              frame.height > 0 else {
            return nil
        }

        let layer = (dict[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
        let alpha = CGFloat((dict[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1)
        return WindowRecord(windowID: windowID, frame: frame, layer: layer, alpha: alpha)
    }

    private static func cgWindowID(from value: Any?) -> CGWindowID? {
        if let number = value as? NSNumber {
            return number.uint32Value
        }
        return value as? CGWindowID
    }
}
