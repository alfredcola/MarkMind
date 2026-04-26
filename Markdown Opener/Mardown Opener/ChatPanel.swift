//
//  ChatPanel.swift
//  Markdown Opener
//
//  Created by alfred chen on 10/11/2025.
//

import Foundation
import PDFKit
import QuickLook
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WebKit

/// The language in which the AI should reply (and UI should be shown)
enum AIReplyLanguage: String, Codable, CaseIterable, Identifiable {
    case english = "English"
    case traditionalChinese = "正體中文"

    var id: String { rawValue }

    /// Returns the **locale identifier** used by the system and the AI prompt
    var localeIdentifier: String {
        switch self {
        case .english:
            return "en"
        case .traditionalChinese:
            return "zh-Hant"
        }
    }

    /// Human-readable name (already localized in `Localizable.xcstrings`)
    var displayName: String {
        NSLocalizedString(self.rawValue, comment: "")
    }
}

// MARK: - Chat Panel
struct ChatPanel: View {
    @EnvironmentObject var convoAbbb: ConversationStore
    private let documentStore = DocumentStore.shared
    @ObservedObject private var rewardedAdManager = RewardedAdManager.shared


    let docURL: URL
    let docText: String

    @State private var showShortcuts = true
    @State private var shortcutAutoSend = true
    @State private var isFullScreen = false
    @State private var input = ""
    @State private var sending = false
    @State private var errorMessage: String?
    @State private var didAutoSend = false
    @State private var selectedFiles: [(url: URL, content: String)] = []
    @State private var showFilePicker = false

    var seedPrompt: String = ""
    var autoSend: Bool = false

    @AppStorage("ai_reply_language") private var aiReplyLanguageRaw: String =
        AIReplyLanguage.english.rawValue
    private var aiReplyLanguage: AIReplyLanguage {
        AIReplyLanguage(rawValue: aiReplyLanguageRaw) ?? .english
    }

    private var languageSystemInstruction: String {
        switch aiReplyLanguage {
        case .english: return "Respond in English."
        case .traditionalChinese: return "以正體中文回覆。"
        }
    }

    @State private var showingSaveAlert = false
    @State private var saveTitle: String = ""

