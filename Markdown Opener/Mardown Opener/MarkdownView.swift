//
//  MarkdownView.swift
//  Markdown Opener
//
//  Created by alfred chen on 9/11/2025.
//

import PDFKit
import QuickLook
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WebKit

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image("generated-image (2)")
                .resizable()
                .scaledToFit()
                .frame(width: 60, height: 60)
                .foregroundStyle(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(spacing: 12) {
                Text("Welcome to MarkMind")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Your one stop self-study app - Open a document to get started, or explore the powerful AI study tools below.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            VStack(spacing: 16) {
                FeatureRow(
                    icon: "eye",
                    title: "Rich Preview & Editing",
                    description: "View and edit documents with beautiful rendering and syntax highlighting. Perfect for self-study materials."
                )

                FeatureRow(
                    icon: "bubble.left.and.text.bubble.right.fill",
                    title: "AI Chat Assistant",
                    description: "Ask questions, summarize, extract key points, or analyze any document instantly. Your personal AI study companion."
                )

                FeatureRow(
                    icon: "square.on.square",
                    title: "Smart Flashcards",
                    description: "Generate flashcards automatically for active recall learning. The ultimate self-study tool for memorizing anything."
                )

                FeatureRow(
                    icon: "checkmark.rectangle",
                    title: "Multiple-Choice Practice",
                    description: "Create MC questions with detailed explanations to test your understanding. Track progress as you study."
                )
            }
            .padding(.horizontal)

            Text("Tap “Open File” in the sidebar or Files app to begin.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// Helper view for consistent feature rows
private struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Document Picker
struct DocumentPickerView: UIViewControllerRepresentable {
    var completion: ([URL]) -> Void  // Changed to return [URL] instead of URL?
    
    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let md = UTType(filenameExtension: "md") ?? .plainText
        let pdf = UTType.pdf
        let docx = UTType(filenameExtension: "docx") ?? .data
        let ppt = UTType(filenameExtension: "ppt") ?? .data
        let pptx = UTType(filenameExtension: "pptx") ?? .data
        let txt = UTType.plainText
        
        let types: [UTType] = [md, txt, pdf, docx, ppt, pptx]
        
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: types,
            asCopy: false
        )
        picker.allowsMultipleSelection = true  // ← THIS ENABLES MULTIPLE SELECTION
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(
        _ uiViewController: UIDocumentPickerViewController,
        context: Context
    ) {}
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let completion: ([URL]) -> Void
        
        init(completion: @escaping ([URL]) -> Void) {
            self.completion = completion
        }
        
        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            completion(urls)  // Pass all selected URLs
        }
        
        func documentPickerWasCancelled(
            _ controller: UIDocumentPickerViewController
        ) {
            completion([])  // Empty array on cancel
        }
    }
}

struct PDFViewer: UIViewRepresentable {
    let document: PDFDocument?

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.document = document
        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        uiView.document = document
    }
}

struct AttributedTextViewer: UIViewRepresentable {
    let attributedText: NSAttributedString?

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isScrollEnabled = true
        textView.backgroundColor = .clear
        textView.attributedText = attributedText
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        uiView.attributedText = attributedText
    }
}

// MARK: - Share Sheet
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    static func present(items: [Any]) {
        guard
            let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
            let root = scene.windows.first(where: { $0.isKeyWindow })?
                .rootViewController
        else { return }

        let vc = UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
        if let pop = vc.popoverPresentationController {
            pop.sourceView = root.view
            pop.sourceRect = CGRect(
                x: root.view.bounds.midX,
                y: root.view.bounds.midY,
                width: 1,
                height: 1
            )
            pop.permittedArrowDirections = []
        }
        root.present(vc, animated: true)
    }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
        return vc
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}



// MARK: - Model
struct ShortcutItem: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let prompt: String
    let isPrimary: Bool
}

// MARK: - Subviews
private struct ShortcutPill: View {
    let title: String
    let isPrimary: Bool

