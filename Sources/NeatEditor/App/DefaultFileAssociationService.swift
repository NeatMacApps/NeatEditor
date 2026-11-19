import Foundation
import UniformTypeIdentifiers
import AppKit

/// File categories that NeatEditor can register as the system default handler.
enum DefaultFileType: String, CaseIterable, Identifiable, Codable, Sendable {
    case plainText
    case markdown

    var id: String { rawValue }

    var contentType: UTType {
        switch self {
        case .plainText:
            .plainText
        case .markdown:
            UTType("net.daringfireball.markdown")
                ?? UTType(filenameExtension: "md")
                ?? .plainText
        }
    }

    var titleLocalizationKey: String {
        switch self {
        case .plainText:
            "defaultApp.type.plainText"
        case .markdown:
            "defaultApp.type.markdown"
        }
    }

    /// Maps an externally opened file URL to a supported file category without reading file bytes.
    static func match(for url: URL) -> DefaultFileType? {
        guard url.isFileURL else {
            return nil
        }

        let name = url.lastPathComponent
        guard !name.isEmpty, name != ".", name != ".." else {
            return nil
        }

        switch url.pathExtension.lowercased() {
        case "txt", "text":
            return .plainText
        case "md", "markdown":
            return .markdown
        case "":
            guard !url.hasDirectoryPath else {
                return nil
            }
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory
            return isDirectory == true ? nil : .plainText
        default:
            return nil
        }
    }
}

/// Live system default-application status for one supported file type.
struct DefaultFileTypeStatus: Equatable, Sendable {
    let fileType: DefaultFileType
    let currentApplicationURL: URL?
    let currentApplicationName: String?
    let isCurrentAppDefault: Bool
}

/// Abstracts LaunchServices / `NSWorkspace` default-application queries and updates for testability.
protocol FileAssociationManaging: Sendable {
    func fetchStatuses(for types: [DefaultFileType]) async -> [DefaultFileType: DefaultFileTypeStatus]
    func setDefaultApplication(for fileType: DefaultFileType) async throws
}

/// Production `NSWorkspace` implementation. Keeps LaunchServices queries off the main actor.
struct SystemFileAssociationService: FileAssociationManaging {
    let applicationURL: URL
    let bundleIdentifier: String?

    init(
        applicationURL: URL = Bundle.main.bundleURL,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) {
        self.applicationURL = applicationURL
        self.bundleIdentifier = bundleIdentifier
    }

    func fetchStatuses(for types: [DefaultFileType]) async -> [DefaultFileType: DefaultFileTypeStatus] {
        let appURL = applicationURL
        let bundleID = bundleIdentifier
        return await Task.detached(priority: .utility) {
            var statuses: [DefaultFileType: DefaultFileTypeStatus] = [:]
            statuses.reserveCapacity(types.count)
            for fileType in types {
                let handlerURL = NSWorkspace.shared.urlForApplication(toOpen: fileType.contentType)
                if let handlerURL {
                    let isDefault = Self.isCurrentApplication(
                        handlerURL: handlerURL,
                        applicationURL: appURL,
                        bundleIdentifier: bundleID
                    )
                    statuses[fileType] = DefaultFileTypeStatus(
                        fileType: fileType,
                        currentApplicationURL: handlerURL,
                        currentApplicationName: Self.displayName(for: handlerURL),
                        isCurrentAppDefault: isDefault
                    )
                } else {
                    statuses[fileType] = DefaultFileTypeStatus(
                        fileType: fileType,
                        currentApplicationURL: nil,
                        currentApplicationName: nil,
                        isCurrentAppDefault: false
                    )
                }
            }
            return statuses
        }.value
    }

    func setDefaultApplication(for fileType: DefaultFileType) async throws {
        try await NSWorkspace.shared.setDefaultApplication(
            at: applicationURL,
            toOpen: fileType.contentType
        )
    }

    static func displayName(for applicationURL: URL) -> String {
        let rawName = FileManager.default.displayName(atPath: applicationURL.path)
        let candidate = rawName.isEmpty
            ? applicationURL.deletingPathExtension().lastPathComponent
            : rawName
        if candidate.lowercased().hasSuffix(".app") && candidate.count > 4 {
            return String(candidate.dropLast(4))
        }
        return candidate
    }

    static func isCurrentApplication(
        handlerURL: URL,
        applicationURL: URL,
        bundleIdentifier: String?,
        handlerBundleIdentifier: (URL) -> String? = { Bundle(url: $0)?.bundleIdentifier }
    ) -> Bool {
        if let bundleIdentifier, !bundleIdentifier.isEmpty,
           let resolvedID = handlerBundleIdentifier(handlerURL),
           resolvedID == bundleIdentifier {
            return true
        }
        return handlerURL.resolvingSymlinksInPath().standardizedFileURL
            == applicationURL.resolvingSymlinksInPath().standardizedFileURL
    }
}
