//
//  DocumentEntity.swift
//  Markdown Opener
//
//  Created by alfred chen on 21/12/2025.
//


// DocumentEntity.swift
import AppIntents

struct DocumentEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Document with Flashcards"

    static var defaultQuery = DocumentQuery()

    var id: String        // This is the full filename like "MyNotes.md.json"
    var displayName: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(displayName)")
    }
}
