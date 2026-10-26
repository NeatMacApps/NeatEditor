import Foundation
import Observation

enum EditorCharacterCountLayout {
    /// Keeps the final line above the floating count at maximum scroll.
    static let reservedBottomInset: CGFloat = 24
    static let trailingInset: CGFloat = 16
    static let bottomInset: CGFloat = 6
}

/// Counts whole-document graphemes off the typing path.
actor EditorCharacterCountWorker {
    private var cachedText: String?
    private var cachedCount = 0

    func count(text: String) throws -> Int {
        try Task.checkCancellation()
        if cachedText == text {
            return cachedCount
        }
        let count = text.count
        try Task.checkCancellation()
        cachedText = text
        cachedCount = count
        return count
    }
}

@MainActor @Observable
final class EditorCharacterCountModel {
    private(set) var tabID: UUID?
    private(set) var characters: Int?
    @ObservationIgnored private let worker = EditorCharacterCountWorker()
    @ObservationIgnored private var pendingUpdate: Task<Void, Never>?
    @ObservationIgnored private var requestID = UUID()

    func count(for tabID: UUID) -> Int? {
        self.tabID == tabID ? characters : nil
    }

    @discardableResult
    func update(tabID: UUID, text: String) -> Task<Void, Never> {
        pendingUpdate?.cancel()
        if self.tabID != tabID {
            self.tabID = tabID
            characters = nil
        }
        let requestID = UUID()
        self.requestID = requestID
        let worker = worker
        let task = Task { [weak self] in
            do {
                let count = try await worker.count(text: text)
                guard !Task.isCancelled, let self, self.requestID == requestID else { return }
                characters = count
            } catch is CancellationError {
                // A newer edit or tab switch owns the next published count.
            } catch {
                assertionFailure("Unexpected editor character count failure: \(error)")
            }
        }
        pendingUpdate = task
        return task
    }
}
