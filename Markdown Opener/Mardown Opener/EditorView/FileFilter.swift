//
//  FileFilter.swift
//  Markdown Opener
//
//  Created by alfred chen on 8/3/2026.
//


import SwiftUI
// MARK: - File Filter
enum FileFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case markdown = "MD"
    case text = "TXT"
    case pdf = "PDF"
    case docx = "DOCX"
    case pptx = "PPTX"

    var id: String { rawValue }

    var group: FileGroup? {
        switch self {
        case .all: return nil
        case .markdown: return .markdown
        case .text: return .text
        case .pdf: return .pdf
        case .docx: return .docx
        case .pptx: return .pptx
        }
    }
}

// MARK: - File Group
enum FileGroup: String, CaseIterable {
    case markdown = "Markdown"
    case text = "Text Files"
    case pdf = "PDF"
    case docx = "Word"
    case pptx = "PowerPoint"
    case other = "Other"
}

// MARK: - Expandable Section
enum ExpandableSection: Hashable {
    case starred
    case tag(Tag)
    case fileGroup(FileGroup)

    func hash(into hasher: inout Hasher) {
        switch self {
        case .starred:
            hasher.combine("starred")
        case .tag(let tag):
            hasher.combine("tag")
            hasher.combine(tag.id)
        case .fileGroup(let g):
            hasher.combine("fileGroup")
            hasher.combine(g.rawValue)
        }
    }

    static func == (lhs: ExpandableSection, rhs: ExpandableSection) -> Bool
    {
        switch (lhs, rhs) {
        case (.starred, .starred): return true
        case (.tag(let l), .tag(let r)): return l.id == r.id
        case (.fileGroup(let l), .fileGroup(let r)): return l == r
        default: return false
        }
    }
}

// MARK: - File Info
struct FileInfo: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let size: Int64
    let modified: Date
    let ext: String
}
