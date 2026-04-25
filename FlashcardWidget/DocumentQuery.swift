//
//  DocumentQuery.swift
//  Markdown Opener
//

import AppIntents
import WidgetKit

struct DocumentQuery: EntityQuery {
    func entities(for identifiers: [DocumentEntity.ID]) async throws -> [DocumentEntity] {
        try await suggestedEntities().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [DocumentEntity] {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.alfredchen.MarkdownOpener"
        ) else { return [] }

        let fileManager = FileManager.default

        var files: [String] = []
        do {
            files = try fileManager.contentsOfDirectory(atPath: containerURL.path)
        } catch {
            print("Widget Query: Can't read shared container - \(error)")
            return []
        }

        var entities: [DocumentEntity] = []

        for filename in files {
            // Only look for .json files saved by "Add to Widget"
            guard filename.hasSuffix(".json") else { continue }

            let jsonURL = containerURL.appendingPathComponent(filename)

            guard let data = try? Data(contentsOf: jsonURL),
                  let cards = try? JSONDecoder().decode([Flashcard].self, from: data),
                  !cards.isEmpty else {
                continue
            }

            // Remove ".json" from display name
            let displayName = String(filename.dropLast(5))  // "MyNotes.md.json" → "MyNotes.md"

            entities.append(DocumentEntity(id: filename, displayName: displayName))
        }

        return entities.sorted { $0.displayName < $1.displayName }
    }

    func defaultResult() async -> DocumentEntity? {
        try? await suggestedEntities().first
    }
}
