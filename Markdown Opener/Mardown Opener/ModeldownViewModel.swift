//
//  MarkdownRepository.swift
//  Markdown Opener
//
//  Created by alfred chen on 9/11/2025.
//

import Combine
import Foundation
import PDFKit
import SwiftUI
import ZIPFoundation

// MARK: - Document Data
struct DocumentData {
    let text: String
    let attributed: NSAttributedString?
    let pdf: PDFDocument?
}

// MARK: - Document Repository Protocol
protocol DocumentRepository {
    func listDocuments() throws -> [URL]
    func load(_ url: URL) throws -> DocumentData
    @discardableResult func save(content: String, to url: URL) throws -> URL
    @discardableResult func saveAs(content: String, suggestedName: String?)
        throws -> URL
    @discardableResult func importIntoLibrary(from externalURL: URL) throws
        -> URL
    func delete(_ url: URL) throws
    func rename(_ url: URL, to newName: String) throws -> URL
}

enum DocxPlainTextExtractor {
    static func extract(from url: URL) throws -> String {
        // DOCX is a zip. Extract word/document.xml and strip tags to text.
        let fm = FileManager.default
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(
                "docx-\(UUID().uuidString)",
                isDirectory: true
            )
        try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmpDir) }

        guard let archive = Archive(url: url, accessMode: .read) else {
            throw NSError(
                domain: "DOCX",
                code: -1,
                userInfo: [
                    NSLocalizedDescriptionKey: "Cannot read DOCX archive"
                ]
            )
        }
        var xmlData = Data()
        for entry in archive {
            if entry.path == "word/document.xml" {
                _ = try archive.extract(entry) { data in xmlData.append(data) }
                break
            }
        }
        guard !xmlData.isEmpty else {
            return ""  // fallback: no content
        }
        // Very naive XML to text: remove tags and decode entities.
        var s = String(data: xmlData, encoding: .utf8) ?? ""
        // Replace paragraph/line break tags with newlines to keep some structure.
        s = s.replacingOccurrences(of: "</w:p>", with: "\n")
        s = s.replacingOccurrences(of: "<w:tab/>", with: "\t")
        // Strip all tags.
        s = s.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )
        // Collapse multiple blank lines.
        s = s.replacingOccurrences(
            of: "\\n{3,}",
            with: "\n\n",
            options: .regularExpression
        )
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum PPTXPlainTextExtractor {
    static func extract(from url: URL) throws -> String {
        let ext = url.pathExtension.lowercased()
        let fm = FileManager.default
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pptx-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmpDir) }

        // Handle .ppt (legacy binary format) as unsupported
        if ext == "ppt" {
            return "" // Return empty string for .ppt; could return "Unsupported .ppt format" if UI needs a placeholder
        }

        // Handle .pptx (ZIP-based)
        guard ext == "pptx",
              let archive = Archive(url: url, accessMode: .read) else {
            throw NSError(
                domain: "PPTX",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Cannot read PPTX archive"]
            )
        }

        // Collect text from all slides (ppt/slides/slide*.xml)
        var slideTexts: [String] = []
        for entry in archive {
            if entry.path.hasPrefix("ppt/slides/slide") && entry.path.hasSuffix(".xml") {
                var xmlData = Data()
                _ = try archive.extract(entry) { data in xmlData.append(data) }
                guard let xmlString = String(data: xmlData, encoding: .utf8) else { continue }
                
                // Naive XML to text: strip tags, keep some structure
                var text = xmlString
                // Replace paragraph breaks with newlines
                text = text.replacingOccurrences(of: "</a:p>", with: "\n")
                // Strip all XML tags
                text = text.replacingOccurrences(
                    of: "<[^>]+>",
                    with: "",
                    options: .regularExpression
                )
                // Collapse multiple newlines
                text = text.replacingOccurrences(
                    of: "\\n{3,}",
                    with: "\n\n",
                    options: .regularExpression
                )
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    slideTexts.append(trimmed)
                }
            }
        }

        return slideTexts.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Document Store
final class DocumentStore: DocumentRepository, ObservableObject {
    static let shared = DocumentStore()

