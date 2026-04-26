import Foundation

struct FileInfo: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let size: Int64
    let modified: Date
    let ext: String
}