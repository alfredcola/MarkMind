import SwiftUI
import Combine

struct SelectionChatPresentationItem: Identifiable {
    let id = UUID()
    let selectedText: String
    let docURL: URL
    let docText: String
    let savedChat: ConversationStore.SavedSelectionChat?
    let restoredDocumentChat: ConversationStore.SavedDocumentChat?
}

struct SelectionChatView: View {
    let selectedText: String
    let docURL: URL
    let docText: String
    
    let savedChat: ConversationStore.SavedSelectionChat?
    
    // For restored full-document chats
    let restoredDocumentChat: ConversationStore.SavedDocumentChat?
    
    @EnvironmentObject var convo: ConversationStore
    @Environment(\.dismiss) private var dismiss
    
    static let sharedSelectionChatURL = URL(string: "temp://selection-chat/shared")!
    private let selectionChatURL = SelectionChatView.sharedSelectionChatURL
    
    @State private var input: String = ""
    @State private var sending: Bool = false
    @State private var errorMessage: String?
    @State private var hasSentInitial = false
    
    @State private var showingSaveAlert = false
    @State private var saveTitle: String = ""
    
    @AppStorage("ai_reply_language") private var aiReplyLanguageRaw: String = AIReplyLanguage.english.rawValue
    
    private var aiReplyLanguage: AIReplyLanguage {
        AIReplyLanguage(rawValue: aiReplyLanguageRaw) ?? .english
    }
    
    private var languageInstruction: String {
        aiReplyLanguage == .traditionalChinese ? "以正體中文回覆。" : "Respond in English."
    }
    
    private var messages: [ChatMessage] {
        convo.messages(for: selectionChatURL)
    }
    