    var documentsURL: URL {
        if let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            return url
        }
        let paths = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
        guard let path = paths.first else {
            return URL(fileURLWithPath: NSHomeDirectory())
        }
        return URL(fileURLWithPath: path)
    }

    func listDocuments() throws -> [URL] {
        let fm = FileManager.default
        let items = try fm.contentsOfDirectory(
            at: documentsURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        return items
            .filter {
                ["md", "txt", "pdf", "docx", "ppt", "pptx"].contains($0.pathExtension.lowercased())
            }
            .sorted { (a, b) in
                let ad = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let bd = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return ad > bd
            }
    }
    


    func load(_ url: URL) throws -> DocumentData {
        let ext = url.pathExtension.lowercased()
        if ext == "md" || ext == "txt" {
            let text = try String(contentsOf: url, encoding: .utf8)
            return DocumentData(text: text, attributed: nil, pdf: nil)
        } else if ext == "docx" {
            let text = try DocxPlainTextExtractor.extract(from: url)
            return DocumentData(text: text, attributed: nil, pdf: nil)
        } else if ext == "ppt" || ext == "pptx" {
            let text = try PPTXPlainTextExtractor.extract(from: url)
            return DocumentData(text: text, attributed: nil, pdf: nil)
        } else if ext == "pdf" {
            guard let doc = PDFDocument(url: url) else {
                throw NSError(
                    domain: "PDF",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Cannot open PDF"]
                )
            }
            var text = ""
            for i in 0..<doc.pageCount {
                if let page = doc.page(at: i), let t = page.string {
                    text.append(t + "\n")
                }
            }
            return DocumentData(text: text, attributed: nil, pdf: doc)
        } else {
            throw NSError(
                domain: "Unsupported",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Unsupported file type"]
            )
        }
    }

    @discardableResult
    func save(content: String, to url: URL) throws -> URL {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true
        )
        let ext = url.pathExtension.lowercased()
        if ext == "md" || ext == "txt" {
            try content.data(using: .utf8)?.write(to: url, options: .atomic)
            return url
        } else if ext == "docx" {
            throw NSError(
                domain: "DOCX",
                code: 6,
                userInfo: [NSLocalizedDescriptionKey: "DOCX editing not supported; use Save As .md"]
            )
        } else if ext == "ppt" || ext == "pptx" {
            throw NSError(
                domain: "PPTX",
                code: 7,
                userInfo: [NSLocalizedDescriptionKey: "PPT/PPTX editing not supported; use Save As .md"]
            )
        } else if ext == "pdf" {
            throw NSError(
                domain: "PDF",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "PDF files are read-only"]
            )
        } else {
            throw NSError(
                domain: "Unsupported",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Unsupported file type"]
            )
        }
    }
    
    @discardableResult
    func saveAs(content: String, suggestedName: String?) throws -> URL {
        let name = suggestedName ?? "Untitled.md"
        
        let safeURL = try uniqueFileURL(baseName: name)
        
        // Ensure file ID is created for new files
        _ = FileIDManager.shared.getFileID(for: safeURL)
        
        return try save(content: content, to: safeURL)
    }
    
    @discardableResult
    func importIntoLibrary(from externalURL: URL) throws -> URL {
        let originalName = externalURL.lastPathComponent
        
        let safeDestination = try uniqueFileURL(baseName: originalName)
        
        try FileManager.default.copyItem(at: externalURL, to: safeDestination)
        
        // Ensure file ID is created for the new file
        _ = FileIDManager.shared.getFileID(for: safeDestination)
        
        return safeDestination
    }
    
    func delete(_ url: URL) throws {
        // Remove file ID first
        FileIDManager.shared.removeID(for: url)
        try FileManager.default.removeItem(at: url)
    }
    
    func rename(_ url: URL, to newName: String) throws -> URL {
        let newURL = url.deletingLastPathComponent().appendingPathComponent(newName)
        
        // Get file ID before moving
        let fileID = FileIDManager.shared.getFileID(for: url)
        
        try FileManager.default.moveItem(at: url, to: newURL)
        
        // Update companion file ID to new location
        FileIDManager.shared.removeID(for: url)
        FileIDManager.shared.getFileID(for: newURL)
        
        return newURL
    }
    
    func uniqueFileURL(baseName: String) throws -> URL {
            let directory = documentsURL
            let sanitizedName = sanitizeFileName(baseName)
            
        let candidateName = sanitizedName
            var counter = 2
            
            var candidateURL = directory.appendingPathComponent(candidateName)
            
            // Keep trying until we find a name that doesn't exist
            while FileManager.default.fileExists(atPath: candidateURL.path) {
                let nameWithoutExt = (candidateName as NSString).deletingPathExtension
                let ext = (candidateName as NSString).pathExtension
                
                let numberedName: String
                if ext.isEmpty {
                    numberedName = "\(nameWithoutExt)(\(counter))"
                } else {
                    numberedName = "\(nameWithoutExt)(\(counter)).\(ext)"
                }
                
                candidateURL = directory.appendingPathComponent(numberedName)
                counter += 1
            }
            
            return candidateURL
        }

    func sanitizeFileName(_ name: String) -> String {
        var sanitized = name.replacingOccurrences(
            of: "[\\\\/]",
            with: "-",
            options: .regularExpression
        )
        sanitized = sanitized.replacingOccurrences(
            of: "[:]",
            with: "-",
            options: .literal
        )
        sanitized = sanitized.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        sanitized = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized
    }
    
    func listAllItems(in directoryURL: URL? = nil) throws -> [FileSystemItem] {
            let baseURL = directoryURL ?? documentsURL
            let contents = try FileManager.default.contentsOfDirectory(
                at: baseURL,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            
            var items: [FileSystemItem] = []
            
            for url in contents {
                let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey])
                let isDir = resourceValues.isDirectory == true
                
                // Allow folders + supported files
                if isDir || supportedExtensions.contains(url.pathExtension.lowercased()) {
                    items.append(FileSystemItem(url: url, isDirectory: isDir))
                }
            }
            
            // Sort: folders first, then files by modification date
            return items.sorted { a, b in
                if a.isDirectory && !b.isDirectory { return true }
                if !a.isDirectory && b.isDirectory { return false }
                
                let aDate = (try? a.url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let bDate = (try? b.url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return aDate > bDate
            }
        }
        
        private var supportedExtensions: Set<String> {
            ["md", "txt", "pdf", "docx", "ppt", "pptx"]
        }
        
        // New: Create folder
        func createFolder(named name: String, in parentURL: URL? = nil) throws -> URL {
            let parent = parentURL ?? documentsURL
            let sanitized = sanitizeFileName(name)
            let folderURL = parent.appendingPathComponent(sanitized, isDirectory: true)
            
            var finalURL = folderURL
            var index = 2
            while FileManager.default.fileExists(atPath: finalURL.path) {
                finalURL = parent.appendingPathComponent("\(sanitized) \(index)", isDirectory: true)
                index += 1
            }
            
            try FileManager.default.createDirectory(at: finalURL, withIntermediateDirectories: true)
            return finalURL
        }
        
        // New: Move item (file or folder)
        func moveItem(at sourceURL: URL, to destinationFolderURL: URL) throws {
            let destURL = destinationFolderURL.appendingPathComponent(sourceURL.lastPathComponent)
            var finalURL = destURL
            var index = 2
            while FileManager.default.fileExists(atPath: finalURL.path) {
                let name = sourceURL.deletingPathExtension().lastPathComponent
                let ext = sourceURL.pathExtension
                let newName = "\(name) \(index)\(ext.isEmpty ? "" : ".\(ext)")"
                finalURL = destinationFolderURL.appendingPathComponent(newName)
                index += 1
            }
            try FileManager.default.moveItem(at: sourceURL, to: finalURL)
        }
}
struct FileSystemItem: Identifiable, Hashable {
    let url: URL
    let isDirectory: Bool
    var name: String { url.lastPathComponent }
    let id: URL
    
