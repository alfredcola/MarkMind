//
//  CloudPath.swift
//  MarkMind
//
//  Path utilities for GCS-only file structure
//

import Foundation

enum CloudPath {
    static let documentsPrefix = "documents"
    static let metadataPrefix = ".metadata"

    static func documentPath(_ filename: String) -> String {
        "\(documentsPrefix)/\(filename)"
    }

    static func metadataPath(for fileId: String) -> String {
        "\(metadataPrefix)/\(fileId)"
    }

    static func companionPath(fileId: String, type: CompanionType) -> String {
        "\(metadataPrefix)/\(fileId)/\(type.filename)"
    }

    static func extractFilename(from path: String) -> String? {
        guard path.hasPrefix("\(documentsPrefix)/") else { return nil }
        let remainder = String(path.dropFirst(documentsPrefix.count + 1))
        return remainder.isEmpty ? nil : remainder
    }

    static func extractFileId(fromMetadataPath path: String) -> String? {
        guard path.hasPrefix("\(metadataPrefix)/") else { return nil }
        let withoutPrefix = String(path.dropFirst(metadataPrefix.count + 1))
        let components = withoutPrefix.split(separator: "/", maxSplits: 1)
        guard let first = components.first else { return nil }
        return String(first)
    }

    static func sanitizeFilename(_ name: String) -> String {
        var sanitized = name.replacingOccurrences(
            of: "[\\\\/]",
            with: "-",
            options: .regularExpression
        )
        sanitized = sanitized.replacingOccurrences(
            of: ":",
            with: "-"
        )
        sanitized = sanitized.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        sanitized = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized
    }

    enum CompanionType: String {
        case chat
        case flashcards
        case mccards

        var filename: String {
            switch self {
            case .chat: return "chat.json"
            case .flashcards: return "flashcards.json"
            case .mccards: return "mccards.json"
            }
        }

        var displayName: String {
            switch self {
            case .chat: return "Chat"
            case .flashcards: return "Flashcards"
            case .mccards: return "Multiple Choice"
            }
        }
    }
}

struct CloudFileInfo: Identifiable, Codable, Hashable {
    let id: String
    let path: String
    let name: String
    let size: Int64
    let modified: Date
    let isDirectory: Bool

    var filename: String {
        (path as NSString).lastPathComponent
    }

    var fileExtension: String {
        (path as NSString).pathExtension
    }

    static func == (lhs: CloudFileInfo, rhs: CloudFileInfo) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct FileIdInfo: Identifiable, Codable {
    var id: String { fileId }
    let fileId: String
    let path: String
    let name: String
    let createdAt: Date
    let modifiedAt: Date
}
