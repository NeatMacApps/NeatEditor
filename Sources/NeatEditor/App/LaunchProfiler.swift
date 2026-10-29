import Foundation
import OSLog

/// Cold-launch segmentation: entry → store ready → first frame.
///
/// Three checkpoints, one `info` log line per launch. Main-thread only by
/// construction (entry → App init → first-frame task); overhead is three
/// `CFAbsoluteTime` reads. Read back with:
/// `log show --predicate 'subsystem == "com.x0c.NeatEditor" AND category == "Launch"' --last 5m`
enum LaunchProfiler {
    private static let logger = Logger(
        subsystem: "com.x0c.NeatEditor",
        category: "Launch"
    )

    private static nonisolated(unsafe) var entryTime: CFAbsoluteTime = 0
    private static nonisolated(unsafe) var storeReadyTime: CFAbsoluteTime = 0
    private static nonisolated(unsafe) var bodyEvaluatedTime: CFAbsoluteTime = 0
    private static nonisolated(unsafe) var makeStartTime: CFAbsoluteTime = 0
    private static nonisolated(unsafe) var bridgeReadyTime: CFAbsoluteTime = 0
    private static nonisolated(unsafe) var editorReadyTime: CFAbsoluteTime = 0
    private static nonisolated(unsafe) var didReport = false

    static func recordEntry() {
        entryTime = CFAbsoluteTimeGetCurrent()
    }

    static func recordStoreReady() {
        storeReadyTime = CFAbsoluteTimeGetCurrent()
    }

    /// SwiftUI body evaluated (struct creation incl. tabs.map), before
    /// AppKit machinery runs makeNSViewController.
    static func recordBodyEvaluated() {
        if bodyEvaluatedTime == 0 {
            bodyEvaluatedTime = CFAbsoluteTimeGetCurrent()
        }
    }

    /// SwiftUI began creating the AppKit bridge (makeNSViewController entry).
    static func recordMakeStart() {
        if makeStartTime == 0 {
            makeStartTime = CFAbsoluteTimeGetCurrent()
        }
    }

    /// AppKit split bridge created (covers Scene/Window/body eval + tabs.map).
    static func recordBridgeReady() {
        if bridgeReadyTime == 0 {
            bridgeReadyTime = CFAbsoluteTimeGetCurrent()
        }
    }

    /// Editor text stack assembled (NSTextView + TextKit2 + gutter + layout).
    static func recordEditorReady() {
        if editorReadyTime == 0 {
            editorReadyTime = CFAbsoluteTimeGetCurrent()
        }
    }

    static func recordFirstFrame() {
        guard !didReport else { return }
        didReport = true
        let firstFrame = CFAbsoluteTimeGetCurrent()
        let mainToStore = (storeReadyTime - entryTime) * 1000
        let storeToBody = (bodyEvaluatedTime - storeReadyTime) * 1000
        let bodyToMake = (makeStartTime - bodyEvaluatedTime) * 1000
        let makeToBridge = (bridgeReadyTime - makeStartTime) * 1000
        let bridgeToEditor = (editorReadyTime - bridgeReadyTime) * 1000
        let editorToFrame = (firstFrame - editorReadyTime) * 1000
        logger.info(
            "launch store→body \(storeToBody, format: .fixed(precision: 2))ms body→make \(bodyToMake, format: .fixed(precision: 2))ms make→bridge \(makeToBridge, format: .fixed(precision: 2))ms bridge→editor \(bridgeToEditor, format: .fixed(precision: 2))ms editor→frame \(editorToFrame, format: .fixed(precision: 2))ms"
        )
        #if DEBUG
        let line = String(
            format: "mainToStore=%.2fms storeToBody=%.2fms bodyToMake=%.2fms makeToBridge=%.2fms bridgeToEditor=%.2fms editorToFrame=%.2fms total=%.2fms\n",
            mainToStore,
            storeToBody,
            bodyToMake,
            makeToBridge,
            bridgeToEditor,
            editorToFrame,
            (firstFrame - entryTime) * 1000
        )
        if let data = line.data(using: .utf8) {
            let url = URL(fileURLWithPath: "/tmp/neat-launch-times.log")
            if FileManager.default.fileExists(atPath: url.path),
               let handle = try? FileHandle(forWritingTo: url) {
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
        #endif
    }
}
