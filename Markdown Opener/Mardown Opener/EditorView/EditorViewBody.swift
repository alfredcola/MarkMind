//
//  EditorViewBody.swift
//  Markdown Opener
//
//  Created by alfred chen on 8/3/2026.
//
import PDFKit
import QuickLook
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WebKit

struct EditorViewBody: View {
    let currentURL: URL?
    let isLoadingFile: Bool
    @Binding var showingPicker: Bool
    @Binding var showingSaveAs: Bool
    @Binding var newName: String
    @Binding var showingFlashcards: Bool
    @Binding var showingMCcards: Bool
    @Binding var showingRenameSheet: Bool
    @Binding var renameName: String
    @Binding var showingDeleteAlert: Bool
    @Binding var pendingDeleteURL: URL?
    @Binding var showingChatSheet: Bool
    @Binding var showingUnsavedAlert: Bool
    @Binding var showingTagManager: Bool
    @Binding var showingSettingsSheet: Bool
    @Binding var showingSavedChats: Bool
    @Binding var showingBatchDeleteAlert: Bool
    @Binding var errorMessage: String?
    @Binding var files: [URL]
    @Binding var text: String
    @Binding var isEditing: Bool
    @Binding var preferredViewForCurrent: EditorView.ViewMode
    @Binding var pdfDocument: PDFDocument?
    @Binding var docxAttributed: NSAttributedString?
    let flashSession: FlashcardSession
    let mcSession: MCSession
    let store: DocumentStore
    let flashcardStore: FlashcardStore
    let mcStore: MCStore
    let convo: ConversationStore
    @Binding var selectedFiles: Set<URL>
    @Binding var selectedFilter: FileFilter
    @Binding var isSelecting: Bool
    @Binding var sidebarVisible: Bool
    @Binding var isEditorFullScreen: Bool
    @Binding var selectedTab: Tab
    @Binding var selectionChatItem: SelectionChatPresentationItem?
    @Binding var fileSort: FileSort
    @Binding var expandedGroups: Set<ExpandableSection>
    
    @AppStorage("expandedFileGroups") private var expandedFileGroupsData: Data = Data()
    @AppStorage("expandedStarred") private var expandedStarred = true
    
    @State private var showingFindReplace = false
    @State private var findText = ""
    @State private var replaceText = ""
    @State private var findResults: [Range<String.Index>] = []
    @State private var currentFindIndex = 0
    @State private var lastSavedTime: Date?
    @State private var isAutoSaving = false
    
    @ObservedObject private var settingsVM = MultiSettingsViewModel.shared
    
    @AppStorage("editor_font_size") private var editorFontSize: Double = 17.0
    @AppStorage("editor_show_line_numbers") private var showLineNumbers: Bool = false
    @AppStorage("editor_spell_check") private var spellCheckEnabled: Bool = true
    
    private var fontSize: CGFloat {
        settingsVM.editorFontSize
    }
    
    private var lineNumbersEnabled: Bool {
        settingsVM.showLineNumbers
    }
    
    private var isAutoSaveEnabled: Bool {
        settingsVM.autoSaveEnabled
    }
    
    private var autoSaveInterval: Int {
        settingsVM.autoSaveInterval
    }
    
    private var defaultEditorView: EditorViewType {
        settingsVM.defaultEditorView
    }
    
    let isPDF: Bool
    let isDOCX: Bool
    let isPPTX: Bool
    let isEditableText: Bool
    let hasUnsavedChanges: Bool
    let isPPtorPPTX: Bool

    let onOpen: (URL) async -> Void
    let onDelete: (URL) async -> Void
    let exportCSV: ([Flashcard]) -> String
    let onDismissKeyboard: () -> Void
    let onHandleAskAISelection: (String) -> Void
    let onRefreshFiles: () -> Void
    let onSave: () async -> Void
    let onNewBlank: () async -> Void
    let onDiscardAndExitCurrentFile: () -> Void
    
    private var wordCount: Int {
        let words = text.split { $0.isWhitespace || $0.isNewline }
        return words.count
    }
    
    private var characterCount: Int {
        return text.count
    }
    
    private var readingTime: Int {
        let wordsPerMinute = 200
        return max(1, wordCount / wordsPerMinute)
    }
    
    private var lineCount: Int {
        return text.components(separatedBy: .newlines).count
    }
    
    private func performFind() {
        findResults = []
        guard !findText.isEmpty else { return }
        var searchStart = text.startIndex
        while let range = text.range(of: findText, range: searchStart..<text.endIndex) {
            findResults.append(range)
            searchStart = range.upperBound
        }
        currentFindIndex = 0
    }
    
    private func performReplace() {
        guard !findText.isEmpty,
              currentFindIndex < findResults.count else { return }
        
        let range = findResults[currentFindIndex]   // already Range<AttributedString.Index>
        
        text.replaceSubrange(range, with: replaceText)   // works directly
        
        performFind()   // re-search — will produce AttributedString.Index ranges again
    }
    
    private func replaceAll() {
        guard !findText.isEmpty else { return }
        text = text.replacingOccurrences(of: findText, with: replaceText)
        performFind()
    }
    