    private var shortcutItems: [ShortcutItem] {
        let summarizePrompt =
            seedPrompt.isEmpty
            ? Localization.locWithUserPreference(
                """
                Summarize the entire document in a clear, structured way for efficient review and revision. 
                Use appropriate Markdown headings (##, ###), bullet points, and numbered lists. 
                Keep it concise but comprehensive, highlighting the main ideas, structure, and conclusions. 
                Do not add unnecessary introductions or disclaimers.
                """,
                """
                請以正體中文完整摘要此文件內容，便於快速複習與溫習。
                使用適當的 Markdown 標題（##、###）、項目符號與編號清單，結構清晰。
                內容需精簡但全面，突顯主要論點、文件結構與結論。
                請勿加入不必要的開場白或免責聲明。
                """
            )
            : seedPrompt

        return [
            // Primary
            ShortcutItem(
                title: Localization.locWithUserPreference("Summarize", "摘要"),
                prompt: summarizePrompt,
                isPrimary: true
            ),

            ShortcutItem(
                title: Localization.locWithUserPreference("Study", "溫習"),
                prompt: Localization.locWithUserPreference(
                    """
                    Please create concise review notes for the course "[Course Code] [Course Name]".

                    Use Markdown format, title: # [Course Code] [Course Name] Course Key Points (Review Version).

                    Organize by 6-12 main topics (adjust as needed). Use ## Topic Name for each, include (skip if not applicable):

                    ### Core Concept Explanation
                    - Define, importance, scenarios, applications.
                    - Stress principles/architecture (🔴 for high-frequency exam points).

                    ### Key Syntax/Code Examples
                    - List syntax, show annotated examples in ``` blocks (focus on logic).

                    ### Key Differences
                    - Compare concepts with bullets or tables.

                    ### Table Summary (if applicable)
                    - Useful tables (e.g., status codes, complexity).

                    ### Notes & Common Mistakes
                    - Pitfalls, debugging (⚠️ for common exam errors).

                    Style: concise, clear, easy to review. **Bold** keywords, 🔴 exam hotspots. Add text-based diagrams if useful. End sections with quick summary/mnemonic if possible.

                    End with ## Exam Tips:
                    - ### Theory: concepts, comparisons, scenarios, security/performance.
                    - ### Practice: debugging, optimization, testing, principles.
                    - ### Common Question Types: explanation, comparison, application, debugging, coding.
                    - ### Preparation: prioritize understanding, practice code/projects, review mistakes, suggested order, past papers.

                    Keep concise for quick review. Ask for more course details if needed.
                    """,
                    """
                    請幫我為「[課程代碼] [課程名稱]」製作一份完整的複習筆記。

                    內容全部用Markdown 格式，標題為 # [課程代碼] [課程名稱] 課程重點詳解。

                    按課程主要主題組織重點（6-12 個主題，可自行調整），涵蓋核心章節。每主題用 ## 主題名稱，包含以下子區塊（不適用可省略）：

                    ### 核心概念解釋
                    - 說明定義、重要性、適用場景與應用。
                    - 強調原理與架構（🔴 標記常考點）。

                    ### 重要指令/語法/程式碼範例
                    - 列出關鍵語法，用 ``` 顯示範例程式碼並註解重點（強調邏輯而非死記）。

                    ### 關鍵差異比較
                    - 用 bullet points 或表格比較相關概念。

                    ### 表格案例摘要（若適用）
                    - 提供實用表格（如狀態碼、演算法比較等）。

                    ### 注意事項與常見錯誤
                    - 列出易錯點、陷阱、除錯技巧（⚠️ 標記常見考試失分）。

                    整體風格：簡潔、重點突出、易記易複習。用 **粗體** 標關鍵字、🔴 標高頻考點。若適用，加文字流程圖/架構圖。每節可結尾加考點小結或記憶口訣。

                    最後加 ## 考試重點提醒，包含：
                    - ### 理論部分：重要概念、比較、場景、安全/效能。
                    - ### 實作部分：除錯、優化、測試、原則。
                    - ### 常見問題類型：概念解釋、比較、應用、除錯、填空題。
                    - ### 準備建議：理解重於背誦、多練習、整理錯題、建議複習順序、多看歷年題。

                    筆記需濃縮適合快速複習。若課程資訊不足，請先詢問補充細節。
                    """
                ),
                isPrimary: false
            ),

            // Core analysis
            ShortcutItem(
                title: Localization.locWithUserPreference("Key points", "重點"),
                prompt: Localization.locWithUserPreference(
                    """
                    Extract and list the most important key points, takeaways, and conclusions from the document. 
                    Present them as concise bullet points under clear thematic headings if appropriate. 
                    Prioritize substance over minor details.
                    """,
                    """
                    請從文件中萃取最重要的重點、關鍵結論與收穫。
                    以簡潔的條列式呈現，如有需要可使用清晰的主題標題分組。
                    優先呈現實質內容，避免次要細節。
                    """
                ),
                isPrimary: false
            ),
            ShortcutItem(
                title: Localization.locWithUserPreference("Action items", "行動項目"),
                prompt: Localization.locWithUserPreference(
                    """
                    Identify all actionable tasks, recommendations, or to-dos mentioned in the document. 
                    For each item, provide:
                    • The task description
                    • Responsible person/role (if mentioned)
                    • Deadline or priority (if mentioned)
                    • Brief context
                    Use a clear numbered or bulleted list.
                    """,
                    """
                    請從文件中找出所有可執行的任務、建議或待辦事項。
                    對每項行動項目，請提供：
                    • 任務描述
                    • 負責人或角色（如有提及）
                    • 期限或優先級（如有提及）
                    • 簡短背景說明
                    以清晰的編號或條列方式呈現。
                    """
                ),
                isPrimary: false
            ),

            ShortcutItem(
                title: Localization.locWithUserPreference("Outline", "大綱"),
                prompt: Localization.locWithUserPreference(
                    """
                    Create a detailed hierarchical outline of the entire document. 
                    Use Markdown headings and nested bullet points to accurately reflect the document's structure and logical flow. 
                    Include main sections, subsections, and key content under each.
                    """,
                    """
                    請為整份文件製作詳細的層級式大綱。
                    使用 Markdown 標題與巢狀項目符號，精準反映文件的結構與邏輯流程。
                    包含主要章節、子章節，以及各部分下的關鍵內容。
                    """
                ),
                isPrimary: false
            ),
            ShortcutItem(
                title: Localization.locWithUserPreference("Mind Map", "心智圖"),
                prompt: Localization.locWithUserPreference(
                    """
                    Generate a text-based mind map of the document's core concepts and their relationships.
                    Use Markdown nested bullets to show hierarchy and connections.
                    Start with the central theme, then branch into main topics and subtopics.
                    """,
                    """
                    請以文字形式製作此文件的核心概念心智圖，並顯示概念間的關係。
                    使用 Markdown 巢狀條列呈現層級與連結。
                    從中心主題開始，分支到主要議題與子議題。
                    """
                ),
                isPrimary: false
            ),

            ShortcutItem(
                title: Localization.locWithUserPreference("Definitions", "術語定義"),
                prompt: Localization.locWithUserPreference(
                    """
                    List all important terms, jargon, acronyms, or technical concepts appearing in the document. 
                    For each term, provide a concise, accurate definition in your own words based on the document's context. 
                    Present as a bullet list with the term in **bold**.
                    """,
                    """
                    請列出文件中出現的重要術語、專業名詞、縮寫或技術概念。
                    對每個術語，根據文件脈絡給出精準且簡潔的定義（用自己的話說明）。
                    以條列呈現，術語請使用**粗體**標示。
                    """
                ),
                isPrimary: false
            ),
            ShortcutItem(
                title: Localization.locWithUserPreference("Explain Simply", "簡化解釋"),
                prompt: Localization.locWithUserPreference(
                    """
                    Explain the main ideas and key concepts of this document as if to a beginner or non-expert.
                    Use simple language, avoid jargon (or explain it), and include analogies where helpful.
                    Structure with short paragraphs and bullet points.
                    """,
                    """
                    請用簡單易懂的語言，向初學者或非專業人士解釋此文件的主要概念與重點。
                    避免使用專業術語（如必須使用請解釋），可加入類比說明。
                    使用短段落與條列結構化呈現。
                    """
                ),
                isPrimary: false
            ),

            // Critical thinking
            ShortcutItem(
                title: Localization.locWithUserPreference("Critique", "評析"),
                prompt: Localization.locWithUserPreference(
                    """
                    Provide a balanced critique of the document: strengths, weaknesses, logical gaps, assumptions, and potential improvements.
                    Use constructive tone and organize under clear headings.
                    """,
                    """
                    請對此文件進行平衡的評析：優點、缺點、邏輯漏洞、假設前提，以及可能的改進建議。
                    使用建設性語氣，並以清晰標題分段組織。
                    """
                ),
                isPrimary: false
            ),

            // Questions & study
            ShortcutItem(
                title: Localization.locWithUserPreference("Study Questions", "學習問題"),
                prompt: Localization.locWithUserPreference(
                    """
                    Generate 8–12 thoughtful study or discussion questions based on the document content.
                    Include a mix of factual recall, comprehension, analysis, and application questions.
                    Number them clearly.
                    """,
                    """
                    請根據文件內容產生 8–12 個有深度的學習或討論問題。
                    包含事實回憶、理解、分析與應用等不同層次。
                    請清楚編號。
                    """
                ),
                isPrimary: false
            ),

            // Translation & comparison
            ShortcutItem(
                title: Localization.locWithUserPreference("Translate to EN", "翻譯成英文"),
                prompt: Localization.locWithUserPreference(
                    "Translate the entire document into natural, professional English. Preserve formatting and structure as much as possible using Markdown.",
                    "請將整份文件翻譯成自然、專業的英文。盡量保留原有的格式與結構，使用 Markdown 呈現。"
                ),
                isPrimary: false
            ),
            ShortcutItem(
                title: Localization.locWithUserPreference("Compare Versions", "版本比較"),
                prompt: Localization.locWithUserPreference(
                    """
                    This query is used when multiple files are selected.
                    Compare the selected documents: highlight key differences, similarities, changes in structure, content additions/removals, and tone shifts.
                    Use clear sections and bullet points.
                    """,
                    """
                    （當選擇多個檔案時使用）
                    比較選定的文件：突顯主要差異、相似處、結構變化、內容增刪，以及語氣轉變。
                    使用清晰分段與條列呈現。
                    """
                ),
                isPrimary: false
            ),

            // Quick facts
            ShortcutItem(
                title: Localization.locWithUserPreference("Quick Facts", "快速事實"),
                prompt: Localization.locWithUserPreference(
                    """
                    Extract key factual information such as names, dates, numbers, locations, statistics, and references.
                    Present in a clean bullet list or table format.
                    """,
                    """
                    請萃取關鍵事實資訊，如人名、日期、數字、地點、統計數據與參考資料。
                    以乾淨的條列或表格形式呈現。
                    """
                ),
                isPrimary: false
            ),
        ]
    }

