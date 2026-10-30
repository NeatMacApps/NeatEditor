import Foundation
import Synchronization

/// One FIFO lane shared by copies of the persistence facade. Enqueue happens
/// synchronously, so a lifecycle flush cannot overtake an older autosave.
final class DocumentFileAccess: Sendable {
    struct State {
        var bindings: [UUID: URL] = [:]
        var accepted: [URL: String] = [:]
        var written: [URL: String] = [:]
    }

    let state = Mutex(State())
    private let manager: Mutex<FileManager>

    init(manager: sending FileManager) {
        self.manager = Mutex(manager)
    }

    func withFileManager<T: Sendable>(_ operation: @Sendable (FileManager) throws -> T) rethrows -> T {
        try manager.withLock { try operation($0) }
    }
    private let queue = DispatchQueue(label: "com.x0c.NeatEditor.files", qos: .userInitiated)

    func sync<T>(_ operation: () throws -> T) rethrows -> T {
        try queue.sync(execute: operation)
    }

    func enqueue(_ operation: @escaping @Sendable () -> Void) {
        queue.async(execute: operation)
    }
}