    var body: some View {
        HStack(spacing: 6) {
            if isPrimary { Image(systemName: "text.magnifyingglass") }
            Text(title)
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.white)
        .clipShape(Capsule())
        .overlay(
            Capsule().stroke(Color.gray, lineWidth: 1)
        )
    }
}

struct ShortcutsBar: View {
    let items: [ShortcutItem]
    @Binding var showShortcuts: Bool
    @Binding var autoSend: Bool
    let sending: Bool
    let onTap: (ShortcutItem) -> Void

    var body: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(items) { item in
                        Button {
                            onTap(item)
                        } label: {
                            ShortcutPill(
                                title: item.title,
                                isPrimary: item.isPrimary
                            )
                        }
                        .disabled(sending)
                        .opacity(sending ? 0.5 : 1)
                    }
                    menuButton
                }
                .padding(.horizontal, 16)
            }

            HStack {
                if sending {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Thinking...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 6)
        .background(Color(.secondarySystemBackground).opacity(0.5))
    }

    private var menuButton: some View {
        Menu {
            Toggle(isOn: $autoSend) {
                Label(
                    "Send instantly",
                    systemImage: autoSend
                        ? "paperplane.fill" : "paperplane"
                )
            }
            Toggle(isOn: $showShortcuts) {
                Label(
                    "Show shortcuts",
                    systemImage: "slider.horizontal.3"
                )
            }
        } label: {
            Image(systemName: "ellipsis.circle.fill")
                .font(.system(size: 20))
                .foregroundColor(.secondary)
                .frame(width: 32, height: 32)
        }
    }
}



struct InputBar: View {
    @Binding var input: String
    private let documentStore = GCSDocumentStore.shared
    let hasSeed: Bool
    let sending: Bool
    @Binding var selectedFiles: [(url: URL, content: String)]
    @Binding var showFilePicker: Bool
    let onSeed: () -> Void
    let docURL: URL

    let onSend: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(alignment: .bottom, spacing: 12) {
                Button(action: { showFilePicker = true }) {
                    Image(systemName: selectedFiles.isEmpty ? "plus.rectangle.on.folder" : "doc.badge.plus")
                        .font(.system(size: 20, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundColor(selectedFiles.count >= 10 ? .gray : .blue)
                        .frame(width: 36, height: 36)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .disabled(selectedFiles.count >= 10)

                VStack(alignment: .leading, spacing: 4) {
                    if !selectedFiles.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.fill")
                                .font(.caption2)
                            Text("\(selectedFiles.count) file(s)")
                                .font(.caption)
                        }
                        .foregroundColor(.secondary)
                    }

                    ZStack(alignment: .leading) {
                        if input.isEmpty {
                            Text(hasSeed ? "Add a message..." : "Ask about this file")
                        }
                        TextField("", text: $input, axis: .vertical)
                            .lineLimit(1...9)
                            .foregroundColor(.primary)
                    }
                    .font(.body)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))

                Button(action: onSend) {
                    ZStack {
                        Circle()
                            .fill(sending
                                ? AnyShapeStyle(Color.gray)
                                : AnyShapeStyle(LinearGradient(colors: [.blue, .cyan], startPoint: .leading, endPoint: .trailing))
                            )
                            .frame(width: 36, height: 36)

                        if sending {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                }
                .disabled(
                    input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || sending
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(.systemBackground))
        }
        .sheet(isPresented: $showFilePicker) {
            InAppFilePicker(
                documentStore: documentStore,
                selectedFiles: $selectedFiles,
                docURL: docURL
            )
        }
    }
}

// MARK: - QuickLook Preview
struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let ql = QLPreviewController()
        ql.dataSource = context.coordinator
        return ql
    }

    func updateUIViewController(
        _ controller: QLPreviewController,
        context: Context
    ) {}

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let parent: QuickLookPreview
        init(_ parent: QuickLookPreview) { self.parent = parent }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(
            _ controller: QLPreviewController,
            previewItemAt index: Int
        ) -> QLPreviewItem {
            parent.url as NSURL
        }
    }
}

