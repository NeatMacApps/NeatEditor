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
    private let sources = Mutex<[any DispatchSourceFileSystemObject]>([])
    private let stopped = Mutex(false)

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

    func stop() {
        let wasStopped = stopped.withLock { value in
            let old = value
            value = true
            return old
        }
        guard !wasStopped else { return }
        NSFileCoordinator.removeFilePresenter(self)
        sources.withLock { sources in
            for source in sources { source.cancel() }
            sources.removeAll()
        }
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
            guard let self, let source else { return }
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
        sources.withLock { $0.append(source) }
        source.resume()
    }
}