    private func insertMarkdownFormatting(_ prefix: String, _ suffix: String = "", _ placeholder: String = "text") {
        let currentText = text
        let insertion = "\(prefix)\(placeholder)\(suffix)"
        text = currentText + insertion
    }
    
    private func wrapSelectionWithMarkdown(_ prefix: String, _ suffix: String = "") {
        text += "\(prefix)\(suffix)"
    }

    var body: some View {
        Group {
            if UIDevice.current.userInterfaceIdiom == .pad {
                AdaptivePadLayout(
                    sidebar: {
                        NavigationStack {
                            recentList
                                .toolbar {
                                    ToolbarItemGroup(
                                        placement: .navigationBarLeading
                                    ) {
                                        Button {
                                            showingPicker = true
                                        } label: {
                                            Label("Open", systemImage: "folder")
                                        }
                                        .keyboardShortcut("o", modifiers: .command)

                                        Button {
                                            Task { await onNewBlank() }
                                        } label: {
                                            Label(
                                                "New",
                                                systemImage:
                                                    "plus.rectangle.on.folder"
                                            )
                                        }
                                        .keyboardShortcut("n", modifiers: .command)

                                        Button {
                                            showingSettingsSheet = true
                                        } label: {
                                            Label(
                                                "Settings",
                                                systemImage: "gearshape"
                                            )
                                        }
                                    }
                                    ToolbarItem(
                                        placement: .navigationBarTrailing
                                    ) {
                                        if $sidebarVisible.wrappedValue
                                            && currentURL != nil
                                        {
                                            Button {
                                                withAnimation {
                                                    sidebarVisible = false
                                                }
                                            } label: {
                                                Label(
                                                    "Hide Sidebar",
                                                    systemImage:
                                                        "sidebar.leading"
                                                )
                                            }
                                        }
                                    }
                                }
                        }
                    },
                    detail: {
                        if currentURL == nil && !isLoadingFile {
                            emptyStateView
                        } else {
                            navigationContent
                        }
                    },
                    sidebarVisible: $sidebarVisible
                )
                .modifier(
                    SheetsAndAlertsModifier(
                        showingChatSheet: $showingChatSheet,
                        showingPicker: $showingPicker,
                        showingSaveAs: $showingSaveAs,
                        newName: $newName,
                        showingFlashcards: $showingFlashcards,
                        showingMCcards: $showingMCcards,
                        showingRenameSheet: $showingRenameSheet,
                        renameName: $renameName,
                        showingDeleteAlert: $showingDeleteAlert,
                        pendingDeleteURL: $pendingDeleteURL,
                        docURL: currentURL,
                        docText: text,
                        flashSession: flashSession,
                        mcSession: mcSession,
                        store: store,
                        flashcardStore: flashcardStore,
                        mcStore: mcStore,
                        convo: convo,
                        errorMessage: $errorMessage,
                        files: $files,
                        currentURL: Binding(
                            get: { currentURL },
                            set: { _ in }
                        ),
                        onOpen: onOpen,
                        onDelete: onDelete,
                        exportCSV: exportCSV
                    )
                )
                .onAppear {
                    Task { onRefreshFiles() }
                }
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: NSNotification.Name("DocumentSaved")
                    )
                ) { _ in
                    Task { onRefreshFiles() }
                }
            } else {
                NavigationView {
                    navigationContent
                        .toolbar {
                            if currentURL == nil {
                                ToolbarItem {
                                    NavigationLink(
                                        destination: MultiSettingsView(showingTagManager: $showingTagManager)
                                    ) {
                                        Label(
                                            "Settings",
                                            systemImage: "gearshape"
                                        )
                                    }
                                }
                            }
                        }
                        .modifier(
                            SheetsAndAlertsModifier(
                                showingChatSheet: $showingChatSheet,
                                showingPicker: $showingPicker,
                                showingSaveAs: $showingSaveAs,
                                newName: $newName,
                                showingFlashcards: $showingFlashcards,
                                showingMCcards: $showingMCcards,
                                showingRenameSheet: $showingRenameSheet,
                                renameName: $renameName,
                                showingDeleteAlert: $showingDeleteAlert,
                                pendingDeleteURL: $pendingDeleteURL,
                                docURL: currentURL,
                                docText: text,
                                flashSession: flashSession,
                                mcSession: mcSession,
                                store: store,
                                flashcardStore: flashcardStore,
                                mcStore: mcStore,
                                convo: convo,
                                errorMessage: $errorMessage,
                                files: $files,
                                currentURL: Binding(
                                    get: { currentURL },
                                    set: { _ in }
                                ),
                                onOpen: onOpen,
                                onDelete: onDelete,
                                exportCSV: exportCSV
                            )
                        )
                        .onAppear {
                            Task { onRefreshFiles() }
                        }
                        .onReceive(
                            NotificationCenter.default.publisher(
                                for: NSNotification.Name("DocumentSaved")
                            )
                        ) { _ in
                            Task { onRefreshFiles() }
                        }
                }
            }
        }
        .alert(
            "Delete \(selectedFiles.count) files?",
            isPresented: $showingBatchDeleteAlert
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    await batchDelete(selectedFiles)
                }
            }
        } message: {
            Text("This action cannot be undone.")
        }
        .alert("Unsaved changes", isPresented: $showingUnsavedAlert) {
            Button("Save") {
                Task {
                    await onSave()
                    onDiscardAndExitCurrentFile()
                }
            }
            Button("Discard", role: .destructive) {
                onDiscardAndExitCurrentFile()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You have unsaved edits. Save before leaving this file?")
        }
        .sheet(isPresented: $showingTagManager) {
            TagManagerView()
        }
        .sheet(isPresented: $showingSettingsSheet) {
            NavigationStack {
                MultiSettingsView(showingTagManager: $showingTagManager)
                    .navigationTitle("Settings")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(.visible, for: .navigationBar)
                    .toolbarBackground(
                        Color(UIColor.systemGroupedBackground),
                        for: .navigationBar
                    )
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .preferredColorScheme(nil)
    }
    
    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text")
                .font(.system(size: 64))
                .foregroundStyle(.quaternary)
            Text("No document open")
                .font(.title2)
                .foregroundStyle(.secondary)
            Button("Open File") { showingPicker = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemGroupedBackground))
    }

    @ViewBuilder
    private var chatTab: some View {
        if let url = currentURL {
            ChatPanel(
                docURL: url,
                docText: text,
                seedPrompt: """
                    Summarize this document for efficient revision. Use headings, bullet points, and keep it concise.
                    """
            )
            .tabItem {
                Label("Chat", systemImage: "bubble.left.and.text.bubble.right")
            }
            .tag(Tab.chat)
        }
    }

    @ViewBuilder
    private var editorTab: some View {
        mainEditor
            .tabItem { Label("Editor", systemImage: "doc.text") }
            .tag(Tab.editor)
    }

    @ViewBuilder
    private var mcstudyTab: some View {
        MCStudyView(
            session: mcSession,
            docURL: currentURL,
            docText: text,
            onGenerate: nil,
            ttsEnabled: .constant(MultiSettingsViewModel.shared.ttsEnabled)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tabItem {
            Label("MC", systemImage: "checkmark.rectangle")
        }
        .tag(Tab.mccards)
    }

    @ViewBuilder
    private var flashcardsTab: some View {
        FlashcardStudyView(
            session: flashSession,
            docURL: currentURL,
            docText: text,
            onGenerate: nil,
            ttsEnabled: .constant(MultiSettingsViewModel.shared.ttsEnabled)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tabItem {
            Label("Flashcards", systemImage: "square.on.square")
        }
        .tag(Tab.flashcards)
    }

    @ViewBuilder
    private var navigationContent: some View {
        Group {
            if currentURL == nil && !isLoadingFile {
                emptyStateContent
            } else {
                ZStack {
                    TabView(selection: $selectedTab) {
                        chatTab
                        editorTabFullScreenAware
                        if !isPPtorPPTX {
                            mcstudyTab
                            flashcardsTab
                        }
                    }
                    .opacity(isEditorFullScreen ? 0 : 1)
                    .disabled(isEditorFullScreen)

                    if isEditorFullScreen {
                        fullScreenEditor
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: isEditorFullScreen)
                .onTapGesture(count: 2) {
                    guard selectedTab == .editor else { return }
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isEditorFullScreen.toggle()
                        if isEditorFullScreen { onDismissKeyboard() }
                    }
                }
                .onChange(of: selectedTab) {
                    if selectedTab != .editor && isEditorFullScreen {
                        withAnimation { isEditorFullScreen = false }
                    }
                }
            }
        }
        .navigationTitle(
            isEditorFullScreen
                ? ""
                : {
                    let baseTitle = currentURL?.lastPathComponent ?? "MarkMind"
                    return baseTitle
                }()
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(isEditorFullScreen ? .hidden : .visible, for: .navigationBar)
        .toolbar(
            isEditorFullScreen && selectedTab == .editor ? .hidden : .visible,
            for: .tabBar
        )
        .toolbar {
            if UIDevice.current.userInterfaceIdiom == .pad {
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    if !sidebarVisible {
                        Button {
                            withAnimation { sidebarVisible = true }
                        } label: {
                            Image(systemName: "sidebar.leading")
                        }
                    }
                }
            }
            if currentURL != nil {
                if !(UIDevice.current.userInterfaceIdiom == .pad) {
                    ToolbarItemGroup(placement: .navigationBarLeading) {
                        Button {
                            if hasUnsavedChanges {
                                showingUnsavedAlert = true
                            } else {
                                onDiscardAndExitCurrentFile()
                            }
                        } label: {
                            Label("Close", systemImage: "xmark.rectangle")
                        }
                    }
                }

                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if isEditing && isEditableText {
                        Button {
                            showingFindReplace = true
                        } label: {
                            Label("Find", systemImage: "magnifyingglass")
                        }
                        .keyboardShortcut("f", modifiers: .command)
                    }
                    
                    Menu {
                        Button {
                            newName =
                                currentURL?.lastPathComponent ?? "Untitled.md"
                            showingSaveAs = true
                        } label: {
                            Label(
                                "Save As",
                                systemImage: "square.and.arrow.down.on.square"
                            )
                        }
                        .disabled(isPDF || isDOCX || isPPTX)

                        Button {
                            Task { await onSave() }
                        } label: {
                            Label("Save", systemImage: "square.and.arrow.down")
                        }
                        .disabled(currentURL == nil || !isEditableText)

                        Divider()

                        Button(role: .destructive) {
                            if let url = currentURL {
                                ConversationStore.shared.clearForDeletionOnDisk(
                                    for: url
                                )
                            }
                        } label: {
                            Label(
                                "Remove Chat Messages",
                                systemImage: "bubble.left.and.bubble.right"
                            )
                        }
                        .disabled(currentURL == nil)

                        Button {
                            renameName =
                                currentURL?.deletingPathExtension()
                                .lastPathComponent ?? ""
                            showingRenameSheet = true
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        .disabled(currentURL == nil)
                        .keyboardShortcut("r", modifiers: .command)

                        Button(role: .destructive) {
                            pendingDeleteURL = currentURL
                            showingDeleteAlert = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .disabled(currentURL == nil)
                        .keyboardShortcut(.delete, modifiers: .command)
                    } label: {
                        Label("File", systemImage: "doc")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var fullScreenEditor: some View {
        VStack(spacing: 0) {
            HStack {
                Text(currentURL?.lastPathComponent ?? "Untitled")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    withAnimation { isEditorFullScreen = false }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 5)
            }
            .padding(.horizontal)
            .opacity(0.8)

            mainEditor
        }
        .background(Color(UIColor.systemBackground))
    }

    @ViewBuilder
    private var editorTabFullScreenAware: some View {
        mainEditor
            .tabItem { Label("Editor", systemImage: "doc.text") }
            .tag(Tab.editor)
    }

    @ViewBuilder
    private var emptyStateContent: some View {
        VStack {
            recentList
                .toolbar {
                    ToolbarItemGroup(placement: .topBarLeading) {
                        Button {
                            showingPicker = true
                        } label: {
                            Label("Open File", systemImage: "folder")
                        }

                        Button {
                            Task { await onNewBlank() }
                        } label: {
                            Label(
                                "New",
                                systemImage: "plus.rectangle.on.folder"
                            )
                        }
                    }
                }
        }
    }

    @ViewBuilder
    private var mainEditor: some View {
        ZStack {
            VStack(spacing: 0) {
                if !isEditorFullScreen && !isPDF && !isPPTX {
                    editorToolbar
                    Divider()
                }
                
                if isEditing && isEditableText {
                    TextEditor(text: $text)
                        .font(.system(size: fontSize, design: .monospaced))
                        .padding(.top, 8)
                        .autocorrectionDisabled(!spellCheckEnabled)
                } else {
                    if pdfDocument != nil {
                        SelectableContentView(
                            contentView: {
                                let pdfView = PDFView()
                                pdfView.autoScales = true
                                pdfView.displayDirection = .vertical
                                pdfView.displayMode = .singlePageContinuous
                                pdfView.document = pdfDocument
                                return pdfView
                            }(),
                            onAskAIAboutSelection: onHandleAskAISelection,
                            isEditorFullScreen: $isEditorFullScreen
                        )
                    } else if isDOCX, let attributed = docxAttributed {
                        SelectableContentView(
                            contentView: {
                                let textView = UITextView()
                                textView.isEditable = false
                                textView.isScrollEnabled = true
                                textView.backgroundColor = .clear
                                textView.textContainerInset = UIEdgeInsets(
                                    top: 20,
                                    left: 16,
                                    bottom: 20,
                                    right: 16
                                )
                                textView.font = UIFont.systemFont(ofSize: 17)
                                textView.attributedText = attributed
                                return textView
                            }(),
                            onAskAIAboutSelection: onHandleAskAISelection,
                            isEditorFullScreen: $isEditorFullScreen
                        )
                    } else if isDOCX || isPPTX, let url = currentURL {
                        QuickLookPreview(url: url)
                    } else                     if currentURL?.pathExtension.lowercased() == "md" {
                        if preferredViewForCurrent == .preview {
                            WebMarkdownViewWithTTS(
                                markdown: text,
                                onAskAIAboutSelection: { selectedText in
                                    selectionChatItem =
                                        SelectionChatPresentationItem(
                                            selectedText: selectedText,
                                            docURL: currentURL
                                                ?? URL(fileURLWithPath: ""),
                                            docText: text,
                                            savedChat: nil,
                                            restoredDocumentChat: nil
                                        )
                                },
                                filePath: currentURL?.path, isEditorFullScreen: $isEditorFullScreen
                            )
                        } else {
                            NativeMarkdownView(
                                markdown: text,
                                ttsEnabled: .constant(
                                    MultiSettingsViewModel.shared.ttsEnabled
                                )
                            )
                        }

                    } else {
                        ScrollView {
                            Text(text)
                                .font(
                                    .system(
                                        .body,
                                        design: currentURL?.pathExtension
                                            .lowercased() == "txt"
                                            ? .monospaced : .default
                                    )
                                )
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemBackground))
        .onTapGesture(count: 2) {
            if !isEditing {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isEditorFullScreen.toggle()
                    if isEditorFullScreen {
                        onDismissKeyboard()
                    }
                }
            }
        }
        .sheet(item: $selectionChatItem) { item in
            SelectionChatView(
                selectedText: item.selectedText,
                docURL: item.docURL,
                docText: item.docText,
                savedChat: item.savedChat,
                restoredDocumentChat: item.restoredDocumentChat
            )
            .environmentObject(convo)
            .interactiveDismissDisabled()
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingFindReplace) {
            findReplaceSheet
        }
    }
    
    @ViewBuilder
    private var editorToolbar: some View {
        VStack(spacing: 0) {
            HStack {
                Text(currentURL?.lastPathComponent ?? "Untitled")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                autoSaveIndicator
                
                Toggle(isOn: $isEditing) {
                    Text(isEditing ? "Editing" : "Preview")
                }
                .labelsHidden()
                .disabled(!isEditableText)
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            
            editorStatsBar
        }
    }
    
    @ViewBuilder
    private var autoSaveIndicator: some View {
        HStack(spacing: 4) {
            if isAutoSaving {
                ProgressView()
                    .scaleEffect(0.6)
                Text("Saving...")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if lastSavedTime != nil {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
                Text("Saved")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    @ViewBuilder
    private var formattingToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                formatButton(icon: "bold", tooltip: "Bold") {
                    insertMarkdownFormatting("**", "**", "bold text")
                }
                formatButton(icon: "italic", tooltip: "Italic") {
                    insertMarkdownFormatting("*", "*", "italic text")
                }
                formatButton(icon: "strikethrough", tooltip: "Strikethrough") {
                    insertMarkdownFormatting("~~", "~~", "strikethrough")
                }
                
                formatButton(icon: "list.bullet", tooltip: "Bullet List") {
                    insertMarkdownFormatting("\n- ", "", "item")
                }
                formatButton(icon: "list.number", tooltip: "Numbered List") {
                    insertMarkdownFormatting("\n1. ", "", "item")
                }
                formatButton(icon: "checklist", tooltip: "Task List") {
                    insertMarkdownFormatting("\n- [ ] ", "", "task")
                }
                
                formatButton(icon: "heading", tooltip: "Heading") {
                    insertMarkdownFormatting("\n## ", "", "Heading")
                }
                formatButton(icon: "text.alignleft", tooltip: "Quote") {
                    insertMarkdownFormatting("\n> ", "", "quote")
                }
                formatButton(icon: "chevron.left.forwardslash.chevron.right", tooltip: "Code Block") {
                    insertMarkdownFormatting("\n```\n", "\n```", "code")
                }
                formatButton(icon: "link", tooltip: "Link") {
                    insertMarkdownFormatting("[", "](url)", "link text")
                }
                
                formatButton(icon: "line.horizontal.3", tooltip: "Find") {
                    showingFindReplace = true
                }
                
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 1, height: 20)
                
                HStack(spacing: 4) {
                    Button {
                        let current = settingsVM.editorFontSize
                        let newSize = current - 2
                        settingsVM.editorFontSize = max(12, newSize)
                    } label: {
                        Image(systemName: "textformat.size.smaller")
                            .font(.system(size: 12))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    
                    Text("\(Int(settingsVM.editorFontSize))")
                        .font(.caption2)
                        .frame(width: 24)
                    
                    Button {
                        let current = settingsVM.editorFontSize
                        let newSize = current + 2
                        settingsVM.editorFontSize = min(24, newSize)
                    } label: {
                        Image(systemName: "textformat.size.larger")
                            .font(.system(size: 12))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color(UIColor.tertiarySystemBackground))
                .cornerRadius(6)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .background(Color(UIColor.secondarySystemBackground))
    }
    
    @ViewBuilder
    private func formatButton(icon: String, tooltip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .frame(width: 32, height: 28)
                .background(Color(UIColor.tertiarySystemBackground))
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private var editorStatsBar: some View {
        HStack(spacing: 16) {
            Text("\(wordCount) words")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(characterCount) chars")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(lineCount) lines")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("~\(readingTime) min read")
                .font(.caption2)
                .foregroundStyle(.secondary)
            
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
        .background(Color(UIColor.secondarySystemBackground).opacity(0.5))
    }
    
    @ViewBuilder
    private var findReplaceSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                HStack {
                    TextField("Find", text: $findText)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: findText) { newValue in
                            performFind()
                        }
                    
                    Text("\(currentFindIndex + 1)/\(findResults.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 50)
                }
                
                TextField("Replace with", text: $replaceText)
                    .textFieldStyle(.roundedBorder)
                
                HStack {
                    Button("Replace") {
                        performReplace()
                    }
                    .disabled(findResults.isEmpty)
                    
                    Button("Replace All") {
                        replaceAll()
                    }
                    .disabled(findResults.isEmpty)
                    
                    Button("Previous") {
                        if currentFindIndex > 0 {
                            currentFindIndex -= 1
                        }
                    }
                    .disabled(findResults.isEmpty)
                    
                    Button("Next") {
                        if currentFindIndex < findResults.count - 1 {
                            currentFindIndex += 1
                        }
                    }
                    .disabled(findResults.isEmpty)
                }
                .buttonStyle(.bordered)
                
                Spacer()
            }
            .padding()
            .navigationTitle("Find & Replace")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        showingFindReplace = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private var remainingFiles: [URL] {
        files.filter { url in
            !FavoritesManager.shared.isStarred(url)
        }
    }
    
    private var taggedFiles: [URL] {
        files.filter { url in
            !TagsManager.shared.tags(for: url).isEmpty && !FavoritesManager.shared.isStarred(url)
        }
    }

    private var visibleGroups: [FileGroup] {
        let present = Set(
            remainingFiles.map { group(for: $0.pathExtension.lowercased()) }
        )
        return FileGroup.allCases.filter {
            present.contains($0) && $0 != .other
        }
    }

    private func countForGroup(_ group: FileGroup) -> Int {
        remainingFiles
            .filter { self.group(for: $0.pathExtension.lowercased()) == group }
            .filter { _ in
                selectedFilter == .all || selectedFilter.group == group
            }
            .count
    }

    private func group(for ext: String) -> FileGroup {
        switch ext.lowercased() {
        case "md": return .markdown
        case "txt": return .text
        case "pdf": return .pdf
        case "docx": return .docx
        case "ppt", "pptx": return .pptx
        default: return .other
        }
    }

    private func toggleExpanded(_ section: ExpandableSection) {
        withAnimation(.easeInOut(duration: 0.25)) {
            if expandedGroups.contains(section) {
                expandedGroups.remove(section)
            } else {
                expandedGroups.insert(section)
            }
        }
        
        switch section {
        case .tag(let tag):
            TagsManager.shared.toggleTagExpanded(tag)
        case .starred:
            expandedStarred = expandedGroups.contains(.starred)
        case .fileGroup:
            saveExpandedState()
        }
    }
    
    private func saveExpandedState() {
        var expandedFileGroups: [String] = []
        for group in expandedGroups {
            if case .fileGroup(let fg) = group {
                expandedFileGroups.append(fg.rawValue)
            }
        }
        if let data = try? JSONEncoder().encode(expandedFileGroups) {
            expandedFileGroupsData = data
        }
        if expandedGroups.contains(.starred) {
            expandedStarred = true
        } else {
            expandedStarred = false
        }
    }
    
    private func loadExpandedState() {
        var loadedGroups: Set<ExpandableSection> = []
        
        if let expandedFileGroups = try? JSONDecoder().decode([String].self, from: expandedFileGroupsData) {
            for rawValue in expandedFileGroups {
                if let group = FileGroup(rawValue: rawValue) {
                    loadedGroups.insert(.fileGroup(group))
                }
            }
        }
        
        if expandedStarred {
            loadedGroups.insert(.starred)
        }
        
        for tag in TagsManager.shared.allTags {
            if TagsManager.shared.isTagExpanded(tag) {
                loadedGroups.insert(.tag(tag))
            }
        }
        
        if loadedGroups.isEmpty {
            loadedGroups.insert(.starred)
            for g in FileGroup.allCases where g != .other {
                loadedGroups.insert(.fileGroup(g))
            }
            TagsManager.shared.expandAllTags()
        }
        
        expandedGroups = loadedGroups
    }

    private func isExpanded(_ section: ExpandableSection) -> Bool {
        expandedGroups.contains(section)
    }

    private func iconForGroup(_ group: FileGroup) -> String {
        switch group {
        case .markdown: return "doc.text"
        case .text: return "doc.plaintext"
        case .pdf: return "doc.richtext"
        case .docx: return "doc"
        case .pptx: return "play.rectangle"
        case .other: return "doc"
        }
    }

    private func colorForGroup(_ group: FileGroup) -> Color {
        switch group {
        case .markdown: return .orange
        case .text: return .blue
        case .pdf: return .red
        case .docx: return .green
        case .pptx: return .purple
        case .other: return .gray
        }
    }

    @ViewBuilder
    private var recentList: some View {
        if files.isEmpty {
            VStack(spacing: 20) {
                Text("No Documents")
                    .font(.title2)
                    .foregroundStyle(.secondary)

                Button {
                    showingPicker = true
                } label: {
                    Label("Open File", systemImage: "folder")
                        .font(.headline)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 32)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding()
        } else {
            VStack(spacing: 0) {
                HStack(spacing: 5) {
                    if !isSelecting {
                        Button {
                            showingSavedChats = true
                        } label: {
                            Image(systemName: "tray.full.fill")
                                .font(.title3.bold())
                                .foregroundColor(.primary)
                                .padding(8)
                                .background(
                                    Color(UIColor.secondarySystemBackground)
                                )
                                .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                    }

                    groupChips

                    Button {
                        withAnimation {
                            if isSelecting {
                                isSelecting = false
                                selectedFiles.removeAll()
                            } else {
                                isSelecting = true
                            }
                        }
                    } label: {
                        Image(
                            systemName: isSelecting
                                ? "xmark.circle" : "checkmark.circle"
                        )
                        .font(.title3.bold())
                        .foregroundColor(isSelecting ? .red : .primary)
                        .padding(8)
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                    .opacity(files.isEmpty && !isSelecting ? 0.5 : 1)
                    .disabled(files.isEmpty && !isSelecting)
                }
                .padding(.horizontal)

                if isSelecting {
                    HStack {
                        Text("\(selectedFiles.count) selected")
                            .foregroundColor(.secondary)

                        Spacer()

                        HStack(spacing: 15) {
                            Button {
                                for url in selectedFiles {
                                    FavoritesManager.shared.toggleStar(for: url)
                                }
                                exitSelectionMode()
                            } label: {
                                Image(systemName: "star")
                                    .font(.title2)
                            }
                            .disabled(selectedFiles.isEmpty)

                            Button(role: .destructive) {
                                showingBatchDeleteAlert = true
                            } label: {
                                Image(systemName: "trash")
                                    .font(.title2)
                            }
                            .disabled(selectedFiles.isEmpty)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 5)
                }

                List {
                    starredFilesSection
                    
                    taggedFilesSection
                    
                    ForEach(visibleGroups, id: \.self) { fileGroup in
                        if isExpanded(.fileGroup(fileGroup)) {
                            let groupFiles =
                                remainingFiles
                                .filter {
                                    self.group(
                                        for: $0.pathExtension.lowercased()
                                    ) == fileGroup
                                }
                                .filter { _ in
                                    selectedFilter == .all
                                        || selectedFilter.group == fileGroup
                                }

                            if !groupFiles.isEmpty {
                                Section {
                                    ForEach(groupFiles, id: \.self) { url in
                                        fileRow(for: url)
                                    }
                                } header: {
                                    Text(fileGroup.rawValue)
                                        .font(.headline)
                                }
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.3), value: currentURL)
            }
            .sheet(isPresented: $showingSavedChats) {
                StudyTabsView()
                    .environmentObject(convo)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .onAppear {
                loadExpandedState()
            }
        }
    }
    
    @ViewBuilder
    private var starredFilesSection: some View {
        let starred = files.filter { FavoritesManager.shared.isStarred($0) }
        if !starred.isEmpty {
            Section {
                ForEach(starred, id: \.self) { url in
                    fileRow(for: url)
                }
            } header: {
                HStack {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                    Text("Favorites")
                        .font(.headline)
                }
            }
        }
    }
    
    @ViewBuilder
    private var taggedFilesSection: some View {
        let allTags = TagsManager.shared.allTags
        ForEach(allTags, id: \.id) { tag in
            let taggedFiles = files.filter { url in
                TagsManager.shared.contains(tag, for: url)
            }
            if !taggedFiles.isEmpty && isExpanded(.tag(tag)) {
                Section {
                    ForEach(taggedFiles, id: \.self) { url in
                        fileRow(for: url)
                    }
                } header: {
                    HStack {
                        Circle()
                            .fill(tag.color.color)
                            .frame(width: 10, height: 10)
                        Text(tag.name)
                            .font(.headline)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func groupChip(
        title: String,
        icon: String,
        color: Color,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(
                title: { Text(title).font(.subheadline.bold()) },
                icon: { Image(systemName: icon) }
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(
                        isActive
                            ? color.opacity(0.22)
                            : Color(UIColor.tertiarySystemFill)
                    )
            )
            .foregroundColor(isActive ? color : .primary)
            .overlay(
                Capsule()
                    .stroke(isActive ? color : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var groupChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                let starredCount = files.filter { FavoritesManager.shared.isStarred($0) }.count
                if starredCount > 0 {
                    groupChip(
                        title: "Starred(\(starredCount))",
                        icon: "star.fill",
                        color: .yellow,
                        isActive: isExpanded(.starred)
                    ) {
                        toggleExpanded(.starred)
                    }
                }
                
                ForEach(TagsManager.shared.allTags, id: \.id) { tag in
                    let taggedCount = files.filter { TagsManager.shared.contains(tag, for: $0) }.count
                    if taggedCount > 0 {
                        groupChip(
                            title: "\(tag.name)(\(taggedCount))",
                            icon: "tag.fill",
                            color: tag.color.color,
                            isActive: isExpanded(.tag(tag))
                        ) {
                            toggleExpanded(.tag(tag))
                        }
                    }
                }
                
                ForEach(visibleGroups, id: \.self) { fileGroup in
                    let count = countForGroup(fileGroup)
                    if count > 0 {
                        groupChip(
                            title: "\(fileGroup.rawValue)(\(count))",
                            icon: iconForGroup(fileGroup),
                            color: colorForGroup(fileGroup),
                            isActive: isExpanded(.fileGroup(fileGroup))
                        ) {
                            toggleExpanded(.fileGroup(fileGroup))
                        }
                    }
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal,5)
        }
    }

    private func toggleSelection(_ url: URL) {
        if selectedFiles.contains(url) {
            selectedFiles.remove(url)
        } else {
            selectedFiles.insert(url)
        }

        if selectedFiles.isEmpty {
            withAnimation {
                isSelecting = false
            }
        }
    }

    private func exitSelectionMode() {
        withAnimation {
            isSelecting = false
            selectedFiles.removeAll()
        }
    }

    @MainActor
    private func batchDelete(_ urls: Set<URL>) async {
        print("Deleting \(urls.count) files...")
        for url in urls {
            await onDelete(url)
        }
        exitSelectionMode()
        onRefreshFiles()
    }

    private func info(for url: URL) -> FileInfo? {
        do {
            let attrs = try FileManager.default.attributesOfItem(
                atPath: url.path
            )
            let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            let mod = (attrs[.modificationDate] as? Date) ?? .distantPast
            return FileInfo(
                url: url,
                size: size,
                modified: mod,
                ext: url.pathExtension.lowercased()
            )
        } catch { return nil }
    }

    private func byteCount(_ bytes: Int64) -> String {
        let fmt = ByteCountFormatter()
        fmt.allowedUnits = [.useKB, .useMB]
        fmt.countStyle = .file
        return fmt.string(fromByteCount: bytes)
    }

    private func friendlyDate(_ date: Date) -> String {
        let rel = RelativeDateTimeFormatter()
        rel.unitsStyle = .short
        let cal = Calendar.current
        if cal.isDateInToday(date) || cal.isDateInYesterday(date) {
            return rel.localizedString(for: date, relativeTo: Date())
        }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    private func iconName(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "md": return "doc.text"
        case "txt": return "doc.plaintext"
        case "pdf": return "doc.richtext"
        case "docx": return "doc"
        case "ppt", "pptx": return "doc.viewfinder"
        default: return "doc"
        }
    }

    @ViewBuilder
    private func fileRow(for url: URL) -> some View {
        let info =
            self.info(for: url)
            ?? FileInfo(
                url: url,
                size: 0,
                modified: .distantPast,
                ext: url.pathExtension.lowercased()
            )

        let isSelected = selectedFiles.contains(url)

        HStack(spacing: 12) {
            if isSelecting {
                Image(
                    systemName: isSelected ? "checkmark.circle.fill" : "circle"
                )
                .foregroundColor(isSelected ? .blue : .secondary)
                .font(.title2)
                .animation(.easeInOut(duration: 0.15), value: isSelected)
            } else {
                Image(systemName: iconName(for: url))
                    .foregroundStyle(.secondary)
            }

            Button {
                if isSelecting {
                    toggleSelection(url)
                } else {
                    Task { await onOpen(url) }
                }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(url.lastPathComponent)
                            .font(.subheadline)
                            .lineLimit(2)
                            .foregroundColor(
                                isSelecting
                                    ? (isSelected ? .blue : .primary) : .primary
                            )
                        
                        if FavoritesManager.shared.isStarred(url) {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundColor(.yellow)
                        }
                    }
                    
                    HStack(spacing: 4) {
                        Text(
                            "\(byteCount(info.size)) • \(friendlyDate(info.modified))"
                        )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        
                        let fileTags = TagsManager.shared.tags(for: url)
                        if !fileTags.isEmpty {
                            Spacer()
                            HStack(spacing: 2) {
                                ForEach(fileTags.prefix(3), id: \.id) { tag in
                                    Circle()
                                        .fill(tag.color.color)
                                        .frame(width: 6, height: 6)
                                }
                                if fileTags.count > 3 {
                                    Text("+\(fileTags.count - 3)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .contentShape(Rectangle())

            Spacer()

            if !isSelecting {
                Menu {
                    Button {
                        Task { await onOpen(url) }
                    } label: {
                        Label("Open", systemImage: "doc.text")
                    }

                    Button {
                        share(url: url)
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    
                    Divider()
                    
                    Menu {
                        ForEach(TagsManager.shared.allTags, id: \.id) { tag in
                            Button {
                                TagsManager.shared.toggleTag(tag, for: url)
                            } label: {
                                HStack {
                                    Circle()
                                        .fill(tag.color.color)
                                        .frame(width: 8, height: 8)
                                    Text(tag.name)
                                    if TagsManager.shared.contains(tag, for: url) {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Label("Tags", systemImage: "tag")
                    }
                    
                    Divider()

                    Button(role: .destructive) {
                        pendingDeleteURL = url
                        showingDeleteAlert = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .imageScale(.large)
                }
            }
        }
        .onLongPressGesture {
            guard !isSelecting else { return }
            withAnimation {
                isSelecting = true
                selectedFiles.insert(url)
            }
        }
        .background(
            isSelecting && isSelected
                ? Color.blue.opacity(0.2)
                : Color.clear
        )
        .cornerRadius(12)
        .animation(.easeInOut(duration: 0.2), value: isSelecting)
        .animation(.easeInOut(duration: 0.2), value: isSelected)

        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if !isSelecting {
                Button {
                    share(url: url)
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .tint(.indigo)

                Button {
                    FavoritesManager.shared.toggleStar(for: url)
                } label: {
                    Label(
                        FavoritesManager.shared.isStarred(url) ? "Unstar" : "Star",
                        systemImage: FavoritesManager.shared.isStarred(url)
                            ? "star.slash" : "star"
                    )
                }
                .tint(.yellow)
            }
        }
    }

    private func share(url: URL) {
        ShareSheet.present(items: [url])
    }
}
