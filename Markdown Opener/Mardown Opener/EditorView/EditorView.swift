//
//  EditorView.swift
//  Markdown Opener
//
//  Created by alfred chen on 10/11/2025.
//

import PDFKit
import QuickLook
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WebKit

// MARK: - Editor View (Main UI)
struct EditorView: View {
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @ObservedObject private var vm = MultiSettingsViewModel.shared

    @EnvironmentObject var store: DocumentStore
    @EnvironmentObject var convo: ConversationStore
    @EnvironmentObject var router: OpenURLRouter
    @EnvironmentObject var flashcardStore: FlashcardStore
    @EnvironmentObject var mcStore: MCStore
    @EnvironmentObject private var tagsManager: TagsManager
    @State private var incomingURLs: [URL] = []
    @State private var files: [URL] = []
    @State private var currentURL: URL? = nil
    @State private var text: String = ""
    @State private var isLoadingFile = false
    @State private var showingPicker = false
    @State private var showingSaveAs = false
    @State private var newName: String = ""
    @State private var summarizing = false
    @State private var errorMessage: String?
    @State private var pdfDocument: PDFDocument? = nil
    @State private var docxAttributed: NSAttributedString? = nil
    @State private var isEditing = false
    @State private var preferredViewForCurrent: ViewMode = .preview
    @State private var showingChatSheet = false
    @State private var showingFlashcards = false
    @State private var showingMCcards = false
    @State private var generatingFlashcards = false
    @State private var flashcardsLoaded = false
    @State private var showingRenameSheet = false
    @State private var renameName: String = ""
    @State private var pendingDeleteURL: URL? = nil
    @State private var showingDeleteAlert = false
    @StateObject private var flashSession = FlashcardSession()
    @StateObject private var mcSession = MCSession()
    @State private var isSelecting = false
    @State private var showingBatchDeleteAlert = false
    @State private var selectedFiles: Set<URL> = []
    @State private var selectedFilter: FileFilter = .all
    @State private var showingUnsavedAlert = false
    @EnvironmentObject private var favorites: FavoritesManager
    @State private var showingTagManager = false
    @State private var isEditorFullScreen = false
    @State private var sidebarVisible = true
    @State private var showingSavedChats = false
    @AppStorage("ads_disabled") var adsDisabled: Bool = false
    @AppStorage("manually_ads_disabled") var manually_adsDisabled: Bool = false

    enum ViewMode { case preview, native }

    @State private var selectedTab: Tab = .editor
    @State private var originalText: String = ""
    @State private var askAISelectedText = ""
    @State private var showingSettingsSheet = false
    @State private var selectionChatItem: SelectionChatPresentationItem?
    @State private var fileSort: FileSort = .dateNew
    @State private var expandedGroups: Set<ExpandableSection> = []
    @State private var autoSaveTimer: Timer?
    @State private var lastAutoSaveText: String = ""
    
    @AppStorage("editor_auto_save") private var autoSaveEnabled: Bool = true
    @AppStorage("editor_auto_save_interval") private var autoSaveInterval: Int = 30

    private var isPDF: Bool { currentURL?.pathExtension.lowercased() == "pdf" }
    private var isDOCX: Bool {
        currentURL?.pathExtension.lowercased() == "docx"
    }
    private var isPPTX: Bool {
        let ext = currentURL?.pathExtension.lowercased()
        return ext == "ppt" || ext == "pptx"
    }
    private var isEditableText: Bool {
        guard let url = currentURL else { return false }
        let ext = url.pathExtension.lowercased()
        return ext == "md" || ext == "txt"
    }

    private var hasUnsavedChanges: Bool {
        guard let url = currentURL else { return false }
        let ext = url.pathExtension.lowercased()
        return (ext == "md" || ext == "txt") && text != originalText
    }

    private var isPPtorPPTX: Bool {
        guard let url = currentURL else { return false }
        let ext = url.pathExtension.lowercased()
        return ext == "ppt" || ext == "pptx"
    }