    init(url: URL, isDirectory: Bool) {
        self.url = url
        self.isDirectory = isDirectory
        self.id = url
    }
    
    static func == (lhs: FileSystemItem, rhs: FileSystemItem) -> Bool {
        lhs.url == rhs.url
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }
}
// MARK: - Conversation Store
@MainActor
final class ConversationStore: ObservableObject {
    static let shared = ConversationStore()
    @Published private(set) var threads: [URL: [ChatMessage]] = [:]

    func messages(for doc: URL) -> [ChatMessage] { threads[doc] ?? [] }

    // In ConversationStore
    private func chatFileURL(for doc: URL) -> URL {
        let base = doc.deletingPathExtension()
        return base.appendingPathExtension("chat.json")
    }

    func loadFromDisk(for doc: URL) {
        let url = chatFileURL(for: doc)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(
                [ChatMessage].self,
                from: data
            )
            threads[doc] = decoded
        } catch {
            // Optionally log/ignore
        }
    }

    func saveToDisk(for doc: URL) {
        guard let arr = threads[doc] else { return }
        do {
            let data = try JSONEncoder().encode(arr)
            try data.write(to: chatFileURL(for: doc), options: .atomic)
        } catch {
            // Optionally log/ignore
        }
    }

    func append(_ message: ChatMessage, to doc: URL) {
        var arr = threads[doc] ?? []
        arr.append(message)
        if arr.count > Constants.Limits.maxChatMessagesPerConversation {
            arr = Array(arr.suffix(Constants.Limits.maxChatMessagesPerConversation))
        }
        threads[doc] = arr
        saveToDisk(for: doc)
    }

    func replaceLastAssistantMessage(in doc: URL, with content: String) {
        guard var arr = threads[doc],
            let idx = arr.lastIndex(where: { $0.role == .assistant })
        else { return }
        let old = arr[idx]
        arr[idx] = ChatMessage(
            role: .assistant,
            content: content,
            id: old.id,
            createdAt: old.createdAt
        )
        threads[doc] = arr
        saveToDisk(for: doc)
    }

    func startAssistantPlaceholder(in doc: URL) {
        append(ChatMessage(role: .assistant, content: ""), to: doc)
        // append() already saves
    }

    func clearForDeletionOnDisk(for doc: URL) {  // for “Remove Messages”
        threads[doc] = []
        let f = chatFileURL(for: doc)
        if FileManager.default.fileExists(atPath: f.path) {
            try? FileManager.default.removeItem(at: f)
        }
    }

    func clear(for doc: URL) {
        threads[doc] = []
        saveToDisk(for: doc)
    }

    // MARK: - Saved Selection Chats

    struct SavedSelectionChat: Codable, Identifiable {
        let id: UUID
        let title: String
        let date: Date
        let messages: [ChatMessage]
        
        var idString: String { id.uuidString }
    }

    private let savedSelectionChatsKey = "SavedSelectionChatSessions"
    
    init() {
        // Existing: Load selection chats
        if let data = UserDefaults.standard.data(forKey: savedSelectionChatsKey),
           let decoded = try? JSONDecoder().decode([SavedSelectionChat].self, from: data) {
            self.savedSelectionChats = decoded.sorted { $0.date > $1.date }
        }

        // ADD THIS: Load document chats
        if let data = UserDefaults.standard.data(forKey: savedDocumentChatsKey),
           let decoded = try? JSONDecoder().decode([SavedDocumentChat].self, from: data) {
            self.savedDocumentChats = decoded.sorted { $0.date > $1.date }
        }
    }

    @Published var savedSelectionChats: [SavedSelectionChat] = [] {
        didSet {
            if savedSelectionChats.count > Constants.Limits.maxSavedSelectionChats {
                savedSelectionChats = Array(savedSelectionChats.prefix(Constants.Limits.maxSavedSelectionChats))
            }
            if let encoded = try? JSONEncoder().encode(savedSelectionChats) {
                UserDefaults.standard.set(encoded, forKey: savedSelectionChatsKey)
            }
        }
    }

    func saveChat(for docURL: URL, title: String) -> SavedSelectionChat? {
        let currentMessages = messages(for: SelectionChatView.sharedSelectionChatURL)
        guard !currentMessages.isEmpty else { return nil }

        let saved = SavedSelectionChat(
            id: UUID(),
            title: title,
            date: Date(),
            messages: currentMessages
        )

        savedSelectionChats.append(saved)
        savedSelectionChats.sort { $0.date > $1.date }

        return saved
    }

    func deleteSavedSelectionChat(_ saved: SavedSelectionChat) {
        savedSelectionChats.removeAll { $0.id == saved.id }
    }
    
    func loadSavedChat(_ saved: SavedSelectionChat, into docURL: URL) {
        // Clear current chat for this document
        threads[docURL] = []
        saveToDisk(for: docURL)
        
        // Load saved messages
        for msg in saved.messages {
            append(msg, to: docURL)
        }
    }
    
    @Published var isRestoringSavedChat = false

    func loadSavedSelectionChat(_ saved: SavedSelectionChat) {
        isRestoringSavedChat = true
        clear(for: SelectionChatView.sharedSelectionChatURL)
        
        Task { @MainActor in
            // Batch append to reduce UI updates
            for msg in saved.messages {
                append(msg, to: SelectionChatView.sharedSelectionChatURL)
                // Optional: yield every 20 messages
                if msg.id.hashValue % 20 == 0 { try? await Task.sleep(nanoseconds: 10_000_000) }
            }
            objectWillChange.send()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.isRestoringSavedChat = false
            }
        }
    }
    
    // MARK: - Saved Full Document Chats

    struct SavedDocumentChat: Codable, Identifiable {
        let id: UUID
        let title: String
        let date: Date
        let documentName: String    // e.g. "Report.md"
        let documentURL: URL        // original file URL (for identification)
        let messages: [ChatMessage]
        
        var idString: String { id.uuidString }
    }

    private let savedDocumentChatsKey = "SavedDocumentChatSessions"

    @Published var savedDocumentChats: [SavedDocumentChat] = [] {
        didSet {
            if savedDocumentChats.count > Constants.Limits.maxSavedDocumentChats {
                savedDocumentChats = Array(savedDocumentChats.prefix(Constants.Limits.maxSavedDocumentChats))
            }
            if let encoded = try? JSONEncoder().encode(savedDocumentChats) {
                UserDefaults.standard.set(encoded, forKey: savedDocumentChatsKey)
            }
        }
    }
    
    func saveDocumentChat(for docURL: URL, title: String) -> SavedDocumentChat? {
        let currentMessages = messages(for: docURL)
        guard !currentMessages.isEmpty else { return nil }
        
        let saved = SavedDocumentChat(
            id: UUID(),
            title: title,
            date: Date(),
            documentName: docURL.lastPathComponent,
            documentURL: docURL,
            messages: currentMessages
        )
        
        savedDocumentChats.append(saved)
        savedDocumentChats.sort { $0.date > $1.date }
        
        return saved
    }

    func deleteSavedDocumentChat(_ saved: SavedDocumentChat) {
        savedDocumentChats.removeAll { $0.id == saved.id }
    }

    func loadSavedDocumentChat(_ saved: SavedDocumentChat, into docURL: URL) {
        // Clear current
        threads[docURL] = []
        saveToDisk(for: docURL)
        
        // Load messages
        for msg in saved.messages {
            append(msg, to: docURL)
        }
    }
    
}

