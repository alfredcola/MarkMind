//
//  SharedContainer.swift
//  Markdown Opener
//
//  Created by alfred chen on 21/12/2025.
//


// SharedContainer.swift
import Foundation
import SwiftUI

struct SharedContainer {
    static let groupIdentifier = "group.com.alfredchen.MarkdownOpener"  // ← Change ONLY if your App Group name is different

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)
    }

    static var documentsURL: URL? {
        containerURL?.appendingPathComponent("Documents", isDirectory: true)
    }

    static var flashcardsURL: URL? {
        containerURL?.appendingPathComponent("Flashcards", isDirectory: true)
    }

    static func ensureDirectories() {
        guard let container = containerURL else { return }

        let docs = container.appendingPathComponent("Documents", isDirectory: true)
        let flashcards = container.appendingPathComponent("Flashcards", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        } catch {
        }
        do {
            try FileManager.default.createDirectory(at: flashcards, withIntermediateDirectories: true)
        } catch {
        }
    }
}
