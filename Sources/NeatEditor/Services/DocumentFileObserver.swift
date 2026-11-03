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
    func presentedItemDidMove(to newURL: URL) { onChange(.moved(newURL)) }

    func accommodatePresentedItemDeletion(completionHandler: @escaping (Error?) -> Void) {
        onChange(.deleted)
        completionHandler(nil)
    }

    /// Atomic replacement changes the inode, not the presented document's identity.
    /// Re-arm its vnode source without churning native presenter registration.
    func refreshFileObservation() {
        if let presentedItemURL { watch(presentedItemURL) }
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
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .attrib, .extend, .link, .revoke],
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
                        self.onChange(.moved(movedURL))
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
