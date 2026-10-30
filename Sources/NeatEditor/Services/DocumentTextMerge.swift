import Foundation

/// Conservative three-way reconciliation. Overlapping intentions are retained
/// as separate documents rather than guessed or written as conflict markers.
enum DocumentTextMerge {
    private struct Change: Equatable {
        let range: Range<Int>
        let lines: [String]
    }

    static func merge(base: String, local: String, disk: String) -> String? {
        if local == disk || disk == base { return local }
        if local == base { return disk }

        let original = lines(in: base)
        let localLines = lines(in: local)
        let diskLines = lines(in: disk)
        // Bound worst-case diff work for simultaneously rewritten large files.
        // This falls back to Keep Both, never to dropping content or guessing.
        guard max(original.count, localLines.count, diskLines.count) <= 20_000 else { return nil }
        let localChanges = changes(from: original, to: localLines)
        let diskChanges = changes(from: original, to: diskLines)
        var combined = localChanges
        for incoming in diskChanges {
            if combined.contains(incoming) { continue }
            guard !combined.contains(where: { overlaps($0.range, incoming.range) }) else {
                return nil
            }
            combined.append(incoming)
        }

        var result: [String] = []
        var cursor = 0
        for change in combined.sorted(by: { $0.range.lowerBound < $1.range.lowerBound }) {
            result.append(contentsOf: original[cursor..<change.range.lowerBound])
            result.append(contentsOf: change.lines)
            cursor = change.range.upperBound
        }
        result.append(contentsOf: original[cursor...])
        return result.joined()
    }

    private static func overlaps(_ lhs: Range<Int>, _ rhs: Range<Int>) -> Bool {
        if lhs.isEmpty { return rhs.lowerBound <= lhs.lowerBound && lhs.lowerBound <= rhs.upperBound }
        if rhs.isEmpty { return lhs.lowerBound <= rhs.lowerBound && rhs.lowerBound <= lhs.upperBound }
        return lhs.overlaps(rhs)
    }

    /// Keep terminators in each token, including CRLF as one Character. This
    /// avoids changing a file's line endings merely by merging independent edits.
    private static func lines(in text: String) -> [String] {
        var result: [String] = []
        var start = text.startIndex
        for index in text.indices where text[index].isNewline {
            let end = text.index(after: index)
            result.append(String(text[start..<end]))
            start = end
        }
        if start < text.endIndex { result.append(String(text[start...])) }
        return result
    }

    private static func changes(from base: [String], to target: [String]) -> [Change] {
        let difference = target.difference(from: base)
        var removed = Set<Int>()
        var inserted = Set<Int>()
        for change in difference {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }

        var result: [Change] = []
        var old = 0
        var new = 0
        while old < base.count || new < target.count {
            if removed.contains(old) || inserted.contains(new) {
                let start = old
                var replacement: [String] = []
                while removed.contains(old) || inserted.contains(new) {
                    if removed.contains(old) { old += 1 }
                    if inserted.contains(new) {
                        replacement.append(target[new])
                        new += 1
                    }
                }
                result.append(Change(range: start..<old, lines: replacement))
            } else {
                old += 1
                new += 1
            }
        }
        return result
    }
}