// MARK: - Chat Sheet
struct ChatSheet: View {
    @EnvironmentObject var convo: ConversationStore
    let docURL: URL
    let docText: String
    let initialPrompt: String
    @StateObject private var adManager = InterstitialAdManager.shared
    @State private var seedPrompt: String = ""
    @State private var shouldAutoSend = false

    var body: some View {
        ChatPanel(
            docURL: docURL,
            docText: docText,
            seedPrompt: seedPrompt,
            autoSend: shouldAutoSend
        )
        .environmentObject(ConversationStore.shared)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            adManager.loadAd()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                presentInterstitialIfReady()
            }
            if !shouldAutoSend {
                seedPrompt = initialPrompt
                shouldAutoSend = true
            }
        }
        .onDisappear {
            presentInterstitialIfReady()
        }
    }

    func presentInterstitialIfReady() {
        guard
            let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
            let rootVC = scene.windows.first(where: { $0.isKeyWindow })?
                .rootViewController
        else { return }
        InterstitialAdManager.shared.present(from: rootVC)
    }

}

enum Tab: Hashable {
    case chat
    case editor
    case flashcards
    case memorize
    case mccards
    case tts
    
}

struct SheetsAndAlertsModifier: ViewModifier {
    @Binding var showingChatSheet: Bool
    @Binding var showingPicker: Bool
    @Binding var showingSaveAs: Bool
    @Binding var newName: String
    @Binding var showingFlashcards: Bool
    @Binding var showingMCcards: Bool                    // ← Added
    @Binding var showingRenameSheet: Bool
    @Binding var renameName: String
    @Binding var showingDeleteAlert: Bool
    @Binding var pendingDeleteURL: URL?

    let docURL: URL?
    let docText: String
    let flashSession: FlashcardSession
    let mcSession: MCSession                              // ← Added
    let store: DocumentRepository
    let flashcardStore: FlashcardStore
    let mcStore: MCStore                                  // ← Added
    let convo: ConversationStore
    @Binding var errorMessage: String?
    @Binding var files: [URL]
    @Binding var currentURL: URL?

    let onOpen: (URL) async -> Void
    let onDelete: (URL) async -> Void
    let exportCSV: ([Flashcard]) -> String                // Used for MC cards (same struct)

    private let kAIReplyLanguageKey = "aireplylanguage"

    private func currentLanguageInstruction() -> String {
        let raw =
            UserDefaults.standard.string(forKey: kAIReplyLanguageKey)
            ?? AIReplyLanguage.english.rawValue
        let lang = AIReplyLanguage(rawValue: raw) ?? .english
        switch lang {
        case .english:
            return "Respond in English."
        case .traditionalChinese:
            return "請用正體中文回答."
        }
    }

