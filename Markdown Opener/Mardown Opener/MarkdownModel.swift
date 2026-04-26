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

struct MCcard: Identifiable, Hashable, Codable {
    let id: UUID
    var question: String
    var options: [String]
    var correctIndex: Int
    var sourceAnchor: String?
    var explanation: String?
    var lastUserIndex: Int?
    var lastFeedback: String?

    // === NEW: Performance memory ===
    var timesSeen: Int = 0
    var timesCorrect: Int = 0
    var consecutiveCorrect: Int = 0  // for spaced repetition feel
    var lastAttemptDate: Date? = nil

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
        lastAttemptDate: Date? = nil
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
        self.lastAttemptDate = lastAttemptDate
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

    // === NEW: Performance memory ===
    var timesSeen: Int = 0
    var timesCorrect: Int = 0
    var consecutiveCorrect: Int = 0  // for spaced repetition feel

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
        consecutiveCorrect: Int = 0
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

    enum Rating { case again, hard, good }

    func rate(_ r: Rating) {
        guard let c = current else { return }
        let delta: Int = r == .again ? -1 : (r == .hard ? 0 : 1)
        ratings[c.id, default: 0] += delta
        advance()
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
    let id: UUID
    let role: Role
    var content: String
    let createdAt: Date
    var isPrefix: Bool = false
    var isShortcut: Bool = false  // Add this line

    init(
        role: Role,
        content: String,
        id: UUID = UUID(),
        createdAt: Date = Date(),
        isShortcut: Bool = false  // Add this parameter
    ) {
        self.role = role
        self.content = content
        self.id = id
        self.createdAt = createdAt
        self.isShortcut = isShortcut
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
