import CoreGraphics
import Foundation
import Testing

@testable import NeatEditor

/// Hover-steal topmost checks: only same-layer occlusion blocks, so two
/// overlapping pinned windows stop fighting while system overlays never block.
struct HoverFocusTopmostCheckTests {
    @Test("uncovered point steals focus")
    func uncoveredPointStealsFocus() {
        let target = record(id: 2, frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        #expect(HoverFocusTopmostCheck.isTopmostAtPoint(
            CGPoint(x: 50, y: 50),
            targetID: 2,
            windowsFrontToBack: [target]
        ))
    }

    @Test("point covered by same-layer front window does not steal")
    func coveredPointDoesNotSteal() {
        let front = record(id: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let target = record(id: 2, frame: CGRect(x: 50, y: 50, width: 100, height: 100))
        #expect(!HoverFocusTopmostCheck.isTopmostAtPoint(
            CGPoint(x: 75, y: 75),
            targetID: 2,
            windowsFrontToBack: [front, target]
        ))
        #expect(HoverFocusTopmostCheck.isTopmostAtPoint(
            CGPoint(x: 125, y: 125),
            targetID: 2,
            windowsFrontToBack: [front, target]
        ))
    }

    @Test("transparent front window does not block")
    func transparentFrontWindowDoesNotBlock() {
        let front = record(id: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 100), alpha: 0.2)
        let target = record(id: 2, frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        #expect(HoverFocusTopmostCheck.isTopmostAtPoint(
            CGPoint(x: 50, y: 50),
            targetID: 2,
            windowsFrontToBack: [front, target]
        ))
    }

    @Test("higher-layer overlays do not block")
    func higherLayerOverlaysDoNotBlock() {
        let overlay = record(id: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 100), layer: 25)
        let target = record(id: 2, frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        #expect(HoverFocusTopmostCheck.isTopmostAtPoint(
            CGPoint(x: 50, y: 50),
            targetID: 2,
            windowsFrontToBack: [overlay, target]
        ))
    }

    @Test("missing target never steals focus")
    func missingTargetNeverStealsFocus() {
        #expect(!HoverFocusTopmostCheck.isTopmostAtPoint(
            CGPoint(x: 50, y: 50),
            targetID: 99,
            windowsFrontToBack: [record(id: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 100))]
        ))
    }

    @Test("AppKit point converts to top-left origin")
    func appKitPointConverts() {
        #expect(HoverFocusTopmostCheck.cgPoint(
            fromAppKitPoint: CGPoint(x: 30, y: 100),
            primaryDisplayHeight: 1000
        ) == CGPoint(x: 30, y: 900))
    }

    @Test("debounce requires entry dwell and post-transition settle")
    func debounceRequiresDwellAndSettle() {
        let now = Date()
        // 首次进框：还没记入场时刻，不动手。
        #expect(!HoverFocusTopmostCheck.isDebounceSatisfied(
            now: now,
            entryDate: nil,
            lastKeyTransition: .distantPast,
            dwell: 0.15,
            settle: 0.35
        ))
        // 刚进框：驻留不够，不动手。
        #expect(!HoverFocusTopmostCheck.isDebounceSatisfied(
            now: now,
            entryDate: now,
            lastKeyTransition: .distantPast,
            dwell: 0.15,
            settle: 0.35
        ))
        // 驻留够了，但刚发生过 key 变化：静默期内不动手。
        #expect(!HoverFocusTopmostCheck.isDebounceSatisfied(
            now: now,
            entryDate: now.addingTimeInterval(-1),
            lastKeyTransition: now,
            dwell: 0.15,
            settle: 0.35
        ))
        // 两项都满足：动手。
        #expect(HoverFocusTopmostCheck.isDebounceSatisfied(
            now: now,
            entryDate: now.addingTimeInterval(-1),
            lastKeyTransition: now.addingTimeInterval(-1),
            dwell: 0.15,
            settle: 0.35
        ))
    }

    private func record(
        id: CGWindowID,
        frame: CGRect,
        layer: Int = 0,
        alpha: CGFloat = 1
    ) -> HoverFocusTopmostCheck.WindowRecord {
        HoverFocusTopmostCheck.WindowRecord(windowID: id, frame: frame, layer: layer, alpha: alpha)
    }
}