final class MCStore: ObservableObject {
    static let shared = MCStore()
    private let store: DocumentStore = .shared
    
    private let fileExtension = "mccards.json"

    func save(_ cards: [MCcard], for docURL: URL) throws {
        guard ["md", "pdf", "docx", "ppt", "pptx", "txt"].contains(docURL.pathExtension.lowercased()) else {
            throw NSError(
                domain: "MCcardStore",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unsupported file type for flashcards"]
            )
        }
        let data = try JSONEncoder().encode(cards)
        let mccardsURL = mccardsFileURL(for: docURL)
        try data.write(to: mccardsURL, options: .atomic)
    }

    func load(for docURL: URL) throws -> [MCcard] {
        guard ["md", "pdf", "docx", "ppt", "pptx", "txt"].contains(docURL.pathExtension.lowercased()) else {
            return []
        }
        let mccardsURL = mccardsFileURL(for: docURL)
        guard FileManager.default.fileExists(atPath: mccardsURL.path) else {
            return []
        }
        let data = try Data(contentsOf: mccardsURL)
        return try JSONDecoder().decode([MCcard].self, from: data)
    }

    func delete(for docURL: URL) throws {
        guard ["md", "pdf", "docx", "ppt", "pptx"].contains(docURL.pathExtension.lowercased()) else {
            return
        }
        let mccardsURL = mccardsFileURL(for: docURL)
        if FileManager.default.fileExists(atPath: mccardsURL.path) {
            try FileManager.default.removeItem(at: mccardsURL)
        }
    }