    var body: some View {
        EditorViewBody(
            currentURL: currentURL,
            isLoadingFile: isLoadingFile,
            showingPicker: $showingPicker,
            showingSaveAs: $showingSaveAs,
            newName: $newName,
            showingFlashcards: $showingFlashcards,
            showingMCcards: $showingMCcards,
            showingRenameSheet: $showingRenameSheet,
            renameName: $renameName,
            showingDeleteAlert: $showingDeleteAlert,
            pendingDeleteURL: $pendingDeleteURL,
            showingChatSheet: $showingChatSheet,
            showingUnsavedAlert: $showingUnsavedAlert,
            showingTagManager: $showingTagManager,
            showingSettingsSheet: $showingSettingsSheet,
            showingSavedChats: $showingSavedChats,
            showingBatchDeleteAlert: $showingBatchDeleteAlert,
            errorMessage: $errorMessage,
            files: $files,
            text: $text,
            isEditing: $isEditing,
            preferredViewForCurrent: $preferredViewForCurrent,
            pdfDocument: $pdfDocument,
            docxAttributed: $docxAttributed,
            flashSession: flashSession,
            mcSession: mcSession,
            store: store,
            flashcardStore: flashcardStore,
            mcStore: mcStore,
            convo: convo,
            selectedFiles: $selectedFiles,
            selectedFilter: $selectedFilter,
            isSelecting: $isSelecting,
            sidebarVisible: $sidebarVisible,
            isEditorFullScreen: $isEditorFullScreen,
            selectedTab: $selectedTab,
            selectionChatItem: $selectionChatItem,
            fileSort: $fileSort,
            expandedGroups: $expandedGroups,
            isPDF: isPDF,
            isDOCX: isDOCX,
            isPPTX: isPPTX,
            isEditableText: isEditableText,
            hasUnsavedChanges: hasUnsavedChanges,
            isPPtorPPTX: isPPtorPPTX,
            onOpen: { url in await open(url) },
            onDelete: { url in await delete(url) },
            exportCSV: { cards in mcCardsToCSV(cards) },
            onDismissKeyboard: dismissKeyboard,
            onHandleAskAISelection: handleAskAISelection,
            onRefreshFiles: refreshFiles,
            onSave: save,
            onNewBlank: newBlank,
            onDiscardAndExitCurrentFile: discardAndExitCurrentFile
        )
        .onChange(of: text) { _, newValue in
            guard autoSaveEnabled,
                  isEditableText,
                  currentURL != nil,
                  newValue != originalText,
                  newValue != lastAutoSaveText else { return }
            
            autoSaveTimer?.invalidate()
            autoSaveTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(autoSaveInterval), repeats: false) { _ in
                Task { @MainActor in
                    await save()
                    lastAutoSaveText = text
                }
            }
        }
        .onChange(of: autoSaveEnabled) { _, newValue in
            if !newValue {
                autoSaveTimer?.invalidate()
                autoSaveTimer = nil
            }
        }
        .onChange(of: autoSaveInterval) { _, _ in
            // Restart timer with new interval if there's pending auto-save
            if autoSaveEnabled && autoSaveTimer != nil {
                autoSaveTimer?.invalidate()
                autoSaveTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(autoSaveInterval), repeats: false) { _ in
                    Task { @MainActor in
                        await save()
                        lastAutoSaveText = text
                    }
                }
            }
        }
        .onChange(of: router.incomingURL) { _, url in
            guard let url = url else { return }
            Task {
                if let consumedURL = router.consumePending() {
                    await handleIncoming(consumedURL)
                }
            }
        }
    }

    private let kAIReplyLanguageKey = "ai_reply_language"
    private func currentLanguageInstruction() -> String {
        let raw =
            UserDefaults.standard.string(forKey: kAIReplyLanguageKey)
            ?? AIReplyLanguage.english.rawValue
        let lang = AIReplyLanguage(rawValue: raw) ?? .english
        switch lang {
        case .english: return "Respond in English."
        case .traditionalChinese: return "請用繁體中文作答"
        }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    private func handleAskAISelection(_ selectedText: String) {
        let trimmed = selectedText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmed.isEmpty else { return }

        selectionChatItem = SelectionChatPresentationItem(
            selectedText: selectedText,
            docURL: currentURL ?? URL(fileURLWithPath: "/"),
            docText: text,
            savedChat: nil,
            restoredDocumentChat: nil
        )
    }

    @MainActor
    private func open(_ url: URL) async {
        currentURL = url
        isLoadingFile = true
        defer { isLoadingFile = false }
        
        // Ensure file ID is accessed/created
        _ = FileIDManager.shared.getFileID(for: url)

        await MainActor.run {
            ConversationStore.shared.loadFromDisk(for: url)
        }

        do {
            let data = try store.load(url)
            text = data.text
            originalText = data.text
            pdfDocument = data.pdf
            docxAttributed = data.attributed

            let savedFlash = try flashcardStore.load(for: url)
            flashSession.cards = savedFlash
            flashSession.index = 0
            flashSession.done = savedFlash.isEmpty

            let savedMC = try mcStore.load(for: url)
            mcSession.cards = savedMC
            mcSession.index = 0
            mcSession.done = savedMC.isEmpty
            mcSession.totalMarks = 0
            mcSession.totalAttempts = 0
            mcSession.perCardMarks.removeAll()

        } catch {
            errorMessage = error.localizedDescription
        }
        
        // Set default editor view based on settings
        let defaultView = MultiSettingsViewModel.shared.defaultEditorView
        isEditing = defaultView == .edit && isEditableText
    }

    @MainActor
    private func newBlank() async {
        do {
            let url = try store.saveAs(
                content: "# Untitled\n\n",
                suggestedName: "Untitled.md"
            )
            refreshFiles()
            await open(url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func save() async {
        guard let url = currentURL, isEditableText else { return }
        do {
            _ = try store.save(content: text, to: url)
            originalText = text
            refreshFiles()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func delete(_ url: URL) async {
        do {
            try store.delete(url)
            try? flashcardStore.delete(for: url)
            try? mcStore.delete(for: url)

            refreshFiles()
            if currentURL == url {
                currentURL = nil
                text = ""
                isLoadingFile = false
                preferredViewForCurrent = .preview
                pdfDocument = nil
                docxAttributed = nil
                flashSession.cards = []
                mcSession.cards = []
                flashcardsLoaded = false
                convo.clear(for: url)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func mcCardsToCSV(_ cards: [Flashcard]) -> String {
        var out = "Question,A,B,C,D,Correct\n"
        for c in cards {
            let q = c.question.replacingOccurrences(of: "\"", with: "\"\"")
            let opts = c.options.map {
                $0.replacingOccurrences(of: "\"", with: "\"\"")
            }
            let correct = ["A", "B", "C", "D"][c.correctIndex]
            out +=
                "\"\(q)\",\"\(opts[0])\",\"\(opts[1])\",\"\(opts[2])\",\"\(opts[3])\",\"\(correct)\"\n"
        }
        return out
    }

    @MainActor
    private func handleIncoming(_ url: URL) async {
        var needsStop = false
        if url.startAccessingSecurityScopedResource() { needsStop = true }
        defer { if needsStop { url.stopAccessingSecurityScopedResource() } }

        do {
            let imported = try store.importIntoLibrary(from: url)
            refreshFiles()
            await open(imported)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func discardAndExitCurrentFile() {
        currentURL = nil
        text = ""
        isLoadingFile = false
        errorMessage = nil
        preferredViewForCurrent = .preview
        pdfDocument = nil
        docxAttributed = nil
        selectedTab = .editor
        originalText = ""
    }

    private func refreshFiles() {
        files = (try? store.listDocuments()) ?? []
    }
}