    @State private var showSidebar = false

    var body: some View {
        ZStack(alignment: .leading) {
            mainChatView
                .background(Color(UIColor.systemBackground))
                .onTapGesture { dismissKeyboard() }
                .accessibilityAction(named: Localization.locWithUserPreference("Toggle full screen", "切換全螢幕"))
            {
                withAnimation {
                    isFullScreen.toggle()
                    if isFullScreen { dismissKeyboard() }
                }
            }
                .alert(isPresented: .constant(errorMessage != nil)) {
                    Alert(
                        title: Text(Localization.locWithUserPreference("Error", "錯誤")),
                        message: Text(errorMessage ?? ""),
                        dismissButton: .default(Text("OK")) {
                            errorMessage = nil
                        }
                    )
                }
                .alert("Save Chat Session", isPresented: $showingSaveAlert) {
                    TextField("Title", text: $saveTitle)
                        .autocapitalization(.words)
                    Button("Save") {
                        let trimmed = saveTitle.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                        guard !trimmed.isEmpty else { return }
                        let _ = convoAbbb.saveDocumentChat(
                            for: docURL,
                            title: trimmed
                        )
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text(
                        "Give this chat session a name so you can open it later."
                    )
                }

            sidebarView

            if showSidebar {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture {
                        withAnimation(.spring()) {
                            showSidebar = false
                        }
                    }
                    .zIndex(0.5)
            }
        }
        .animation(.spring(), value: showSidebar)
        .onChange(of: sending) { _, newValue in
            UIApplication.shared.isIdleTimerDisabled = newValue
        }
    }

    private var mainChatView: some View {
        VStack(spacing: 0) {
            if !isFullScreen {
                headerBar
                Divider()
            }

            chatMessagesList

            if !isFullScreen {
                selectedFilesDisplay
//                shortcutsBar
                inputBar
            }
        }
    }

    private var headerBar: some View {
        HStack(spacing: 12) {
            Button(action: {
                withAnimation(.spring()) {
                    showSidebar.toggle()
                }
            }) {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.primary)
                    .frame(width: 36, height: 36)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(Localization.locWithUserPreference("AI Assistant", "AI 助手"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                coinsBadge

                if !convoAbbb.messages(for: docURL).isEmpty {
                    Button {
                        let defaultTitle = docURL.deletingPathExtension()
                            .lastPathComponent
                        let dateStr = Date().formatted(
                            date: .omitted,
                            time: .shortened
                        )
                        saveTitle = "\(defaultTitle) – \(dateStr)"
                        showingSaveAlert = true
                    } label: {
                        Image(systemName: "bookmark")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.primary)
                            .frame(width: 36, height: 36)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color(.systemBackground))
    }

    private var coinsBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "bitcoinsign.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.yellow)
            Text("\(rewardedAdManager.coins)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color(.secondarySystemBackground))
                .overlay(
                    Capsule()
                        .stroke(Color.yellow.opacity(0.3), lineWidth: 1)
                )
        )
    }

    private var chatMessagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    let msgs = convoAbbb.messages(for: docURL)
                        .filter { msg in
                            !(msg.role == .user && msg.isShortcut)
                        }
                    
                    if msgs.isEmpty {
                        placeholderMessage
                    } else {
                        ForEach(msgs) { msg in
                            MessageBubble(message: msg)
                                .contextMenu { messageContextMenu(msg) }
                                .id(msg.id)
                                .transition(.opacity)
                        }
                    }
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .onAppear { scrollToBottom(proxy) }
            .onChange(of: convoAbbb.messages(for: docURL)) { _, _ in
                scrollToBottom(proxy)
            }
            .onTapGesture(count: 2) {
                withAnimation {
                    isFullScreen.toggle()
                    if isFullScreen { dismissKeyboard() }
                }
            }
        }
    }

    private var placeholderMessage: some View {
        VStack(spacing: 16) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 48))
                .foregroundStyle(.purple.opacity(0.6))

