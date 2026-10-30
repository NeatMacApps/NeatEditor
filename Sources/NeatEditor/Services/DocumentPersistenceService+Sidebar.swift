import Foundation

extension DocumentPersistenceService {
    struct SidebarFileInfo: Hashable, Sendable {
        let fileURL: URL
        let modificationDate: Date
        let fileSize: Int
    }

    /// File types shown in the workspace sidebar. Lowercased path extensions.
    static let sidebarSupportedExtensions: Set<String> = ["md", "markdown", "txt", "text"]

    private enum SidebarPreview {
        static let maxLines = 3
        static let maxBytes = 64 * 1024
        static let maxCharacters = 1000
        static let headCharacters = 4096
    }

    /// Extensionless files are only listed when their head looks like plain
    /// UTF-8 text. The bound keeps the probe cheap for large binaries.
    private static let textSniffByteCount = 4 * 1024

    /// Missing app-owned directories are normal before the first save.
    /// Other enumeration errors must remain distinguishable from an empty list.
    func sidebarTextFiles() throws -> [SidebarFileInfo] {
        try sidebarTextFiles(in: defaultDirectory)
    }

    /// Lists regular text files in `directory`: the supported extensions plus
    /// extensionless files whose head looks like plain UTF-8 text. Hidden
    /// entries, directories, binaries and unpublished staging files are
    /// skipped so a sidebar row always opens as editable text.
    func sidebarTextFiles(in directory: URL) throws -> [SidebarFileInfo] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        let urls: [URL]
        do {
            urls = try withFileManager {
                try $0.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
            }
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return []
        }

