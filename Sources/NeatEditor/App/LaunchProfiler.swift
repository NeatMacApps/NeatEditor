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
    private static nonisolated(unsafe) var didReport = false

    static func recordEntry() {
        entryTime = CFAbsoluteTimeGetCurrent()
    }

    static func recordStoreReady() {
        storeReadyTime = CFAbsoluteTimeGetCurrent()
    }

    static func recordFirstFrame() {
        guard !didReport else { return }
        didReport = true
        let firstFrame = CFAbsoluteTimeGetCurrent()
        let mainToStore = (storeReadyTime - entryTime) * 1000
        let storeToFrame = (firstFrame - storeReadyTime) * 1000
        logger.info(
            "launch main→store \(mainToStore, format: .fixed(precision: 2))ms store→firstFrame \(storeToFrame, format: .fixed(precision: 2))ms"
        )
        #if DEBUG
        let line = String(
            format: "mainToStore=%.2fms storeToFrame=%.2fms total=%.2fms\n",
            mainToStore,
            storeToFrame,
            mainToStore + storeToFrame
        )
        if let data = line.data(using: .utf8) {
            let url = URL(fileURLWithPath: "/tmp/neat-launch-times.log")
            if FileManager.default.fileExists(atPath: url.path),
               let handle = try? FileHandle(forWritingTo: url) {
                try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
        #endif
    }
}
