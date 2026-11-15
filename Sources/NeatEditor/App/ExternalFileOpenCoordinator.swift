import Foundation
import AppKit

@MainActor
final class ExternalFileOpenCoordinator {
    static let shared = ExternalFileOpenCoordinator()

    var handler: (([URL]) -> Void)? {
        didSet {
            flushPendingFilesIfNeeded()
        }
    }

    private var pendingFileURLs: [URL] = []

    var saveBeforeTermination: (@MainActor () -> Bool)?

    private init() {}

    func enqueue(_ urls: [URL]) {
        let fileURLs = urls.filter(\.isFileURL)
        guard !fileURLs.isEmpty else {
            return
        }

        if let handler {
            handler(fileURLs)
            return
        }

        pendingFileURLs.append(contentsOf: fileURLs)
    }

    private func flushPendingFilesIfNeeded() {
        guard let handler, !pendingFileURLs.isEmpty else {
            return
        }

        let queuedFileURLs = pendingFileURLs
        pendingFileURLs.removeAll()
        handler(queuedFileURLs)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // A background launch never activates, so the SwiftUI scene window is
        // not created. The E2E launch presents its own window instead.
        E2ETestWindow.presentIfNeeded()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        ExternalFileOpenCoordinator.shared.saveBeforeTermination?() == false
            ? .terminateCancel
            : .terminateNow
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        ExternalFileOpenCoordinator.shared.enqueue(urls)
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let fileURLs = filenames.map { URL(fileURLWithPath: $0) }
        ExternalFileOpenCoordinator.shared.enqueue(fileURLs)
        sender.reply(toOpenOrPrint: .success)
    }
}