            VStack(spacing: 8) {
                Text(Localization.locWithUserPreference("Ready to help!", "準備好幫助你了！"))
                    .font(.headline)
                    .foregroundColor(.primary)

                Text(Localization.locWithUserPreference(
                    "Ask me anything about this document.\nTry a shortcut below to get started.",
                    "你可以問關於這個檔案的任何問題。\n嘗試下方的快捷鍵開始使用。"
                ))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            }

            if !shortcutItems.isEmpty {
                VStack(spacing: 8) {
                    ForEach(shortcutItems.prefix(3)) { item in
                        Button {
                            Task {
                                await insertOrSend(item.prompt, autoSend: shortcutAutoSend)
                            }
                        } label: {
                            HStack {
                                Image(systemName: "arrow.right.circle.fill")
                                    .foregroundStyle(.blue)
                                Text(item.title)
                                    .font(.subheadline.weight(.medium))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color(.tertiarySystemBackground))
                            .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .id(UUID())
    }

    private func messageContextMenu(_ msg: ChatMessage) -> some View {
        Group {
            Button("Save as MD File") {
                let timestamp = Int(Date().timeIntervalSince1970)
                let filename = "chat_message_\(timestamp).md"
                Task {
                    await saveMessageAsMD(msg.content, filename: filename)
                }
            }
            .keyboardShortcut("m")

            Divider()

            Button("Copy") {
                UIPasteboard.general.string = msg.content
                let impact = UIImpactFeedbackGenerator(style: .light)
                impact.impactOccurred()
            }
            .keyboardShortcut("c")

            Button("Share") {
                ShareSheet.present(items: [msg.content])
            }
            .keyboardShortcut("s")
        }
    }

    private var selectedFilesDisplay: some View {
        Group {
            if !selectedFiles.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                        Text(Localization.locWithUserPreference("Attached Files", "附加檔案"))
                            .font(.caption.weight(.medium))
                        Text("(\(selectedFiles.count))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(selectedFiles, id: \.url) { file in
                                fileTag(file)
                            }
                        }
                    }.padding(.horizontal)
                }
                .background(Color(.secondarySystemBackground).opacity(0.5))
            }
        }
    }

    private func fileTag(_ file: (url: URL, content: String)) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.fill")
                .font(.caption)
                .foregroundStyle(.blue)

            Text(file.url.lastPathComponent)
                .font(.caption)
                .lineLimit(1)

            Button(action: {
                removeSelectedFile(file.url)
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.tertiarySystemBackground))
        .clipShape(Capsule())
    }

    private var shortcutsBar: some View {
        Group {
            if showShortcuts {
                ShortcutsBar(
                    items: shortcutItems,
                    showShortcuts: $showShortcuts,
                    autoSend: $shortcutAutoSend,
                    sending: sending,
                    onTap: { item in
                        Task {
                            await insertOrSend(
                                item.prompt,
                                autoSend: shortcutAutoSend
                            )
                        }
                    }
                )
            }
        }
    }

    private var inputBar: some View {
        InputBar(
            input: $input,
            hasSeed: !seedPrompt.isEmpty,
            sending: sending,
            selectedFiles: $selectedFiles,
            showFilePicker: $showFilePicker,
            onSeed: {
                Task {
                    await insertOrSend(
                        seedPrompt.isEmpty ? "" : seedPrompt,
                        autoSend: shortcutAutoSend
                    )
                }
            },
            docURL: docURL,
            onSend: { Task { await send() } }
        )
        .onAppear {
            if autoSend, !didAutoSend, !seedPrompt.isEmpty {
                didAutoSend = true
                Task {
                    let tempShortcut = ShortcutItem(
                        title: "Auto Prompt",
                        prompt: seedPrompt,
                        isPrimary: false
                    )
                    await sendShortcut(tempShortcut)
                }
            }
        }
    }

    private var sidebarView: some View {
        SavedChatsList()
            .frame(width: 250)
            .offset(x: showSidebar ? 0 : -250)
            .animation(.spring(), value: showSidebar)
            .zIndex(1)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard let lastId = convoAbbb.messages(for: docURL).last?.id else {
            return
        }
        withAnimation(.easeInOut(duration: 0.3)) {
            proxy.scrollTo(lastId, anchor: .bottom)
        }
    }

    @MainActor
    private func saveMessageAsMD(_ content: String, filename: String) async {
        do {
            let store = documentStore

            // Generate clean suggested name from content
            let suggestedName = cleanFilename(fromFirstSentenceOf: content)

            // Fallback name with timestamp if content is empty or fails
            let fallbackName =
                "chat_message_\(Int(Date().timeIntervalSince1970)).md"
            let baseName = suggestedName.isEmpty ? fallbackName : suggestedName

            // Ensure .md extension
            let nameWithExtension =
                baseName.hasSuffix(".md") ? baseName : "\(baseName).md"

            // Get a unique URL (this prevents overwriting!)
            let uniqueURL = try store.uniqueFileURL(baseName: nameWithExtension)

            // Final content with title
            let mdContent = "# Chat Message\n\n\(content)"

            // Save using the unique name
            let savedURL = try store.saveAs(
                content: mdContent,
                suggestedName: uniqueURL.lastPathComponent
            )

            // Notify UI to refresh file list
            NotificationCenter.default.post(
                name: NSNotification.Name("DocumentSaved"),
                object: nil
            )

            // Haptic feedback
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()

        } catch {
            errorMessage =
                "Failed to save MD file: \(error.localizedDescription)"
        }
    }

    // MARK: - Smart filename generator
    private func cleanFilename(fromFirstSentenceOf text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        // 1. Get the first sentence (stop at . ! ? or newline)
        var firstSentence = ""
        let sentenceEndings = CharacterSet(charactersIn: ".!?。！？\n")

        if let range = trimmed.rangeOfCharacter(from: sentenceEndings) {
            firstSentence = String(trimmed[..<range.upperBound])
        } else {
            // No punctuation → take first line or first 80 chars
            firstSentence =
                trimmed.components(separatedBy: .newlines).first
                ?? String(trimmed.prefix(80))
        }

        var cleaned =
            firstSentence
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // 2. Remove common Markdown/list prefixes (so we don’t get filenames starting with "1." or "-")
        let prefixesToRemove = [
            "^\\s*#+",  // # Heading
            "^\\s*-\\s*",  // - bullet
            "^\\s*•\\s*",  // bullet
            "^\\s*\\*\\s*",  // * bullet
            "^\\s*\\d+\\.\\s*",  // 1. 2. numbered list
            "^\\s*>\\s*",  // > quote
            "^\\s*\\[.\\]\\s*",  // [ ] or [x] checkbox
        ]

        for pattern in prefixesToRemove {
            cleaned = cleaned.replacingOccurrences(
                of: pattern,
                with: "",
                options: .regularExpression
            )
        }

        let safe =
            cleaned
            .replacingOccurrences(
                of: "[^\\p{L}\\p{N}\\s\\-_.]",
                with: "",
                options: .regularExpression
            )  // keep letters, numbers, space, - _ .
            .replacingOccurrences(
                of: "\\s+",
                with: " ",
                options: .regularExpression
            )  // multiple spaces → single
            .trimmingCharacters(in: .whitespaces)
            .prefix(100)  // max length to avoid too-long filenames

        let result = String(safe)
            .replacingOccurrences(of: " ", with: "_")  // spaces → underscores for nicer URLs

        return result.isEmpty ? "" : result
    }

    // MARK: - File Selection Logic

    private func removeSelectedFile(_ url: URL) {
        selectedFiles.removeAll { $0.url == url }
    }

    // MARK: - Helpers

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    @MainActor
    private func deductCoinIfPossible() -> Bool {
        let success = RewardedAdManager.shared.spendCoins(1)
        
        if success {
            return true
        }
        
        let isSubscribed = SubscriptionManager.shared.isSubscribed
        
        if isSubscribed {
            errorMessage = Localization.locWithUserPreference(
                "Not enough coins. Buy coins, or watch an ad to earn more!",
                "硬幣不足。購買硬幣，或觀看廣告賺取更多！"
            )
        } else {
            errorMessage = Localization.locWithUserPreference(
                "Not enough coins. Subscribe to Premium for 100 coins/month (ad-free!), buy coins, or watch an ad to earn more!",
                "硬幣不足。訂閱 Premium 每月獲得 100 硬幣（無廣告！）、購買硬幣，或觀看廣告賺取更多！"
            )
        }
        
        // Haptic feedback
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        
        return false
    }

    private func buildConversationForAPI(maxMessages: Int = 24, maxTotalTokensEstimate: Int = 100_000) -> [ChatMessage] {
        var conversation: [ChatMessage] = []
        
        let systemPrompt = buildSystemPrompt()
        conversation.append(.init(role: .system, content: systemPrompt))
        
        let allMessages = convoAbbb.messages(for: docURL)
        guard !allMessages.isEmpty else {
            return conversation
        }
        
        let recentMessages = allMessages.suffix(maxMessages)
        
        var filtered: [ChatMessage] = []
        for msg in recentMessages {
            let trimmed = msg.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                continue
            }
            
            if trimmed.hasPrefix("Error:") || trimmed.hasPrefix("Loading") {
                continue
            }
            
            filtered.append(msg)
        }
        
        var tokenEstimate = systemPrompt.utf8.count / 4 + 100
        
        var finalConversation = conversation
        for msg in filtered.reversed() {
            let msgTokens = msg.content.utf8.count / 4 + 20
            
            if tokenEstimate + msgTokens > maxTotalTokensEstimate {
                break
            }
            
            finalConversation.append(msg)
            tokenEstimate += msgTokens
        }

        return finalConversation
    }
    
    @MainActor
    private func sendShortcut(_ shortcut: ShortcutItem) async {
        sending = true
        defer { sending = false }

        let userMessage = ChatMessage(
            role: .user,
            content: shortcut.prompt,
            isShortcut: true
        )
        convoAbbb.append(userMessage, to: docURL)

        var fullConversation = buildConversationForAPI()

        if fullConversation.last?.role != .user {
            fullConversation.append(userMessage)
        }

        do {
            try await CoinProtection.withCoinProtected(actionDescription: "Shortcut / quick action") {
                let apiKey =
                    ProcessInfo.processInfo.environment["MINIMAX_API_KEY"]
                    ?? (Bundle.main.object(forInfoDictionaryKey: "MiniMaxAPIKey") as? String)
                    ?? ""

                guard !apiKey.isEmpty else {
                    throw NSError(domain: "APIError", code: -2, userInfo: [
                        NSLocalizedDescriptionKey: Localization.locWithUserPreference(
                            "Missing MiniMax API key.",
                            "缺少 MiniMax API 金鑰。"
                        )
                    ])
                }

                let reply = try await MiniMaxService.chatWithAutoContinue(
                    apiKey: apiKey,
                    messages: fullConversation,  // ← use full history
                    temperature: 0.1,
                    maxTokens: Constants.API.maxTokensStandard
                )

                var finalReply: String
                switch aiReplyLanguage {
                case .english:
                    finalReply = reply
                case .traditionalChinese:
                    let hasChinese = reply.range(
                        of: #"[\u4E00-\u9FFF]"#,
                        options: .regularExpression
                    ) != nil
                    let chineseRatio = Double(reply.unicodeScalars.filter { $0.value >= 0x4E00 && $0.value <= 0x9FFF }.count) / Double(max(reply.count, 1))
                    
                    if !hasChinese || chineseRatio < 0.3 {
                        finalReply = "（以下以正體中文回覆）\n" + reply
                    } else {
                        finalReply = reply
                    }
                }

                let assistantMessage = ChatMessage(
                    role: .assistant,
                    content: finalReply
                )
                convoAbbb.append(assistantMessage, to: docURL)
                convoAbbb.saveToDisk(for: docURL)

                return ()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func send() async {
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else { return }

        sending = true
        defer { sending = false }

        let userMessage = ChatMessage(role: .user, content: trimmedInput)
        convoAbbb.append(userMessage, to: docURL)

        var fullConversation = buildConversationForAPI()

        if fullConversation.last?.role != .user {
            fullConversation.append(userMessage)
        }
        
        let languageReminder = aiReplyLanguage == .traditionalChinese 
            ? "\n\n⚠️ 請使用正體中文回覆 | Please respond in Traditional Chinese"
            : "\n\n⚠️ Please respond in English"

        var finalReply: String = ""
        
        do {
            try await CoinProtection.withCoinProtected(actionDescription: "Normal chat message") {
                var lastUserMessageIndex = fullConversation.count - 1
                if lastUserMessageIndex >= 0 && fullConversation[lastUserMessageIndex].role == .user {
                    fullConversation[lastUserMessageIndex].content += languageReminder
                }
                let apiKey =
                    ProcessInfo.processInfo.environment["MINIMAX_API_KEY"]
                    ?? (Bundle.main.object(forInfoDictionaryKey: "MiniMaxAPIKey") as? String)
                    ?? ""

                guard !apiKey.isEmpty else {
                    throw NSError(domain: "APIError", code: -2, userInfo: [
                        NSLocalizedDescriptionKey: Localization.locWithUserPreference(
                            "Missing MiniMax API key.",
                            "缺少 MiniMax API 金鑰。"
                        )
                    ])
                }

                let reply = try await MiniMaxService.chatWithAutoContinue(
                    apiKey: apiKey,
                    messages: fullConversation,
                    temperature: 0.1,
                    maxTokens: Constants.API.maxTokensStandard
                )

                switch aiReplyLanguage {
                case .english:
                    finalReply = reply
                case .traditionalChinese:
                    let hasChinese = reply.range(
                        of: #"[\u4E00-\u9FFF]"#,
                        options: .regularExpression
                    ) != nil
                    let chineseRatio = Double(reply.unicodeScalars.filter { $0.value >= 0x4E00 && $0.value <= 0x9FFF }.count) / Double(max(reply.count, 1))
                    
                    if !hasChinese || chineseRatio < 0.3 {
                        finalReply = "（以下以正體中文回覆）\n" + reply
                    } else {
                        finalReply = reply
                    }
                }
            }
            
            let assistantMessage = ChatMessage(role: .assistant, content: finalReply)
            convoAbbb.append(assistantMessage, to: docURL)
            convoAbbb.saveToDisk(for: docURL)
        } catch {
            errorMessage = error.localizedDescription
        }

        input = ""
    }
    
    @MainActor
    private func insertOrSend(_ text: String, autoSend: Bool) async {
        if autoSend {
            let tempShortcut = ShortcutItem(
                title: "Inserted Prompt",
                prompt: text,
                isPrimary: false
            )
            await sendShortcut(tempShortcut)
        } else {
            if input.isEmpty {
                input = text
            } else {
                input += (input.hasSuffix("\n") ? "" : "\n") + text
            }
        }
    }

    private func buildSystemPrompt() -> String {
        let additionalFiles = selectedFiles.map { (url: $0.url, content: $0.content) }
        return PromptBuilder.buildChatSystemPrompt(
            docName: docURL.lastPathComponent,
            docContent: docText,
            additionalFiles: additionalFiles
        )
    }

}
// MARK: - Message Bubble
struct MessageBubble: View {
    let message: ChatMessage
    
    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if isUser { Spacer(minLength: 50) }

            VStack(
                alignment: isUser ? .trailing : .leading,
                spacing: 4
            ) {
                HStack(spacing: 6) {
                    if !isUser {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12))
                            .foregroundStyle(.purple)
                    }
                    Text(isUser ? "You" : "AI")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                NativeMarkdownView(
                    markdown: message.content,
                    horizontalAlignment: isUser ? .trailing : .leading,
                    ttsEnabled: .constant(MultiSettingsViewModel.shared.ttsEnabled)
                )
                .padding(6)
                .foregroundColor(.primary)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            isUser ? Color.gray.opacity(0.15) : Color.clear,
                            lineWidth: 1
                        )
                )
            }

            if !isUser { Spacer(minLength: 50) }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}
