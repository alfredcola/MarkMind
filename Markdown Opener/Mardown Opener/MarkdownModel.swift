//
//  Flashcard.swift
//  Markdown Opener
//
//  Created by alfred chen on 9/11/2025.
//

import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import Markdown

enum MCQuestionType: String, Codable {
    case singleSelect = "single"  // Traditional A/B/C/D
    case multiSelect = "multi"    // Multiple correct answers
    case trueFalse = "tf"        // True or False
}

struct MCcard: Identifiable, Hashable, Codable {
    let id: UUID
    var question: String
    var options: [String]
    var correctIndex: Int  // For single select
    var correctIndices: [Int]?  // For multi-select (all correct indices)
    var questionType: MCQuestionType = .singleSelect
    var sourceAnchor: String?
    var explanation: String?
    var lastUserIndex: Int?
    var lastUserIndices: [Int]?  // For multi-select tracking
    var lastFeedback: String?

    // Performance memory
    var timesSeen: Int = 0
    var timesCorrect: Int = 0
    var consecutiveCorrect: Int = 0
    var lastAttemptDate: Date? = nil
    var partialCreditEnabled: Bool = false

    // SM-2 Spaced Repetition Fields
    var easeFactor: Double = 2.5
    var interval: Int = 0
    var repetitions: Int = 0
    var nextReviewDate: Date = Date()

    init(
        id: UUID = UUID(),
        question: String,
        options: [String],
        correctIndex: Int,
        correctIndices: [Int]? = nil,
        questionType: MCQuestionType = .singleSelect,
        sourceAnchor: String? = nil,
        explanation: String? = nil,
        lastUserIndex: Int? = nil,
        lastUserIndices: [Int]? = nil,
        lastFeedback: String? = nil,
        timesSeen: Int = 0,
        timesCorrect: Int = 0,
        consecutiveCorrect: Int = 0,
        lastAttemptDate: Date? = nil,
        partialCreditEnabled: Bool = false,
        easeFactor: Double = 2.5,
        interval: Int = 0,
        repetitions: Int = 0,
        nextReviewDate: Date = Date()
    ) {
        self.id = id
        self.question = question
        self.options = options
        self.correctIndex = correctIndex
        self.correctIndices = correctIndices
        self.questionType = questionType
        self.sourceAnchor = sourceAnchor
        self.explanation = explanation
        self.lastUserIndex = lastUserIndex
        self.lastUserIndices = lastUserIndices
        self.lastFeedback = lastFeedback
        self.timesSeen = timesSeen
        self.timesCorrect = timesCorrect
        self.consecutiveCorrect = consecutiveCorrect
        self.lastAttemptDate = lastAttemptDate
        self.partialCreditEnabled = partialCreditEnabled
        self.easeFactor = easeFactor
        self.interval = interval
        self.repetitions = repetitions
        self.nextReviewDate = nextReviewDate
    }

    var isDueForReview: Bool {
        Date() >= nextReviewDate
    }

    mutating func updateWithSM2(quality: Int) {
        timesSeen += 1

        if quality >= 3 {
            timesCorrect += 1
            consecutiveCorrect += 1

            if repetitions == 0 {
                interval = 1
            } else if repetitions == 1 {
                interval = 6
            } else {
                interval = Int(Double(interval) * easeFactor)
            }
            repetitions += 1
        } else {
            consecutiveCorrect = 0
            repetitions = 0
            interval = 1
        }

        easeFactor = easeFactor + (0.1 - Double(5 - quality) * (0.08 + Double(5 - quality) * 0.02))
        if easeFactor < 1.3 {
            easeFactor = 1.3
        }

        nextReviewDate = Calendar.current.date(byAdding: .day, value: interval, to: Date()) ?? Date()
    }

    var correctAnswer: String {
        guard correctIndex >= 0 && correctIndex < options.count else { return "" }
        return options[correctIndex]
    }
    