    private func mccardsFileURL(for docURL: URL) -> URL {
        let base = docURL.deletingLastPathComponent()
        let name = docURL.deletingPathExtension().lastPathComponent
        return base.appendingPathComponent("\(name).\(fileExtension)")
    }
}

// MARK: - Flashcard Persistence
@MainActor
final class FlashcardStore: ObservableObject {
    static let shared = FlashcardStore()
    private let store: DocumentStore = .shared
    
    private let fileExtension = "flashcards.json"
    
    func saveFlashcardsToWidget(_ cards: [Flashcard], for filename: String) {
        guard !cards.isEmpty else { return }

        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.alfredchen.MarkdownOpener"
        ) else {
            Log.error("Cannot access App Group", category: .widget)
            return
        }

        let jsonURL = containerURL.appendingPathComponent(filename)

        do {
            let data = try JSONEncoder().encode(cards)
            try data.write(to: jsonURL, options: .atomic)
            Log.debug("Saved for widget: \(filename) (\(cards.count) cards)", category: .widget)
        } catch {
            Log.error("Save failed", category: .widget, error: error)
        }
    }
    
    func saveFlashcards(_ cards: [Flashcard], for documentName: String) {
            guard !cards.isEmpty else { return }

            guard let containerURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: "group.com.alfredchen.MarkdownOpener"
            ) else {
                Log.error("Cannot access App Group container", category: .widget)
                return
            }

            let jsonURL = containerURL.appendingPathComponent(documentName + ".json")

            do {
                let data = try JSONEncoder().encode(cards)
                try data.write(to: jsonURL)
                Log.debug("Flashcards saved to: \(jsonURL.path)", category: .data)
            } catch {
                Log.error("Failed to save flashcards", category: .data, error: error)
            }
        }

        func loadFlashcards(for documentName: String) -> [Flashcard] {
            guard let containerURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: "group.com.alfredchen.MarkdownOpener"
            ) else { return [] }

            let jsonURL = containerURL.appendingPathComponent(documentName + ".json")

            guard let data = try? Data(contentsOf: jsonURL),
                  let cards = try? JSONDecoder().decode([Flashcard].self, from: data) else {
                return []
            }
            return cards
        }
    

    func save(_ cards: [Flashcard], for docURL: URL) throws {
        guard ["md", "pdf", "docx", "ppt", "pptx", "txt"].contains(docURL.pathExtension.lowercased()) else {
            throw NSError(
                domain: "FlashcardStore",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unsupported file type for flashcards"]
            )
        }
        let data = try JSONEncoder().encode(cards)
        let flashcardsURL = flashcardsFileURL(for: docURL)
        try data.write(to: flashcardsURL, options: .atomic)
    }

    func load(for docURL: URL) throws -> [Flashcard] {
        guard ["md", "pdf", "docx", "ppt", "pptx", "txt"].contains(docURL.pathExtension.lowercased()) else {
            return []
        }
        let flashcardsURL = flashcardsFileURL(for: docURL)
        guard FileManager.default.fileExists(atPath: flashcardsURL.path) else {
            return []
        }
        let data = try Data(contentsOf: flashcardsURL)
        return try JSONDecoder().decode([Flashcard].self, from: data)
    }

    func delete(for docURL: URL) throws {
        guard ["md", "pdf", "docx", "ppt", "pptx"].contains(docURL.pathExtension.lowercased()) else {
            return
        }
        let flashcardsURL = flashcardsFileURL(for: docURL)
        if FileManager.default.fileExists(atPath: flashcardsURL.path) {
            try FileManager.default.removeItem(at: flashcardsURL)
        }
    }

    private func flashcardsFileURL(for docURL: URL) -> URL {
        let base = docURL.deletingLastPathComponent()
        let name = docURL.deletingPathExtension().lastPathComponent
        return base.appendingPathComponent("\(name).\(fileExtension)")
    }
}

