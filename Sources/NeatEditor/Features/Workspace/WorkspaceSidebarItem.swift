import Foundation

struct WorkspaceSidebarItem: Identifiable, Hashable, Sendable {
    let fileURL: URL
    let modificationDate: Date
    var preview: String
    var fileSize: Int = 0

    var id: URL {
        fileURL
    }

    var title: String {
        fileURL.lastPathComponent
    }
}