    var correctAnswers: [String] {
        if let indices = correctIndices {
            return indices.compactMap { idx in idx >= 0 && idx < options.count ? options[idx] : nil }
        }
        return [correctAnswer]
    }
    
    var accuracy: Double {
        timesSeen == 0 ? 0 : Double(timesCorrect) / Double(timesSeen)
    }
    
    var isWeak: Bool { accuracy < 0.7 && timesSeen >= 2 }
    var isMastered: Bool { consecutiveCorrect >= 3 }
    
    // Calculate partial credit for multi-select
    func calculatePartialCredit(userSelected: Set<Int>) -> Double {
        guard let correct = Set(correctIndices ?? [correctIndex]) as Set<Int>? else { return 0 }
        
        let correctSelections = userSelected.intersection(correct)
        let wrongSelections = userSelected.subtracting(correct)
        
        let numCorrect = correctSelections.count
        let numWrong = wrongSelections.count
        let totalCorrect = correct.count
        
        // Partial credit formula: (correct selections - wrong selections) / total correct
        // Negative results become 0
        let score = Double(numCorrect - numWrong) / Double(totalCorrect)
        return max(0, min(1, score))
    }
    
    // Check if answer is correct
    func isCorrect(userIndex: Int) -> Bool {
        return userIndex == correctIndex
    }
    
    func isCorrect(userIndices: Set<Int>) -> Bool {
        if questionType == .singleSelect {
            return userIndices.contains(correctIndex) && userIndices.count == 1
        }
        guard let correct = Set(correctIndices ?? [correctIndex]) as Set<Int>? else { return false }
        return userIndices == correct
    }
}

// MARK: - Flashcard Model
struct Flashcard: Identifiable, Hashable, Codable {
    let id: UUID
    var question: String
    var options: [String]
    var correctIndex: Int
    var sourceAnchor: String?
    var explanation: String?
    var lastUserIndex: Int?
    var lastFeedback: String?

    // Performance memory
    var timesSeen: Int = 0
    var timesCorrect: Int = 0
    var consecutiveCorrect: Int = 0

    // SM-2 Spaced Repetition Fields
    var easeFactor: Double = 2.5  // Initial ease factor
    var interval: Int = 0  // Days until next review
    var repetitions: Int = 0  // Successful review count
    var nextReviewDate: Date = Date()
    var isCustom: Bool = false  // True if manually created

    init(
        id: UUID = UUID(),
        question: String,
        options: [String],
        correctIndex: Int,
        sourceAnchor: String? = nil,
        explanation: String? = nil,
        lastUserIndex: Int? = nil,
        lastFeedback: String? = nil,
        timesSeen: Int = 0,
        timesCorrect: Int = 0,
        consecutiveCorrect: Int = 0,
        easeFactor: Double = 2.5,
        interval: Int = 0,
        repetitions: Int = 0,
        nextReviewDate: Date = Date(),
        isCustom: Bool = false
    ) {
        self.id = id
        self.question = question
        self.options = options
        self.correctIndex = correctIndex
        self.sourceAnchor = sourceAnchor
        self.explanation = explanation
        self.lastUserIndex = lastUserIndex
        self.lastFeedback = lastFeedback
        self.timesSeen = timesSeen
        self.timesCorrect = timesCorrect
        self.consecutiveCorrect = consecutiveCorrect
        self.easeFactor = easeFactor
        self.interval = interval
        self.repetitions = repetitions
        self.nextReviewDate = nextReviewDate
        self.isCustom = isCustom
    }

    var correctAnswer: String {
        guard correctIndex >= 0 && correctIndex < options.count else { return "" }
        return options[correctIndex]
    }
    
    var accuracy: Double {
        timesSeen == 0 ? 0 : Double(timesCorrect) / Double(timesSeen)
    }
    
    var isWeak: Bool { accuracy < 0.7 && timesSeen >= 2 }
    var isMastered: Bool { consecutiveCorrect >= 3 }
    