    func body(content: Content) -> some View {
        content
            // Chat sheet – always .sheet
            .sheet(isPresented: $showingChatSheet) {
                if let url = docURL {
                    ChatPanel(
                        docURL: url,
                        docText: docText,
                        seedPrompt:
                            """
                            Summarize this document for efficient revision. Use headings, bullet points, and not too long.
                            \(currentLanguageInstruction())
                            """
                    )
                    .environmentObject(ConversationStore.shared)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                } else {
                    Text("Open a document first").padding()
                }
            }

            .sheet(isPresented: $showingPicker) {
                DocumentPickerView { urls in
                    Task {
                        guard !urls.isEmpty else {
                            showingPicker = false
                            return
                        }

                        var importedURLs: [URL] = []
                        errorMessage = nil

                        // Optional: give user feedback during import
                        // You could set a @State var isImporting = true here if desired

                        for url in urls {
                            var shouldStopAccess = false
                            if url.startAccessingSecurityScopedResource() {
                                shouldStopAccess = true
                            }
                            defer {
                                if shouldStopAccess {
                                    url.stopAccessingSecurityScopedResource()
                                }
                            }

                            do {
                                let imported = try await store.importIntoLibraryAsync(from: url)
                                importedURLs.append(imported)
                            } catch {
                                Log.error("Failed to import \(url.lastPathComponent)", category: .fileIO, error: error)
                                if errorMessage == nil {
                                    errorMessage = "Some files could not be imported."
                                }
                                // Continue importing others
                            }
                        }

                        // Refresh file list
                        files = (try? store.listDocuments()) ?? []

                        // Open the first successfully imported file (optional but nice UX)
                        if let firstImported = importedURLs.first {
                            await onOpen(firstImported)
                        }

                        showingPicker = false
                    }
                }
                .presentationDetents([.large])  // Better for multi-selection
                .presentationDragIndicator(.visible)
            }

            .sheet(isPresented: $showingSaveAs) {
                NavigationStack {
                    Form {
                        TextField("File name", text: $newName)
                    }
                    .navigationTitle("Save As")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showingSaveAs = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                Task {
                                    do {
                                        let targetName =
                                            newName.isEmpty ? "Untitled.md" : newName
                                        if let gcsStore = store as? GCSDocumentStore {
                                            let url = try await gcsStore.saveAsAsync(
                                                content: docText,
                                                suggestedName: targetName
                                            )
                                            files = (try? store.listDocuments()) ?? []
                                            await onOpen(url)
                                        }
                                    } catch {
                                        errorMessage = error.localizedDescription
                                    }
                                    showingSaveAs = false
                                }
                            }
                            .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
            }
            .sheet(isPresented: $showingMCcards) {
                if let url = docURL {
                    MCStudyView(
                        session: mcSession,
                        docURL: url,
                        docText: docText,
                        ttsEnabled: .constant(MultiSettingsViewModel.shared.ttsEnabled)
                    )
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                }
            }

            .sheet(isPresented: $showingRenameSheet) {
                NavigationStack {
                    Form {
                        TextField("Name", text: $renameName)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    .navigationTitle("Rename")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                showingRenameSheet = false
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                Task {
                                    guard let src = currentURL else {
                                        showingRenameSheet = false
                                        return
                                    }
                                    
                                    let trimmed = renameName
                                        .trimmingCharacters(in: .whitespacesAndNewlines)
                                        .replacingOccurrences(of: "/", with: "_")
                                    
                                    guard !trimmed.isEmpty else {
                                        showingRenameSheet = false
                                        return
                                    }
                                    
                                    let finalName = {
                                        let ext = src.pathExtension
                                        return ext.isEmpty ? trimmed : "\(trimmed).\(ext)"
                                    }()
                                    
                                    do {
                                        let newURL = try store.rename(src, to: finalName)
                                        files = (try? store.listDocuments()) ?? []
                                        await onOpen(newURL)
                                    } catch {
                                        errorMessage = error.localizedDescription
                                    }
                                    
                                    showingRenameSheet = false
                                }
                            }
                            .disabled(renameName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    .presentationDetents([.medium])
                    .onAppear {
                        if let url = currentURL {
                            renameName = url.deletingPathExtension().lastPathComponent
                        }
                    }
                }
            }

            // Delete alert (unchanged)
            .alert("Delete this file?", isPresented: $showingDeleteAlert) {
                Button("Delete", role: .destructive) {
                    Task {
                        if let target = pendingDeleteURL {
                            await onDelete(target)
                        }
                        pendingDeleteURL = nil
                    }
                }
                Button("Cancel", role: .cancel) {
                    pendingDeleteURL = nil
                }
            } message: {
                Text(pendingDeleteURL?.lastPathComponent ?? "")
            }

            // Error alert
            .alert("Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "An unknown error occurred")
            }
    }
}
