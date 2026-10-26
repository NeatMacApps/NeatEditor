import Foundation
import Observation

struct EditorStatusSnapshot: Equatable, Sendable {
    var characters = 0
    var nonWhitespaceCharacters = 0
    var words = 0
    var lines = 1
    var selectedCharacters = 0
    var line = 1
    var column = 1
}

/// Keeps full-document counting off the typing path and reuses it for cursor moves.
actor EditorStatusWorker {
    private var cachedText: String?
    private var cachedCounts = EditorStatusSnapshot()
    private var lineStarts = [0]

    func snapshot(text: String, selection: NSRange) throws -> EditorStatusSnapshot {
        try Task.checkCancellation()
        if cachedText != text {
            var counts = EditorStatusSnapshot()
            var starts = [0]
            var offset = 0
            for character in text {
                if counts.characters.isMultiple(of: 4096) {
                    try Task.checkCancellation()
                }
                counts.characters += 1
                if !character.isWhitespace {
                    counts.nonWhitespaceCharacters += 1
                }
                offset += character.utf16.count
                if character.isNewline {
                    starts.append(offset)
                }
            }
            counts.lines = starts.count
            text.enumerateSubstrings(
                in: text.startIndex..<text.endIndex,
                options: [.byWords, .substringNotRequired]
            ) { _, _, _, stop in
                if Task.isCancelled {
                    stop = true
                } else {
                    counts.words += 1
                }
            }
            try Task.checkCancellation()
            cachedText = text
            cachedCounts = counts
            lineStarts = starts
        }

        let source = text as NSString
        let location = selection.location == NSNotFound ? 0 : selection.location.clamped(to: 0...source.length)
        let length = selection.length.clamped(to: 0...(source.length - location))
        var result = cachedCounts
        result.selectedCharacters = source.substring(with: NSRange(location: location, length: length)).count

        var lower = 0
        var upper = lineStarts.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if lineStarts[middle] <= location {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        let lineIndex = max(0, lower - 1)
        result.line = lineIndex + 1
        result.column = source.substring(with: NSRange(
            location: lineStarts[lineIndex], length: location - lineStarts[lineIndex]
        )).count + 1
        return result
    }
}

@MainActor @Observable
final class EditorStatusModel {
    private(set) var tabID: UUID?
    private(set) var snapshot: EditorStatusSnapshot?
    @ObservationIgnored private let worker = EditorStatusWorker()
    @ObservationIgnored private var pendingUpdate: Task<Void, Never>?
    @ObservationIgnored private var requestID = UUID()

    @discardableResult
    func update(tabID: UUID, text: String, selection: NSRange) -> Task<Void, Never> {
        pendingUpdate?.cancel()
        if self.tabID != tabID {
            self.tabID = tabID
            snapshot = nil
        }
        let requestID = UUID()
        self.requestID = requestID
        let worker = worker
        let task = Task { [weak self] in
            do {
                let result = try await worker.snapshot(text: text, selection: selection)
                guard !Task.isCancelled, let self, self.requestID == requestID else { return }
                snapshot = result
            } catch is CancellationError {
                // A newer edit or selection owns the next published snapshot.
            } catch {
                assertionFailure("Unexpected editor statistics failure: \(error)")
            }
        }
        pendingUpdate = task
        return task
    }
}