    var isDueForReview: Bool {
        Date() >= nextReviewDate
    }
    
    // SM-2 Algorithm: Calculate next review based on quality (0-5)
    // 0-2: Incorrect, reset repetitions
    // 3-5: Correct, increase interval
    mutating func updateWithSM2(quality: Int) {
        timesSeen += 1
        
        if quality >= 3 {
            timesCorrect += 1
            consecutiveCorrect += 1
            
            if repetitions == 0 {
                interval = 1
            } else if repetitions == 1 {
                interval = 6
            } else {
                interval = Int(Double(interval) * easeFactor)
            }
            repetitions += 1
        } else {
            consecutiveCorrect = 0
            repetitions = 0
            interval = 1
        }
        
        // Update ease factor
        easeFactor = easeFactor + (0.1 - Double(5 - quality) * (0.08 + Double(5 - quality) * 0.02))
        if easeFactor < 1.3 {
            easeFactor = 1.3
        }
        
        nextReviewDate = Calendar.current.date(byAdding: .day, value: interval, to: Date()) ?? Date()
    }
    
    // Export to Anki-compatible format (TSV)
    func toAnkiLine() -> String {
        let front = question.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: "<br>")
        let back = correctAnswer.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: "<br>")
        let tags = sourceAnchor.map { " #\($0)" } ?? ""
        return "\(front)\t\(back)\(tags)"
    }
}

// MARK: - Anki Export
extension Array where Element == Flashcard {
    func exportToAnki() -> String {
        return self.map { $0.toAnkiLine() }.joined(separator: "\n")
    }
}


// MARK: - Flashcard Session
final class FlashcardSession: ObservableObject {
    @Published var cards: [Flashcard] = []
    @Published var index: Int = 0
    @Published var done: Bool = false

    var current: Flashcard? {
        guard index < cards.count else { return nil }
        return cards[index]
    }

    private func advance() {
        index += 1
        if index >= cards.count {
            done = true
        }
    }
    
    // Get cards due for review, sorted by priority (most overdue first)
    func dueCards() -> [Flashcard] {
        let now = Date()
        return cards
            .filter { $0.isDueForReview }
            .sorted { $0.nextReviewDate < $1.nextReviewDate }
    }
    
    // Get new cards that haven't been seen yet
    func newCards() -> [Flashcard] {
        return cards.filter { $0.timesSeen == 0 }
    }
    
    // Reorder cards by SRS priority
    func reorderBySRS() {
        let due = dueCards()
        let notDue = cards.filter { !$0.isDueForReview }
        cards = due + notDue
        index = 0
        done = cards.isEmpty
    }
    
    // Update card after user feedback (quality: 0-5)
    func updateCard(_ card: Flashcard, quality: Int) {
        if let idx = cards.firstIndex(where: { $0.id == card.id }) {
            cards[idx].updateWithSM2(quality: quality)
        }
    }
}
final class MCSession: ObservableObject {
    @Published var cards: [MCcard] = []
    @Published var index: Int = 0
    @Published var done: Bool = false

    private var ratings: [UUID: Int] = [:]

    // Scoring: Each question is worth 10 marks if correct, 0 if incorrect
    @Published var totalMarks: Int = 0
    @Published var totalAttempts: Int = 0
    @Published var perCardMarks: [UUID: Int] = [:]

    // Track whether explanations have been generated at end
    @Published var explanationsReady: Bool = false

    var current: MCcard? {
        guard index < cards.count else { return nil }
        return cards[index]
    }

    enum Rating: Int { case again = 1, hard = 3, good = 4, easy = 5 }

    func rate(_ r: Rating) {
        guard let c = current else { return }
        updateCard(c, quality: r.rawValue)
    }

    func dueCards() -> [MCcard] {
        let now = Date()
        return cards
            .filter { $0.isDueForReview }
            .sorted { $0.nextReviewDate < $1.nextReviewDate }
    }