enum MiniMaxService {
    private static let baseURL = "https://api.minimax.chat/v1/text/chatcompletion_v2"

    struct PayloadMsg: Codable {
        let role: String
        let content: String
        let prefix: Bool?
        
        init(role: String, content: String, prefix: Bool? = nil) {
            self.role = role
            self.content = content
            self.prefix = prefix
        }
    }
    
    struct ChatReq: Codable {
        let model: String
        let messages: [PayloadMsg]
        let temperature: Double?
        let max_tokens: Int?
        let stream: Bool?
    }
    
    struct ChatChoice: Codable {
        let message: PayloadMsg
        let finish_reason: String?
    }
    
    struct ChatResp: Codable {
        let choices: [ChatChoice]
    }

    /// Single call — returns content + finish reason
    static func chat(
        apiKey: String,
        messages: [ChatMessage],
        temperature: Double = 0.3,
        maxTokens: Int = Constants.API.maxTokensStandard
    ) async throws -> (content: String, finishReason: String?) {
        guard let url = URL(string: baseURL) else {
            throw NSError(domain: "MiniMax", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid API URL"])
        }

        let payloadMsgs = messages.map { msg in
            PayloadMsg(
                role: msg.role.rawValue,
                content: msg.content,
                prefix: msg.isPrefix ? true : nil
            )
        }

        let body = ChatReq(
            model: "MiniMax-M2.7-highspeed",
            messages: payloadMsgs,
            temperature: temperature,
            max_tokens: maxTokens,
            stream: false
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 240
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let text = String(data: data, encoding: .utf8) ?? "<no body>"
            Log.error("MiniMax API Error: \(status) - \(text)", category: .network)
            throw NSError(domain: "MiniMax", code: status,
                          userInfo: [NSLocalizedDescriptionKey: "API Error \(status): \(text)"])
        }
        
        Log.debug("MiniMax Response received", category: .network)

        let decoded = try JSONDecoder().decode(ChatResp.self, from: data)
        guard let choice = decoded.choices.first else {
            throw NSError(domain: "MiniMax", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "No response from AI"])
        }

        return (content: choice.message.content, finishReason: choice.finish_reason)
    }

    /// Auto-continues long responses using prefix completion
    static func chatWithAutoContinue(
        apiKey: String,
        messages: [ChatMessage],
        temperature: Double = 0.3,
        maxTokens: Int = Constants.API.maxTokensStandard
    ) async throws -> String {
        var fullContent = ""
        var currentMessages = messages

        while true {
            let (content, finishReason) = try await chat(
                apiKey: apiKey,
                messages: currentMessages,
                temperature: temperature,
                maxTokens: maxTokens
            )

            fullContent += content

            // Stop if not truncated
            guard finishReason == "length" else { break }

            // Prepare next call with prefix
            if currentMessages.last?.role == .assistant {
                currentMessages.removeLast()
            }

            var prefixMsg = ChatMessage(role: .assistant, content: fullContent)
            prefixMsg.isPrefix = true
            currentMessages.append(prefixMsg)
        }

        return fullContent
    }
}