        var infos: [SidebarFileInfo] = []
        infos.reserveCapacity(urls.count)
        var seen = Set<URL>()
        for url in urls {
            if url.lastPathComponent.hasPrefix(".neateditor-staging-") {
                continue
            }
            let pathExtension = url.pathExtension
            let hasSupportedExtension = Self.sidebarSupportedExtensions.contains(
                pathExtension.lowercased()
            )
            guard hasSupportedExtension || pathExtension.isEmpty else {
                continue
            }
            let values = try url.resourceValues(forKeys: keys)
            let fileURL = normalizedFileURL(for: url)
            guard values.isRegularFile == true, seen.insert(fileURL).inserted else {
                continue
            }
            if !hasSupportedExtension,
               !Self.isLikelyTextFile(at: fileURL) {
                continue
            }
            infos.append(SidebarFileInfo(
                fileURL: fileURL,
                modificationDate: values.contentModificationDate ?? .distantPast,
                fileSize: values.fileSize ?? 0
            ))
        }
        // Pre-extract the display name once per file: the old comparator
        // recomputed `lastPathComponent` on every comparison (O(N log N)
        // extractions). Sorting on precomputed keys keeps the exact same
        // order (natural descending, path fallback).
        let keyed = infos.map { ($0.fileURL.lastPathComponent, $0) }
        return keyed.sorted { lhs, rhs in
            let comparison = lhs.0.localizedStandardCompare(rhs.0)
            if comparison != .orderedSame {
                return comparison == .orderedDescending
            }
            return lhs.1.fileURL.path > rhs.1.fileURL.path
        }.map(\.1)
    }

    /// Copies documents left in the pre-folder app library into `directory`.
    /// Existing names are never overwritten and the originals are never
    /// moved or deleted, so a failed migration can only leave files behind.
    /// Returns the copy count only when all candidates are copied or already
    /// present. Any read/copy failure returns `nil` so migration is retried.
    func migrateLegacyAppDocumentsIfNeeded(into directory: URL) -> Int? {
        let destination = normalizedFileURL(for: directory)
        guard normalizedFileURL(for: appLibraryDirectory) != destination else {
            return 0
        }
        let legacyFiles: [SidebarFileInfo]
        do {
            legacyFiles = try sidebarTextFiles(in: appLibraryDirectory)
        } catch {
            return nil
        }
        guard !legacyFiles.isEmpty else {
            return 0
        }

        var copiedCount = 0
        var hasFailedCopy = false
        for info in legacyFiles {
            let destinationURL = destination.appendingPathComponent(
                info.fileURL.lastPathComponent
            )
            guard !withFileManager({ $0.fileExists(atPath: destinationURL.path) }) else {
                continue
            }
            do {
                try withFileManager { try $0.copyItem(at: info.fileURL, to: destinationURL) }
                copiedCount += 1
            } catch where isFileExistsError(error) {
                // Another writer claimed this name; its content stays intact.
                continue
            } catch {
                // Attempt the rest, but never mark a partial migration complete.
                hasFailedCopy = true
            }
        }
        return hasFailedCopy ? nil : copiedCount
    }

    /// Extensionless candidates get a bounded probe: NUL bytes and invalid
    /// UTF-8 sequences mark a binary. A truncated sequence at the 4 KiB
    /// boundary is accepted because the read may split a character.
    static func isLikelyTextFile(
        at fileURL: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return false
        }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: textSniffByteCount) else {
            return false
        }
        guard !data.isEmpty else {
            return true
        }
        guard !data.contains(0) else {
            return false
        }
        return isUTF8Prefix(data)
    }

    private static func isUTF8Prefix(_ data: Data) -> Bool {
        let bytes = [UInt8](data)
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            let length: Int
            switch byte {
            case 0x00...0x7F:
                length = 1
            case 0xC2...0xDF:
                length = 2
            case 0xE0...0xEF:
                length = 3
            case 0xF0...0xF4:
                length = 4
            default:
                return false
            }

            if index + length > bytes.count {
                // A character split by the sniff boundary is still text.
                return true
            }
            var offset = 1
            while offset < length {
                if bytes[index + offset] & 0xC0 != 0x80 {
                    return false
                }
                offset += 1
            }
            index += length
        }
        return true
    }

    /// Short preview excerpt for a sidebar row: the first lines of content.
    /// Pure string transform so rows stay live while typing without disk I/O.
    /// Only scans a small head of the buffer so per-keystroke updates stay cheap.
    static func sidebarPreviewExcerpt(from content: String, maxLines: Int = SidebarPreview.maxLines) -> String {
        let excerpt = String(content.prefix(SidebarPreview.headCharacters))
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .prefix(max(1, maxLines))
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard excerpt.count > SidebarPreview.maxCharacters else {
            return excerpt
        }
        return String(excerpt.prefix(SidebarPreview.maxCharacters))
    }

    /// Reads only a small prefix of the file for preview purposes. Never
    /// throws: missing/unreadable files yield an empty preview and the row
    /// falls back to its placeholder.
    func sidebarPreview(
        for fileURL: URL,
        maxLines: Int = SidebarPreview.maxLines
    ) -> String {
        guard let data = sidebarPrefixData(for: fileURL) else {
            return ""
        }
        let content: String
        if let strict = String(data: data, encoding: .utf8) {
            content = strict
        } else {
            content = String(decoding: data, as: UTF8.self)
        }
        return Self.sidebarPreviewExcerpt(from: content, maxLines: maxLines)
    }

    private func sidebarPrefixData(for fileURL: URL) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return nil
        }
        defer { try? handle.close() }
        return try? handle.read(upToCount: SidebarPreview.maxBytes)
    }

    /// Closed files use exactly the same validation and collision policy as tabs.
    func renameSidebarFile(at fileURL: URL, to newTitle: String) throws -> URL {
        let sourceURL = normalizedFileURL(for: fileURL)
        let tab = EditorTab(title: sourceURL.lastPathComponent, fileURL: sourceURL)
        return try rename(tab: tab, to: newTitle).fileURL ?? sourceURL
    }

    /// Live text is staged completely before exclusive publication. Unopened
    /// files use FileManager copying so their full content isn't read into memory.
    func duplicateSidebarFile(at fileURL: URL, content: String? = nil) throws -> URL {
        let sourceURL = normalizedFileURL(for: fileURL)
        let pathExtension = sourceURL.pathExtension
        let baseName = (sourceURL.lastPathComponent as NSString).deletingPathExtension
        let copyName = pathExtension.isEmpty
            ? "\(baseName) copy"
            : "\(baseName) copy.\(pathExtension)"
        if let content {
            return try exclusivePublish(
                data: Data(content.utf8),
                named: copyName,
                in: sourceURL.deletingLastPathComponent()
            )
        }
        return try publishFile(
            named: copyName,
            in: sourceURL.deletingLastPathComponent()
        ) { destination in
            try withFileManager { try $0.copyItem(at: sourceURL, to: destination) }
        }
    }
}