    func newCards() -> [MCcard] {
        return cards.filter { $0.timesSeen == 0 }
    }

    func reorderBySRS() {
        let due = dueCards()
        let notDue = cards.filter { !$0.isDueForReview }
        cards = due + notDue
        index = 0
        done = cards.isEmpty
    }

    func updateCard(_ card: MCcard, quality: Int) {
        if let idx = cards.firstIndex(where: { $0.id == card.id }) {
            cards[idx].updateWithSM2(quality: quality)
        }
    }

    
    func applyMark(isCorrect: Bool, for cardID: UUID) {
        totalAttempts += 1
        let mark = isCorrect ? 10 : 0
        totalMarks += mark
        perCardMarks[cardID] = mark
    }

    func restart() {
        index = 0
        done = cards.isEmpty
        explanationsReady = false
        totalMarks = 0
        totalAttempts = 0
        perCardMarks.removeAll()

        for i in cards.indices {
            cards[i].lastUserIndex = nil
            cards[i].lastUserIndices = nil
            cards[i].lastFeedback = nil
        }
    }

    private func advance() {
        index += 1
        if index >= cards.count {
            done = true
        }
    }
}

// MARK: - Chat Message
struct ChatMessage: Identifiable, Codable, Equatable {
    enum Role: String, Codable { case system, user, assistant }

    enum MessageStatus: String, Codable {
        case sending
        case sent
        case delivered
        case failed
    }

    let id: UUID
    let role: Role
    var content: String
    let createdAt: Date
    var isPrefix: Bool = false
    var isShortcut: Bool = false
    var status: MessageStatus = .sent
    var parentId: UUID?
    var branchId: UUID?
    var branchLabel: String?
    var isMerged: Bool = false

    init(
        role: Role,
        content: String,
        id: UUID = UUID(),
        createdAt: Date = Date(),
        isShortcut: Bool = false,
        status: MessageStatus = .sent,
        parentId: UUID? = nil,
        branchId: UUID? = nil,
        branchLabel: String? = nil,
        isMerged: Bool = false
    ) {
        self.role = role
        self.content = content
        self.id = id
        self.createdAt = createdAt
        self.isShortcut = isShortcut
        self.status = status
        self.parentId = parentId
        self.branchId = branchId
        self.branchLabel = branchLabel
        self.isMerged = isMerged
    }
}

struct SavedDocumentChat: Codable, Identifiable {
    let id: UUID
    let title: String
    let date: Date
    let messages: [ChatMessage]
    let documentURL: URL
    
    var idString: String { id.uuidString }
}

// MARK: - Open URL Router
class OpenURLRouter: ObservableObject {
    @Published var incomingURL: URL? = nil
    private var pendingURL: URL? = nil
    
    private let supportedExtensions = ["md", "markdown", "txt", "pdf", "docx", "ppt", "pptx"]
    
    /// Handles an incoming URL and returns true if it was consumed (handled)
    /// Returns false if this router did not recognize or handle the URL
    func handle(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        
        guard url.scheme == "markmind" || supportedExtensions.contains(ext) else {
            return false
        }

        if Thread.isMainThread {
            _handleOnMain(url)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?._handleOnMain(url)
            }
        }
        
        return incomingURL == nil && pendingURL == nil
    }

    private func _handleOnMain(_ url: URL) {
        // Avoid processing multiple at once
        if incomingURL != nil || pendingURL != nil {
            return
        }
        pendingURL = url
        incomingURL = url  // Trigger observers in EditorView
    }

    // Call this from EditorView when it's ready to process the URL
    func consumePending() -> URL? {
        let url = pendingURL
        pendingURL = nil
        incomingURL = nil
        return url
    }
}

// MARK: - Notification
extension Notification.Name {
    static let regenerateFlashcards = Notification.Name("regenerateFlashcards")
    static let regenerateMCcards = Notification.Name("regenerateMCcards")
}

