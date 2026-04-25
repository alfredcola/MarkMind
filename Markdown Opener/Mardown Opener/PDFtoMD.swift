import Foundation
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

struct PDFtoMD: View {
    @State private var showImporter = false
    @State private var showExporter = false
    @State private var markdownContent = ""
    @State private var markdownURL: URL?
    @State private var statusMessage = ""
    @State private var isFormattingWithAI = false
    @State private var aiFormattedMarkdown = ""

    // Callback to notify the parent when conversion is done
    var onConvert: (URL?) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text(statusMessage)
                    .foregroundStyle(.secondary)

                if isFormattingWithAI {
                    ProgressView("AI Formatting...")
                        .padding()
                    Text("AI is formatting your Markdown...")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }

                if !markdownContent.isEmpty {
                    ScrollView {
                        Text(markdownContent)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(8)
                            .padding()
                    }
                }

                // Improved button logic
                if markdownURL != nil  {
                    // Success state: show main actions
                    Button("Import Another PDF") {
                        showImporter = true
                    }
                    .buttonStyle(.bordered)

                    if !isFormattingWithAI {
                        Button("AI Format") {
                            Task {
                                await formatMarkdownWithMiniMax(markdownContent)
                            }
                        }
                        .buttonStyle(.bordered)
                    }

                    Button("Add to Library") {
                        if let url = markdownURL {
                            onConvert(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                } else if !isFormattingWithAI {
                    // Initial or idle state
                    Button("Import PDF") {
                        showImporter = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .navigationTitle("PDF to Markdown")
            .navigationBarTitleDisplayMode(.inline)
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
            }
            .toolbar {
                if markdownURL != nil {
                    ShareLink(
                        item: markdownURL!,
                        subject: Text("Converted Markdown"),
                        message: Text("Here is the converted Markdown file."),
                        preview: .init(
                            "converted.md",
                            image: Image(systemName: "doc.text")
                        )
                    )
                    .labelStyle(.iconOnly)
                }
            }
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let pdfURL = urls.first else { return }
            pdfURL.startAccessingSecurityScopedResource()
            convertPDFtoMarkdownFrom(pdfURL)
            pdfURL.stopAccessingSecurityScopedResource()
        case .failure(let error):
            statusMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    private func convertPDFtoMarkdownFrom(_ url: URL) {
        guard let pdfDocument = PDFDocument(url: url) else {
            statusMessage = "Failed to load PDF"
            return
        }

        let initialMarkdown = extractMarkdownFrom(pdfDocument)
        markdownContent = initialMarkdown
        
        // Use Task to run the async formatting
        Task {
            await formatMarkdownWithMiniMax(initialMarkdown)

            // Only save to file if we actually have formatted content
            guard !markdownContent.isEmpty else { return }

            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("ai_formatted_\(UUID().uuidString).md")

            do {
                try markdownContent.write(to: tempURL, atomically: true, encoding: .utf8)
                await MainActor.run {
                    self.markdownURL = tempURL
                    // Only update if we didn't just hit an error in the formatting step
                    if !statusMessage.contains("❌") {
                        statusMessage = "AI-formatted and ready!"
                    }
                }
            } catch {
                await MainActor.run {
                    statusMessage = "Failed to save file locally."
                }
            }
        }
    }
    
    private func cleanAIResponse(_ rawResponse: String) -> String {
        var cleaned = rawResponse.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check if the response starts with ```markdown or ``` and ends with ```
        if cleaned.hasPrefix("```") {
            // Split by lines
            var lines = cleaned.components(separatedBy: .newlines)
            
            // Remove the first line (the opening ``` or ```markdown)
            if !lines.isEmpty { lines.removeFirst() }
            
            // Remove the last line (the closing ```)
            if !lines.isEmpty && lines.last?.contains("```") == true {
                lines.removeLast()
            }
            
            cleaned = lines.joined(separator: "\n")
        }
        
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func formatMarkdownWithMiniMax(_ markdown: String) async {
        guard !markdown.isEmpty else { return }

        await MainActor.run {
            isFormattingWithAI = true
            statusMessage = "AI is analyzing structure..."
        }

        // Pre-process: Normalize common PDF line-break patterns
        let preprocessedMarkdown = preprocessBrokenWords(markdown)

        let ultimatePrompt = """
            You are a PDF-to-Markdown conversion engine. I am providing you with raw, messy text extracted from a PDF. 

            ### THE CHALLENGE:
            The text contains broken words and random line breaks. Reconstruct the logical flow.

            ### 🚨 CRITICAL RULE:
            - OUTPUT ONLY THE RAW MARKDOWN CONTENT.
            - DO NOT USE MARKDOWN CODE FENCES (```markdown or ```).
            - START IMMEDIATELY WITH THE CONTENT.
            - NO INTRODUCTIONS, NO OUTRO, NO COMMENTARY.

            ### INPUT TEXT:
            \(preprocessedMarkdown)

            ### FINAL RAW MARKDOWN OUTPUT:
            """

        do {
            // Now errors are caught by the 'catch' block below
            let formatted = try await callMiniMaxAPI(prompt: ultimatePrompt)
            let cleaned = cleanAIResponse(formatted)
            
            await MainActor.run {
                self.aiFormattedMarkdown = cleaned
                self.markdownContent = cleaned
                self.statusMessage = "✅ Successfully formatted!"
                self.isFormattingWithAI = false // Stop loading
            }
        } catch {
            await MainActor.run {
                self.statusMessage = "❌ AI Error: \(error.localizedDescription)"
                self.isFormattingWithAI = false // Stop loading
            }
        }
    }

    private func preprocessBrokenWords(_ text: String) -> String {
        var processed = text

        // Fix hyphenated words split by a newline (very common in PDFs)
        // Example: "inter-\nnational" -> "international"
        let hyphenPattern = "([a-zA-Z])-\\s*\\n\\s*([a-zA-Z])"
        processed = processed.replacingOccurrences(
            of: hyphenPattern,
            with: "$1$2",
            options: .regularExpression
        )

        return processed
    }

    private func callMiniMaxAPI(prompt: String) async throws -> String {
        let apiKey = Bundle.main.object(forInfoDictionaryKey: "MiniMaxAPIKey") as? String ?? ""
        let url = URL(string: "https://api.minimax.chat/v1/text/chatcompletion_v2")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(
            "Bearer \(apiKey)",
            forHTTPHeaderField: "Authorization"
        )

        let body: [String: Any] = [
            "model": "MiniMax-M2.7",
            "messages": [
                [
                    "role": "user",
                    "content": prompt,
                ]
            ],
            "temperature": 0.1,
            "max_tokens": 8000,
            "stream": false
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(
            MiniMaxResponse.self,
            from: data
        )

        return response.choices[0].message.content
    }

    private func extractMarkdownFrom(_ pdf: PDFDocument) -> String {
        var fullText = ""
        let pageCount = pdf.pageCount

        for i in 0..<pageCount {
            guard let page = pdf.page(at: i) else { continue }

            // PDFKit's .string provides the text in the correct reading order
            // which is usually better than iterating through AttributedStrings
            if let pageText = page.string {
                // Basic cleaning: remove null characters or weird PDF artifacts
                let cleanedPage = pageText.replacingOccurrences(
                    of: "\0",
                    with: ""
                )
                fullText += "--- Page \(i + 1) ---\n"
                fullText += cleanedPage + "\n\n"
            }
        }

        return fullText.isEmpty ? "No text extracted." : fullText
    }
}

// MARK: - Supporting types
struct MiniMaxResponse: Codable {
    let choices: [Choice]

    struct Choice: Codable {
        let message: Message
    }

    struct Message: Codable {
        let content: String
    }
}