    private var trimmedSelectedText: String {
        selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private var hasMeaningfulSelection: Bool {
        !trimmedSelectedText.isEmpty || restoredDocumentChat != nil
    }
    
    private var selectedTextPreview: String {
        let preview = trimmedSelectedText
        if preview.isEmpty { return "Chat" }
        return String(preview.prefix(60)) + (preview.count > 60 ? "…" : "")
    }
    
    private var displayTitle: String {
        if let docChat = restoredDocumentChat {
            return docChat.documentName
        }
        return selectedTextPreview
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            if messages.isEmpty && !hasMeaningfulSelection {
                                Text("No valid text selected.")
                                    .foregroundColor(.secondary)
                                    .padding()
                            } else {
                                ForEach(messages, id: \.id) { message in
                                    MessageBubble(message: message)
                                        .id(message.id)
                                        .padding(.horizontal, 4)
                                }
                            }
                        }
                        .padding(.top, 2)
                    }
                    .onAppear {
                        scrollToBottom(proxy)
                    }
                    .onChange(of: messages.count) {
                        scrollToBottom(proxy)
                    }
                }
                
                if messages.isEmpty && hasMeaningfulSelection {
                    Divider()
                    inputArea
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text(displayTitle)
                            .font(.subheadline)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                        
                        if restoredDocumentChat != nil {
                            Text("Restored Full Document Chat")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        convo.clear(for: selectionChatURL)
                        dismiss()
                    }
                }
                
                if !messages.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            let time = Date().formatted(date: .omitted, time: .shortened)
                            saveTitle = "\(displayTitle) – \(time)"
                            showingSaveAlert = true
                        }
                    }
                }
            }
            .alert("Save Chat Session", isPresented: $showingSaveAlert) {
                TextField("Title", text: $saveTitle)
                    .autocapitalization(.words)
                Button("Save") {
                    let trimmed = saveTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    let _ = convo.saveChat(for: SelectionChatView.sharedSelectionChatURL, title: trimmed)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Give this chat session a name so you can open it later.")
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .task {
                await handleInitialLoad()
            }
        }
    }
    
    private var inputArea: some View {
        HStack(spacing: 12) {
            TextField("Ask a follow-up...", text: $input, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...6)
                .disabled(sending || !hasMeaningfulSelection)
            
            Button {
                Task { await send() }
            } label: {
                Image(systemName: sending ? "ellipsis" : "paperplane.fill")
                    .font(.title3)
                    .foregroundStyle(sending ? .orange : .blue)
                    .symbolEffect(.pulse, options: .repeating, isActive: sending)
            }
            .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
        }
        .padding()
    }
    
    // MARK: - Main Initialization Logic with Detailed Logging
    
    @MainActor
    private func handleInitialLoad() async {
        // 1. No meaningful content → dismiss safely
        guard hasMeaningfulSelection else {
            try? await Task.sleep(for: .milliseconds(300))
            dismiss()
            return
        }
        
        // 2. Restoring a saved selection chat
        if let savedChat = savedChat {
            convo.loadSavedSelectionChat(savedChat)
            return
        }
        
        // 3. Restoring a full document chat into selection context
        if let docChat = restoredDocumentChat {
            convo.clear(for: selectionChatURL)
            for msg in docChat.messages {
                convo.append(msg, to: selectionChatURL)
            }
            return
        }
        
        // 4. Fresh new selection
        if convo.isRestoringSavedChat {
            return
        }
        convo.clear(for: selectionChatURL)
        
        guard !hasSentInitial else {
            return
        }
        
        hasSentInitial = true
        
        try? await Task.sleep(for: .milliseconds(400))
        
        await sendInitialPrompt()
    }
    
    @MainActor
    private func sendInitialPrompt() async {
        let instruction = restoredDocumentChat != nil
            ? "Continue this full document analysis chat."
            : "Explain or analyze the selected text in clear, structured, and concise detail."
        
        await callAI(with: instruction)
    }
    
    @MainActor
    private func send() async {
        let content = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
                
        input = ""
        let userMsg = ChatMessage(role: .user, content: content)
        convo.append(userMsg, to: selectionChatURL)
        convo.objectWillChange.send()
        
        await callAI(with: content)
    }
    
    @MainActor
    private func callAI(with userContent: String) async {
        sending = true
        
        defer {
            sending = false
        }
        
        do {
            let apiKey = ProcessInfo.processInfo.environment["MINIMAX_API_KEY"]
                ?? (Bundle.main.object(forInfoDictionaryKey: "MiniMaxAPIKey") as? String)
                ?? ""
            guard !apiKey.isEmpty else {
                errorMessage = "Missing MiniMax API key."
                return
            }
            
            let actualText = restoredDocumentChat != nil ? "[Full document content not reloaded]" : trimmedSelectedText
            let contextText = restoredDocumentChat != nil ? "[Full document]" : docText
            let isFullDoc = restoredDocumentChat != nil
            
            let systemPrompt = PromptBuilder.buildSelectionChatPrompt(
                selectedText: actualText,
                fullDocText: contextText,
                isFullDoc: isFullDoc
            )
            
            let apiMessages: [ChatMessage] = [
                .init(role: .system, content: systemPrompt),
                .init(role: .user, content: userContent)
            ]
            
            
            let reply = try await MiniMaxService.chatWithAutoContinue(
                apiKey: apiKey,
                messages: apiMessages,
                temperature: 0.1,
                maxTokens: 8000
            )
            
            var finalReply: String
            if aiReplyLanguage == .traditionalChinese {
                let hasChinese = reply.containsChinese()
                let chineseRatio = Double(reply.unicodeScalars.filter { $0.value >= 0x4E00 && $0.value <= 0x9FFF }.count) / Double(max(reply.count, 1))
                
                if !hasChinese || chineseRatio < 0.3 {
                    finalReply = "（以下以正體中文回覆）\n\(reply)"
                } else {
                    finalReply = reply
                }
            } else {
                finalReply = reply
            }
            
            
            try? await Task.sleep(nanoseconds: 100_000_000)
            
            let assistantMsg = ChatMessage(role: .assistant, content: finalReply)
            convo.append(assistantMsg, to: selectionChatURL)
            convo.objectWillChange.send()
            
        } catch {
            errorMessage = "AI error: \(error.localizedDescription)"
            convo.objectWillChange.send()
        }
    }
    
    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if let last = messages.last {
            withAnimation {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
}

// MARK: - Helper Extension for Chinese Detection
extension String {
    func containsChinese() -> Bool {
        return self.range(of: #"[\u4E00-\u9FFF]"#, options: .regularExpression) != nil
    }
}

struct SavedChatsList: View {
    @EnvironmentObject var convo: ConversationStore
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - Filter & Sort State
    @State private var searchText: String = ""
    @State private var sortOption: SortOption = .dateNewest
    @State private var showAdvancedFilters = false
    
    enum SortOption: String, CaseIterable, Identifiable {
        case dateNewest = "Newest First"
        case dateOldest = "Oldest First"
        case titleAZ = "Title A–Z"
        case titleZA = "Title Z–A"
        case messageCount = "Most Messages"
        
        var id: Self { self }
    }
    
    // MARK: - Loading State for Sheet
    @State private var showingChat = false
    @State private var loadedSelectedText = ""
    @State private var loadedDocText = ""
    @State private var loadedDocURL = URL(fileURLWithPath: "/")
    @State private var loadedSavedSelectionChat: ConversationStore.SavedSelectionChat?
    @State private var loadedSavedDocumentChat: ConversationStore.SavedDocumentChat?
    
    // MARK: - Data Computation
    
    private var allSavedChats: [any SavedChatProtocol] {
        let selectionChats = convo.savedSelectionChats.map { $0 as any SavedChatProtocol }
        let documentChats = convo.savedDocumentChats.map { $0 as any SavedChatProtocol }
        return selectionChats + documentChats
    }
    
    private var filteredAndSortedChats: [any SavedChatProtocol] {
        var chats = allSavedChats
        
        // Search filter
        if !searchText.isEmpty {
            let lowercasedQuery = searchText.lowercased()
            chats = chats.filter { chat in
                chat.title.lowercased().contains(lowercasedQuery) ||
                (chat.subtitle?.lowercased().contains(lowercasedQuery) ?? false) ||
                (chat.previewText?.lowercased().contains(lowercasedQuery) ?? false)
            }
        }
        
        // Sorting
        switch sortOption {
        case .dateNewest:
            chats.sort { $0.date > $1.date }
        case .dateOldest:
            chats.sort { $0.date < $1.date }
        case .titleAZ:
            chats.sort { $0.title.lowercased() < $1.title.lowercased() }
        case .titleZA:
            chats.sort { $0.title.lowercased() > $1.title.lowercased() }
        case .messageCount:
            chats.sort { $0.messageCount > $1.messageCount }
        }
        
        return chats
    }
    
    private var hasActiveSearch: Bool {
        !searchText.isEmpty
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            Group {
                if filteredAndSortedChats.isEmpty {
                    if allSavedChats.isEmpty {
                        emptyStateView
                    } else {
                        searchNoResultsView
                    }
                } else {
                    List {
                        ForEach(filteredAndSortedChats, id: \.id) { chat in
                            Button {
                                openSavedChat(chat)
                            } label: {
                                chatRow(for: chat)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    withAnimation {
                                        deleteChat(chat)
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Saved Chats")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search chats...")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        // Sort Section
                        Section("Sort By") {
                            Picker("Sort", selection: $sortOption) {
                                ForEach(SortOption.allCases) { option in
                                    Label(option.rawValue, systemImage: sortIcon(for: option))
                                        .tag(option)
                                }
                            }
                            .pickerStyle(.inline)
                        }
                        
                    } label: {
                        Label("Sort", systemImage: "line.3.horizontal.decrease.circle")
                    }
                    .disabled(filteredAndSortedChats.isEmpty)
                }
            }
            .animation(.default, value: filteredAndSortedChats.count)
            .sheet(isPresented: $showingChat) {
                SelectionChatView(
                    selectedText: loadedSelectedText,
                    docURL: loadedDocURL,
                    docText: loadedDocText,
                    savedChat: loadedSavedSelectionChat,
                    restoredDocumentChat: loadedSavedDocumentChat
                )
                .environmentObject(convo)
                .interactiveDismissDisabled()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
    }
    
    // MARK: - Subviews & Helpers
    
    private var emptyStateView: some View {
        ContentUnavailableView(
            "No saved chats",
            systemImage: "tray",
            description: Text("Saved chats from document analysis or text selections will appear here.")
        )
    }
    
    private var searchNoResultsView: some View {
        ContentUnavailableView(
            "No results",
            systemImage: "magnifyingglass",
            description: Text("No saved chats match “\(searchText)”")
        )
    }
    
    private func chatRow(for chat: any SavedChatProtocol) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: chatIcon(for: chat))
                        .foregroundStyle(.tint)
                    
                    Text(chat.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(2)
                }
                
                if let subtitle = chat.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                
                if let preview = chat.previewText, !preview.isEmpty {
                    Text(preview)
                        .font(.caption)
                        .foregroundStyle(.secondary.opacity(0.9))
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
                
                HStack(spacing: 12) {
                    Label("\(chat.messageCount)", systemImage: "message")
                    Text(chat.date, style: .relative)
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                .foregroundStyle(.secondary.opacity(0.8))
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.quaternary)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
    
    private func sortIcon(for option: SortOption) -> String {
        switch option {
        case .dateNewest, .dateOldest: return "calendar"
        case .titleAZ, .titleZA: return "textformat.alt"
        case .messageCount: return "message.fill"
        }
    }
    
    private func chatIcon(for chat: any SavedChatProtocol) -> String {
        chat is ConversationStore.SavedSelectionChat ? "text.alignleft" : "doc.text"
    }
    
    private func openSavedChat(_ chat: any SavedChatProtocol) {
        convo.clear(for: SelectionChatView.sharedSelectionChatURL)
        
        if let selectionChat = chat as? ConversationStore.SavedSelectionChat {
            convo.loadSavedSelectionChat(selectionChat)
            
            loadedSelectedText = extractSelectedText(from: selectionChat) ?? selectionChat.title
            loadedDocText = ""
            loadedDocURL = URL(fileURLWithPath: "/")
            loadedSavedSelectionChat = selectionChat
            loadedSavedDocumentChat = nil
            
        } else if let documentChat = chat as? ConversationStore.SavedDocumentChat {
            for msg in documentChat.messages {
                convo.append(msg, to: SelectionChatView.sharedSelectionChatURL)
            }
            
            loadedSelectedText = ""
            loadedDocText = ""
            loadedDocURL = URL(fileURLWithPath: "/")
            loadedSavedSelectionChat = nil
            loadedSavedDocumentChat = documentChat
        }
        
        showingChat = true
    }
    
    private func deleteChat(_ chat: any SavedChatProtocol) {
        if let selectionChat = chat as? ConversationStore.SavedSelectionChat {
            convo.deleteSavedSelectionChat(selectionChat)
        } else if let documentChat = chat as? ConversationStore.SavedDocumentChat {
            convo.deleteSavedDocumentChat(documentChat)
        }
    }
    
    private func extractSelectedText(from chat: ConversationStore.SavedSelectionChat) -> String? {
        return chat.messages.first(where: { $0.role == .assistant })?.content
            .components(separatedBy: "=== SELECTED TEXT ===")
            .last?
            .components(separatedBy: "=== END OF SELECTED TEXT ===")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Protocol (unchanged)
protocol SavedChatProtocol: Identifiable {
    var id: UUID { get }
    var title: String { get }
    var date: Date { get }
    var messages: [ChatMessage] { get }
    
    var subtitle: String? { get }
    var previewText: String? { get }
    var messageCount: Int { get }
}

extension ConversationStore.SavedSelectionChat: SavedChatProtocol {
    var subtitle: String? { "Text selection" }
    var previewText: String? {
        messages.first?.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    var messageCount: Int { messages.count }
}

extension ConversationStore.SavedDocumentChat: SavedChatProtocol {
    var subtitle: String? { documentName }
    var previewText: String? {
        messages.first(where: { $0.role == .assistant })?.content
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    var messageCount: Int { messages.count }
}
struct StudyTabsView: View {
    @EnvironmentObject var convo: ConversationStore  // Needed for SavedChatsList
    
    var body: some View {
        TabView {
            // Tab 1: Study History for the current document
            MCReviewHistoryView(currentDocURL: nil)
                .tabItem {
                    Label("History", systemImage: "clock.fill")
                }
            
            // Tab 2: All Saved Chats (both selection and document chats)
            SavedChatsList()
                .tabItem {
                    Label("Saved Chats", systemImage: "tray.full.fill")
                }
                .environmentObject(convo)  // Ensure the environment object is available
        }
        .navigationTitle("Study")
        .navigationBarTitleDisplayMode(.inline)
    }
}