// MARK: - File Exporter
enum FileExporter {
    static func tempFile(named name: String, content: String) -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(name)
        if let data = content.data(using: .utf8) {
            do {
                try data.write(to: url, options: .atomic)
            } catch {
            }
        }
        return url
    }

    static func writeTemp(data: Data, ext: String, suggested: String = "")
        throws -> URL
    {
        let base = suggested.isEmpty ? UUID().uuidString : suggested
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        let url = dir.appendingPathComponent(base).appendingPathExtension(ext)
        try data.write(to: url, options: .atomic)
        return url
    }
}

// MARK: - Simple Markdown to HTML
enum SimpleMarkdown {
    static func naiveToHTML(from md: String) -> String {
        var output: [String] = []
        var inCode = false
        var currentParagraph = ""
        var listStack: [String] = []

        func closeParagraphIfNeeded() {
            if !currentParagraph.isEmpty {
                output.append("<p>\(inline(currentParagraph))</p>")
                currentParagraph = ""
            }
        }
        func closeListIfNeeded() {
            while !listStack.isEmpty {
                let tag = listStack.removeLast()
                output.append("</\(tag)>")
            }
        }

        let lines = md.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        for raw in lines {
            let line = raw

            if line.hasPrefix("```") {
                closeParagraphIfNeeded()
                closeListIfNeeded()
                if inCode {
                    output.append("</pre>")
                    inCode = false
                } else {
                    output.append("<pre>")
                    inCode = true
                }
                continue
            }
            if inCode {
                output.append(line.replacingOccurrences(of: "\t", with: "    "))
                continue
            }

            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                closeParagraphIfNeeded()
                closeListIfNeeded()
                continue
            }

            if line.hasPrefix("#") {
                closeParagraphIfNeeded()
                closeListIfNeeded()
                let level = min(6, line.prefix { $0 == "#" }.count)
                let text = line.drop(while: { $0 == "#" || $0 == " " })
                output.append("<h\(level)>\(inline(String(text)))</h\(level)>")
                continue
            }

            if line.hasPrefix(">") {
                closeParagraphIfNeeded()
                closeListIfNeeded()
                let content = line.drop(while: { $0 == ">" || $0 == " " })
                output.append(
                    "<blockquote>\(inline(String(content)))</blockquote>"
                )
                continue
            }

            if line.trimmingCharacters(in: .whitespaces) == "---" {
                closeParagraphIfNeeded()
                closeListIfNeeded()
                output.append("<hr/>")
                continue
            }

            if let (type, content) = listItemInfo(line) {
                closeParagraphIfNeeded()
                let desiredTag = type == .ordered ? "ol" : "ul"
                if listStack.last != desiredTag {
                    closeListIfNeeded()
                    listStack.append(desiredTag)
                    output.append("<\(desiredTag)>")
                }
                output.append("<li>\(inline(content))</li>")
                continue
            }

            if line.hasPrefix("|") && line.hasSuffix("|") {
                closeParagraphIfNeeded()
                closeListIfNeeded()
                output.append(parseTableRow(line))
                continue
            }

            if currentParagraph.isEmpty {
                currentParagraph = line
            } else {
                currentParagraph += " " + line
            }
        }

        closeParagraphIfNeeded()
        closeListIfNeeded()
        if inCode { output.append("</pre>") }