// MARK: - Grading Service (Updated to use new return type)
enum GradingService {
    static func grade(userAnswer: String, correctAnswer: String, apiKey: String) async throws -> (Int, String) {
        let system = """
        You are a strict but fair examiner. Compare the user's answer with the correct answer.
        Give a mark from 0 to 10 (10 = perfect). Return ONLY JSON: {"mark": int, "feedback": "short one sentence"}.
        """
        let userPrompt = "Correct answer: \(correctAnswer)\nUser answer: \(userAnswer)"
        let messages: [ChatMessage] = [
            .init(role: .system, content: system),
            .init(role: .user, content: userPrompt),
        ]
        
        let (rawContent, _) = try await MiniMaxService.chat(
            apiKey: apiKey,
            messages: messages,
            temperature: 0.0,
            maxTokens: 512
        )
        
        struct Resp: Decodable {
            let mark: Int
            let feedback: String
        }
        
        guard let data = rawContent.data(using: .utf8),
              let resp = try? JSONDecoder().decode(Resp.self, from: data) else {
            throw NSError(domain: "Grading", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid JSON from MiniMax"])
        }
        
        return (resp.mark, resp.feedback)
    }

    static func explain(userAnswer: String, card: MCcard, apiKey: String) async throws -> String {
        let system = """
        You are a knowledgeable tutor. Explain why the correct option is correct and the other options are not.
        Use concise but clear reasoning (4-6 sentences max). Avoid extra prefaces or meta-commentary.
        """
        let letterMap = ["A","B","C","D"]
        let listing = zip(letterMap, card.options).map { "\($0). \($1)" }.joined(separator: "\n")
        let userPrompt = """
        Question: \(card.question)
        Options:
        \(listing)
        Correct: \(letterMap[card.correctIndex]) - \(card.correctAnswer)
        User answer: \(userAnswer)
        """
        let messages: [ChatMessage] = [
            .init(role: .system, content: system),
            .init(role: .user, content: userPrompt),
        ]
        
        let (content, _) = try await MiniMaxService.chat(
            apiKey: apiKey,
            messages: messages,
            temperature: 0.2,
            maxTokens: 1024
        )
        
        return content
    }
}



// MARK: - Flashcard Parser
private func parseMCFlashcards(from response: String) -> [Flashcard] {
    var cards: [Flashcard] = []
    let blocks = response.components(separatedBy: "\n\n").map {
        $0.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    for block in blocks {
        let lines = block.components(separatedBy: "\n").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        var question = ""
        var options: [String] = []
        var correctLetter = ""

        for line in lines {
            if line.hasPrefix("Q:") {
                question = String(line.dropFirst(2)).trimmingCharacters(
                    in: .whitespaces
                )
            } else if line.hasPrefix("A)") || line.hasPrefix("B)")
                || line.hasPrefix("C)") || line.hasPrefix("D)")
            {
                options.append(
                    String(line.dropFirst(2)).trimmingCharacters(
                        in: .whitespaces
                    )
                )
            } else if line.hasPrefix("Correct:") {
                correctLetter = String(line.dropFirst(8)).trimmingCharacters(
                    in: .whitespaces
                ).uppercased()
            }
        }

        guard !question.isEmpty, options.count == 4,
            let letter = correctLetter.first,
            let idx = ["A", "B", "C", "D"].firstIndex(of: String(letter))
        else { continue }

        cards.append(
            Flashcard(question: question, options: options, correctIndex: idx)
        )
    }
    return cards
}

// MARK: - File ID Manager (Unique ID for each file)
struct FileIDInfo {
    let fileName: String
    let fileID: String
    let filePath: String
}

@MainActor
final class FileIDManager {
    static let shared = FileIDManager()
    private let idsKey = "com.markmind.fileids"
    
    private init() {
        Log.debug("FileIDManager initialized", category: .fileIO)
    }
    
    // Get or create unique ID for a file URL
    func getFileID(for url: URL) -> String {
        Log.debug("getFileID called for: \(url.lastPathComponent)", category: .fileIO)
        
        // First check companion file (most reliable)
        let idFile = companionFileURL(for: url)
        Log.debug("Checking companion file: \(idFile.path)", category: .fileIO)
        
        if FileManager.default.fileExists(atPath: idFile.path) {
            if let content = try? String(contentsOf: idFile, encoding: .utf8) {
                let id = content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !id.isEmpty {
                    Log.debug("Found existing ID: \(id)", category: .fileIO)
                    // Update cache
                    cacheIDIfNeeded(id, for: url)
                    return id
                }
            }
        }
        
        // Generate new ID and store it
        let newID = UUID().uuidString
        Log.debug("Creating new ID: \(newID)", category: .fileIO)
        storeID(newID, for: url)
        return newID
    }
    
    // Get all file IDs with their info
    func getAllFileIDs() -> [FileIDInfo] {
        let allIDs = getAllIDs()
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        
        var results: [FileIDInfo] = []
        
        // First get IDs from companion files
        if let documentsDir = documentsPath {
            if let files = try? FileManager.default.contentsOfDirectory(
                at: documentsDir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) {
                for fileURL in files {
                    let idFile = companionFileURL(for: fileURL)
                    if FileManager.default.fileExists(atPath: idFile.path),
                       let content = try? String(contentsOf: idFile, encoding: .utf8) {
                        let id = content.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !id.isEmpty {
                            results.append(FileIDInfo(
                                fileName: fileURL.lastPathComponent,
                                fileID: id,
                                filePath: fileURL.absoluteString
                            ))
                        }
                    }
                }
            }
        }
        
        // Also add from cache if not already added
        for (path, id) in allIDs {
            if !results.contains(where: { $0.fileID == id }) {
                let fileName = URL(string: path)?.lastPathComponent ?? "Unknown"
                results.append(FileIDInfo(
                    fileName: fileName,
                    fileID: id,
                    filePath: path
                ))
            }
        }
        
        return results
    }
    
    // Migrate all existing files to add unique IDs (async version)
    func migrateExistingFilesAsync() async {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        guard let documentsDir = documentsPath else { return }
        
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: documentsDir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            
            for fileURL in fileURLs {
                let ext = fileURL.pathExtension.lowercased()
                guard ["md", "markdown", "txt", "pdf", "docx", "ppt", "pptx"].contains(ext) else { continue }
                
                // Check companion file
                let idFile = companionFileURL(for: fileURL)
                if !FileManager.default.fileExists(atPath: idFile.path) {
                    // No ID, create one
                    let newID = UUID().uuidString
                    storeID(newID, for: fileURL)
                    Log.debug("Assigned ID \(newID) to file: \(fileURL.lastPathComponent)", category: .fileIO)
                }
            }
        } catch {
            Log.error("Failed to migrate file IDs", category: .fileIO, error: error)
        }
    }
    
    // Store ID for a file URL
    private func storeID(_ id: String, for url: URL) {
        Log.debug("Storing ID \(id) for: \(url.lastPathComponent)", category: .fileIO)
        
        // Store in companion file
        let idFile = companionFileURL(for: url)
        do {
            try id.write(to: idFile, atomically: true, encoding: .utf8)
            Log.debug("Written to companion file: \(idFile.path)", category: .fileIO)
        } catch {
            Log.error("Failed to write companion file", category: .fileIO, error: error)
        }
        
        // Also cache it
        cacheIDIfNeeded(id, for: url)
    }
    
    // Cache ID in UserDefaults (only if not already cached)
    private func cacheIDIfNeeded(_ id: String, for url: URL) {
        let allIDs = getAllIDs()
        if allIDs[url.absoluteString] == nil {
            Log.debug("Caching ID for: \(url.lastPathComponent)", category: .fileIO)
            var newIDs = allIDs
            newIDs[url.absoluteString] = id
            saveAllIDs(newIDs)
        }
    }
    
    // Get all cached IDs
    private func getAllIDs() -> [String: String] {
        guard let data = UserDefaults.standard.data(forKey: idsKey) else {
            Log.debug("No cached IDs found", category: .fileIO)
            return [:]
        }
        do {
            let ids = try JSONDecoder().decode([String: String].self, from: data)
            Log.debug("Loaded \(ids.count) cached IDs", category: .fileIO)
            return ids
        } catch {
            Log.error("Failed to decode cached IDs", category: .fileIO, error: error)
            return [:]
        }
    }
    
    // Save all cached IDs
    private func saveAllIDs(_ ids: [String: String]) {
        do {
            let data = try JSONEncoder().encode(ids)
            UserDefaults.standard.set(data, forKey: idsKey)
            Log.debug("Saved \(ids.count) IDs to cache", category: .fileIO)
        } catch {
            Log.error("Failed to save IDs", category: .fileIO, error: error)
        }
    }
    
    // Remove ID for a file URL
    func removeID(for url: URL) {
        Log.debug("Removing ID for: \(url.lastPathComponent)", category: .fileIO)
        let allIDs = getAllIDs()
        var newIDs = allIDs
        newIDs.removeValue(forKey: url.absoluteString)
        saveAllIDs(newIDs)
        
        // Also delete companion file
        let idFile = companionFileURL(for: url)
        try? FileManager.default.removeItem(at: idFile)
    }
    
    // Companion file URL for storing ID
    private func companionFileURL(for url: URL) -> URL {
        let parentDir = url.deletingLastPathComponent()
        let fileName = url.lastPathComponent
        return parentDir.appendingPathComponent(".\(fileName).markmindid")
    }
}
