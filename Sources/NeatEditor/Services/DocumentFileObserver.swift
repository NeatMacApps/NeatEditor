import Foundation
import Synchronization
import Darwin

/// Presenter notifications cover coordinated writers; vnode sources also cover
/// direct writes and parent-directory replacement. Neither is treated as a log.
final class DocumentFileObserver: NSObject, NSFilePresenter, Sendable {
    enum Event: Sendable {
        case changed
        case moved(URL)
        case deleted
    }

    let presentedItemURL: URL?
    let presentedItemOperationQueue: OperationQueue
    private let onChange: @Sendable (Event) -> Void
    private struct FileIdentity: Equatable {
        let device: dev_t
        let inode: ino_t
    }

    private struct ObservationState {
        var isStopped = false
        var fileIdentity: FileIdentity?
        var sources: [URL: any DispatchSourceFileSystemObject] = [:]
    }
    private let state = Mutex(ObservationState())

    /// Long enough for a safe-save writer to recreate the original path, short
    /// enough that a genuine external rename is followed without a visible stall.
    private static let moveSettleInterval = 0.2

    init(url: URL, onChange: @escaping @Sendable (Event) -> Void) {
        self.presentedItemURL = url
        self.onChange = onChange
        let queue = OperationQueue()
        queue.name = "com.x0c.NeatEditor.presenter"
        queue.maxConcurrentOperationCount = 1
        self.presentedItemOperationQueue = queue
        super.init()
        NSFileCoordinator.addFilePresenter(self)
        watch(url)
        watch(url.deletingLastPathComponent())
    }

    func presentedItemDidChange() { onChange(.changed) }
    func presentedItemDidGain(_ version: NSFileVersion) { onChange(.changed) }
    func presentedItemDidResolveConflict(_ version: NSFileVersion) { onChange(.changed) }
    func presentedItemDidMove(to newURL: URL) {
        guard let source = presentedItemURL, source != newURL else {
            onChange(.changed)
            return
        }
        resolvePossibleMove(from: source, to: newURL)
    }

    func accommodatePresentedItemDeletion(completionHandler: @escaping (Error?) -> Void) {
        onChange(.deleted)
        completionHandler(nil)
    }

    /// Atomic replacement changes the inode, not the presented document's identity.
    /// Re-arm its vnode source without churning native presenter registration.
    func refreshFileObservation() {
        if let presentedItemURL { watch(presentedItemURL) }
    }

    /// A safe save moves the old file aside and recreates the original path.
    /// TextEdit, for example, moves the document to `<name>.sb-<token>` while it
    /// writes the replacement and removes that backup afterwards (reproduced
    /// 2026-11-07). Publishing that intermediate move would retarget the tab at
    /// a path the writer deletes moments later, so a move is only reported once
    /// the writer has settled and the original path stays absent.
    private func resolvePossibleMove(from source: URL, to destination: URL) {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Self.moveSettleInterval) {
            [weak self] in
            guard let self, !self.state.withLock({ $0.isStopped }) else { return }
            let manager = FileManager()
            if manager.fileExists(atPath: source.path) {
                // The original survives: this was a replacement, not a rename.
                self.onChange(.changed)
            } else if manager.fileExists(atPath: destination.path) {
                self.onChange(.moved(destination))
            } else {
                // Both paths are gone (coalesced replace-and-move); let
                // reconciliation report the missing source instead of
                // publishing a location that does not exist.
                self.onChange(.changed)
            }
        }
    }

    func stop() {
        let sources = state.withLock { state -> [any DispatchSourceFileSystemObject]? in
            guard !state.isStopped else { return nil }
            state.isStopped = true
            let sources = Array(state.sources.values)
            state.sources.removeAll()
            return sources
        }
        guard let sources else { return }
        NSFileCoordinator.removeFilePresenter(self)
        for source in sources { source.cancel() }
    }

    private func watch(_ url: URL) {
        let descriptor = open(url.path, O_EVTONLY | O_CLOEXEC)
        guard descriptor >= 0 else { return }
        // Attribute-only iCloud events can be caused by coordination itself.
        // They do not imply a text change and must not feed another reconcile.
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .extend, .link, .revoke],
            queue: .global(qos: .utility)
        )
        source.setEventHandler { [weak self, weak source] in
            guard let self, let source,
                  !self.canIgnoreDirectoryEvent(source.data, at: url) else { return }
            if url == self.presentedItemURL, source.data.contains(.rename) {
                var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
                if fcntl(descriptor, F_GETPATH, &path) == 0 {
                    let bytes = path.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }
                    let movedURL = URL(fileURLWithPath: String(decoding: bytes, as: UTF8.self))
                    if movedURL != url, FileManager().fileExists(atPath: movedURL.path) {
                        self.resolvePossibleMove(from: url, to: movedURL)
                        return
                    }
                }
            }
            self.onChange(.changed)
        }
        source.setCancelHandler { close(descriptor) }
        var info = stat()
        let identity = url == presentedItemURL && fstat(descriptor, &info) == 0
            ? FileIdentity(device: info.st_dev, inode: info.st_ino) : nil
        let needsReconciliation = install(source, at: url, identity: identity)
        // A canceled source must also be resumed so its close handler runs.
        source.resume()
        if needsReconciliation { onChange(.changed) }
    }

    private func install(
        _ source: any DispatchSourceFileSystemObject, at url: URL, identity: FileIdentity?
    ) -> Bool {
        state.withLock { state in
            guard !state.isStopped else { source.cancel(); return false }
            state.sources.updateValue(source, forKey: url)?.cancel()
            guard url == presentedItemURL else { return false }
            let changed = state.fileIdentity != nil && state.fileIdentity != identity
            state.fileIdentity = identity
            return changed
        }
    }

    private func canIgnoreDirectoryEvent(_ event: DispatchSource.FileSystemEvent, at url: URL) -> Bool {
        let snapshot = state.withLock { ($0.isStopped, $0.fileIdentity) }
        if snapshot.0 { return true }
        guard url != presentedItemURL, event == .write,
              let target = presentedItemURL, let identity = snapshot.1 else { return false }
        var info = stat()
        let result = target.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return fstatat(AT_FDCWD, path, &info, 0)
        }
        return result == 0 && FileIdentity(device: info.st_dev, inode: info.st_ino) == identity
    }
}