        return output.joined(separator: "\n")
    }

    private enum ListType { case ordered, unordered }

    private static func listItemInfo(_ line: String) -> (ListType, String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("- [ ] ") || trimmed.hasPrefix("* [ ] ") {
            let content = String(trimmed.dropFirst(6))
            return (.unordered, content)
        }
        if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("* [x] ") || trimmed.hasPrefix("- [X] ") {
            let content = String(trimmed.dropFirst(6))
            return (.unordered, "✅ " + content)
        }
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            let content = String(trimmed.dropFirst(2))
            return (.unordered, content)
        }
        if let dot = trimmed.firstIndex(of: "."),
            let num = Int(trimmed[..<dot]), num >= 1
        {
            let after = trimmed.index(after: dot)
            let content = trimmed[after...].trimmingCharacters(in: .whitespaces)
            return (.ordered, String(content))
        }
        return nil
    }

    private static func parseTableRow(_ line: String) -> String {
        let cells = line.split(separator: "|").map { String($0).trimmingCharacters(in: .whitespaces) }
        let isSeparator = cells.allSatisfy { $0.allSatisfy { $0 == "-" || $0 == ":" } }
        if isSeparator { return "" }
        let tag = "td"
        let cellHTML = cells.map { "<\(tag)>\(inline($0))</\(tag)>" }.joined(separator: "")
        return "<tr>\(cellHTML)</tr>"
    }

    private static func inline(_ s: String) -> String {
        var r = s
        r = r.replacingOccurrences(
            of: "`([^`]+)`",
            with: "<code>$1</code>",
            options: .regularExpression
        )
        r = r.replacingOccurrences(
            of: "\\*\\*(.+?)\\*\\*",
            with: "<strong>$1</strong>",
            options: .regularExpression
        )
        r = r.replacingOccurrences(
            of: "(?<!\\*)\\*(?!\\*)(.+?)(?<!\\*)\\*(?!\\*)",
            with: "<em>$1</em>",
            options: .regularExpression
        )
        r = r.replacingOccurrences(
            of: "~~(.+?)~~",
            with: "<del>$1</del>",
            options: .regularExpression
        )
        r = r.replacingOccurrences(
            of: "\\[([^\\]]+)\\]\\(([^\\)]+)\\)",
            with: "<a href=\"$2\">$1</a>",
            options: .regularExpression
        )
        r = r.replacingOccurrences(
            of: "https?://[^\\s<>\"']+",
            with: "<a href=\"$0\">$0</a>",
            options: .regularExpression
        )
        return r
    }
}

// MARK: - GFM HTML Renderer using swift-markdown
extension SimpleMarkdown {
    static func gfmToHTML(from md: String) -> String {
        let document = Markdown.Document(parsing: md, options: [.parseBlockDirectives, .parseSymbolLinks])
        var renderer = GFMRenderer()
        return renderer.render(document)
    }

    private struct GFMRenderer {
        private var html: [String] = []
        private var listStack: [String] = []
        private var tableColumnAlignments: [String] = []

        mutating func render(_ document: Markdown.Document) -> String {
            html = []
            walk(document)
            return html.joined()
        }

