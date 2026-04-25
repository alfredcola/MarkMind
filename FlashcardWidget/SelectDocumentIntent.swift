//
//  SelectDocumentIntent.swift
//  Markdown Opener
//
//  Created by alfred chen on 21/12/2025.
//


// SelectDocumentIntent.swift
import AppIntents

struct SelectDocumentIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Select Document"
    static var description = IntentDescription("Choose which document's flashcards to show in the widget.")

    @Parameter(
        title: "Document",
        description: "Pick a document that has flashcards",
        requestValueDialog: IntentDialog("Which document?")
    )
    var document: DocumentEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Show flashcards from \(\.$document)")
    }
}