        private mutating func walk(_ markup: Markdown.Markup) {
            switch markup {
            case let paragraph as Markdown.Paragraph:
                html.append("<p>")
                walkChildren(paragraph)
                html.append("</p>")
            case let heading as Markdown.Heading:
                let level = min(6, heading.level)
                html.append("<h\(level)>")
                walkChildren(heading)
                html.append("</h\(level)>")
            case is Markdown.ThematicBreak:
                html.append("<hr/>")
            case let codeBlock as Markdown.CodeBlock:
                html.append("<pre><code>")
                html.append(codeBlock.code.replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;"))
                html.append("</code></pre>")
            case let blockQuote as Markdown.BlockQuote:
                html.append("<blockquote>")
                walkChildren(blockQuote)
                html.append("</blockquote>")
            case let unorderedList as Markdown.UnorderedList:
                closeListIfNeeded()
                listStack.append("ul")
                html.append("<ul>")
                walkChildren(unorderedList)
                html.append("</ul>")
                _ = listStack.popLast()
            case let orderedList as Markdown.OrderedList:
                closeListIfNeeded()
                listStack.append("ol")
                html.append("<ol>")
                walkChildren(orderedList)
                html.append("</ol>")
                _ = listStack.popLast()
            case let listItem as Markdown.ListItem:
                html.append("<li>")
                walkChildren(listItem)
                if case .checked = listItem.checkbox {
                    html.insert("✅ ", at: html.startIndex)
                } else if listItem.checkbox != nil {
                    html.insert("☐ ", at: html.startIndex)
                }
                html.append("</li>")
            case let table as Markdown.Table:
                closeListIfNeeded()
                html.append("<table>")
                tableColumnAlignments = table.columnAlignments.map { alignment -> String in
                    switch alignment {
                    case .center: return "center"
                    case .left: return "left"
                    case .right: return "right"
                    case .none: return "left"
                    @unknown default: return "left"
                    }
                }
                walkChildren(table)
                html.append("</table>")
                tableColumnAlignments = []
            case is Markdown.Table:
                walkChildren(markup)
            case let tableHead as Markdown.Table.Head:
                html.append("<thead><tr>")
                for (index, cell) in tableHead.cells.enumerated() {
                    let align = index < tableColumnAlignments.count ? tableColumnAlignments[index] : "left"
                    html.append("<\(tag(for: "th", alignment: align))>")
                    walkInlineContent(cell)
                    html.append("</th>")
                }
                html.append("</tr></thead><tbody>")
            case let tableRow as Markdown.Table.Row:
                html.append("<tr>")
                for (index, cell) in tableRow.cells.enumerated() {
                    let align = index < tableColumnAlignments.count ? tableColumnAlignments[index] : "left"
                    html.append("<\(tag(for: "td", alignment: align))>")
                    walkInlineContent(cell)
                    html.append("</td>")
                }
                html.append("</tr>")
            case is Markdown.Table.Head, is Markdown.Table.Row:
                walkChildren(markup)
            case let htmlBlock as Markdown.HTMLBlock:
                html.append(htmlBlock.rawHTML)
            case is Markdown.Document:
                walkChildren(markup)
            default:
                if markup.childCount > 0 {
                    walkChildren(markup)
                } else {
                    html.append(renderInline(markup))
                }
            }
        }

        private mutating func walkChildren(_ markup: Markdown.Markup) {
            for child in markup.children {
                walk(child)
            }
        }

        private mutating func walkInlineContent(_ markup: Markdown.Markup) {
            for child in markup.children {
                html.append(renderInline(child))
            }
        }

        private func renderInline(_ markup: Markdown.Markup) -> String {
            switch markup {
            case let text as Markdown.Text:
                return text.string.replacingOccurrences(of: "\n", with: " ")
            case let emph as Markdown.Emphasis:
                return "<em>\(emph.children.map { renderInline($0) }.joined())</em>"
            case let strong as Markdown.Strong:
                return "<strong>\(strong.children.map { renderInline($0) }.joined())</strong>"
            case is Markdown.Strikethrough:
                return "<del>\(markup.children.map { renderInline($0) }.joined())</del>"
            case let inlineCode as Markdown.InlineCode:
                return "<code>\(inlineCode.code)</code>"
            case let link as Markdown.Link:
                return "<a href=\"\(link.destination ?? "#")\">\(link.children.map { renderInline($0) }.joined())</a>"
            case is Markdown.SoftBreak:
                return " "
            case is Markdown.LineBreak:
                return "<br/>"
            case let inlineHTML as Markdown.InlineHTML:
                return inlineHTML.rawHTML
            default:
                return markup.plainText
            }
        }

        private func tag(for base: String, alignment: String) -> String {
            if alignment == "left" { return base }
            return "\(base) align=\"\(alignment)\""
        }

        private mutating func closeListIfNeeded() {
            while !listStack.isEmpty {
                let tag = listStack.removeLast()
                html.append("</\(tag)>")
            }
        }
    }
}

extension Markdown.Markup {
    var plainText: String {
        var result = ""
        if let text = self as? Markdown.Text {
            result = text.string
        } else {
            for child in children {
                result += child.plainText
            }
        }
        return result
    }
}
