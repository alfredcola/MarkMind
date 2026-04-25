import Combine
import SwiftUI
import WidgetKit

struct RepresentableViewController: UIViewControllerRepresentable {
    let onViewController: (UIViewController) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        onViewController(vc)
        return vc
    }

    func updateUIViewController(
        _ uiViewController: UIViewController,
        context: Context
    ) {}
}

private let ADMINPASSWORD = "041129"

// MARK: - Enums
enum FileSort: String, CaseIterable, Identifiable, Codable {
    case nameAsc = "Name A-Z"
    case nameDesc = "Name Z-A"
    case dateNew = "Date Newest"
    case dateOld = "Date Oldest"
    case sizeLarge = "Size Largest"
    case sizeSmall = "Size Smallest"

    var id: String { rawValue }
}

enum MarkdownPreviewMode: String, Codable, CaseIterable, Identifiable {
    case web = "Web Preview"
    case native = "Native Preview"

    var id: String { rawValue }
}

enum MiniMaxModel: String, CaseIterable, Identifiable, Codable {
    case chat = "MiniMax-M2.7-highspeed"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chat: return "Chat"
        }
    }

    var timeoutInterval: TimeInterval {
        240
    }
}

enum EditorViewType: String, CaseIterable, Identifiable, Codable {
    case edit = "Edit"
    case preview = "Preview"

    var id: String { rawValue }
}

enum AppTheme: String, CaseIterable, Identifiable, Codable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var id: String { rawValue }
}

enum EditorTheme: String, CaseIterable, Identifiable, Codable {
    case light = "Light"
    case dark = "Dark"
    case sepia = "Sepia"

    var id: String { rawValue }
    
    var backgroundColor: Color {
        switch self {
        case .light: return .white
        case .dark: return Color(red: 0.1, green: 0.1, blue: 0.15)
        case .sepia: return Color(red: 0.96, green: 0.93, blue: 0.86)
        }
    }
}

enum AIVoice: String, CaseIterable, Identifiable, Codable {
    case sky = "af_sky"
    case alice = "bf_alice"
    case jessica = "af_jessica"
    case fable = "bm_fable"
    case george = "bm_george"
    case alloy = "af_alloy"
    case isabella = "bf_isabella"
    case liam = "am_liam"
    case onyx = "am_onyx"
    case lily = "bf_lily"
    case lewis = "bm_lewis"
    case kore = "af_kore"
    case emma = "bf_emma"
    case nova = "af_nova"
    case puck = "am_puck"
    case aoede = "af_aoede"
    case daniel = "bm_daniel"
    case santa = "am_santa"
    case nicole = "af_nicole"
    case michael = "am_michael"
    case echo = "am_echo"
    case sarah = "af_sarah"
    case adam = "am_adam"
    case eric = "am_eric"
    case fenrir = "am_fenrir"
    case river = "af_river"
    case heart = "af_heart"
    case bella = "af_bella"

    var id: String { rawValue }

    var displayName: String {
        rawValue.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "af ", with: "")
            .replacingOccurrences(of: "bf ", with: "")
            .replacingOccurrences(of: "bm ", with: "")
            .replacingOccurrences(of: "am ", with: "")
            .capitalized
    }

    var filename: String { rawValue + ".npy" }
}

enum TTSFontSize: String, CaseIterable, Identifiable, Codable {
    case small = "Small"
    case medium = "Medium"
    case large = "Large"

    var id: String { rawValue }

    var fontSize: CGFloat {
        switch self {
        case .small: return 14
        case .medium: return 17
        case .large: return 22
        }
    }
}

enum TTSHighlightingStyle: String, CaseIterable, Identifiable, Codable {
    case word = "Word"
    case sentence = "Sentence"
    case paragraph = "Paragraph"

    var id: String { rawValue }
}

enum TTSTheme: String, CaseIterable, Identifiable, Codable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
    case sepia = "Sepia"

    var id: String { rawValue }

    var backgroundColor: Color {
        switch self {
        case .system: return Color(UIColor.systemBackground)
        case .light: return .white
        case .dark: return Color(red: 0.1, green: 0.1, blue: 0.15)
        case .sepia: return Color(red: 0.96, green: 0.93, blue: 0.86)
        }
    }
}

enum TTSSleepTimerOption: Int, CaseIterable, Identifiable, Codable {
    case off = 0
    case fiveMinutes = 5
    case tenMinutes = 10
    case fifteenMinutes = 15
    case thirtyMinutes = 30
    case endOfDocument = -1

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .off: return "Off"
        case .fiveMinutes: return "5 min"
        case .tenMinutes: return "10 min"
        case .fifteenMinutes: return "15 min"
        case .thirtyMinutes: return "30 min"
        case .endOfDocument: return "End of Doc"
        }
    }
}

enum ChipGroup: String, CaseIterable, Identifiable, Codable {
    case starred = "Starred"
    case tags = "Tags"
    case markdown = "Markdown"
    case text = "Text Files"
    case pdf = "PDF"
    case docx = "Word"
    case pptx = "PowerPoint"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .starred: return "star.fill"
        case .tags: return "tag.fill"
        case .markdown: return "doc.text"
        case .text: return "doc.plaintext"
        case .pdf: return "doc.richtext"
        case .docx: return "doc"
        case .pptx: return "play.rectangle"
        }
    }

    var color: Color {
        switch self {
        case .starred: return .yellow
        case .tags: return .indigo
        case .markdown: return .orange
        case .text: return .blue
        case .pdf: return .red
        case .docx: return .green
        case .pptx: return .purple
        }
    }
}

// MARK: - ViewModel
final class MultiSettingsViewModel: ObservableObject {
    static let shared = MultiSettingsViewModel()

    @AppStorage("minimax_api_key") var apiKey: String = ""
    @AppStorage("enable_haptics") var enableHaptics: Bool = true
    @AppStorage("ads_disabled") var adsDisabled: Bool = false
    @AppStorage("manually_adsDisabled") var manually_adsDisabled: Bool = false
    @AppStorage("tts_enabled") var ttsEnabled: Bool = true
    @Published var adsPasswordInput: String = ""

    // Editor Settings
    @AppStorage("editor_font_size") var editorFontSize: Double = 17.0
    @AppStorage("editor_show_line_numbers") var showLineNumbers: Bool = false
    @AppStorage("editor_auto_save") var autoSaveEnabled: Bool = true
    @AppStorage("editor_auto_save_interval") var autoSaveInterval: Int = 30
    @AppStorage("editor_spell_check") var spellCheckEnabled: Bool = true
    @AppStorage("editor_default_view") var defaultEditorView: EditorViewType = .preview
    
    // Theme Settings
    @AppStorage("app_theme") var appTheme: AppTheme = .system
    @AppStorage("editor_theme") var editorTheme: EditorTheme = .light

    // File Sorting
    @AppStorage("file_sort_preference") private var fileSortRaw: String =
        FileSort.dateNew.rawValue
    var fileSort: FileSort {
        get { FileSort(rawValue: fileSortRaw) ?? .dateNew }
        set { fileSortRaw = newValue.rawValue }
    }

    // Markdown Preview
    @AppStorage("markdown_preferred_preview") private var preferredPreviewRaw:
        String = MarkdownPreviewMode.web.rawValue
    var preferredPreview: MarkdownPreviewMode {
        get { MarkdownPreviewMode(rawValue: preferredPreviewRaw) ?? .web }
        set { preferredPreviewRaw = newValue.rawValue }
    }

    // AI Reply Language
    @AppStorage("ai_reply_language") private var aiReplyLanguageRaw: String =
        AIReplyLanguage.english.rawValue
    var aiReplyLanguage: AIReplyLanguage {
        get { AIReplyLanguage(rawValue: aiReplyLanguageRaw) ?? .english }
        set { aiReplyLanguageRaw = newValue.rawValue }
    }

    // MiniMax Model Selection
    @AppStorage("minimax_model_preference") private var selectedModelRaw:
        String = MiniMaxModel.chat.rawValue
    var selectedModel: MiniMaxModel {
        get { MiniMaxModel(rawValue: selectedModelRaw) ?? .chat }
        set { selectedModelRaw = newValue.rawValue }
    }

    // AI Voice Selection (PERSISTENT)
    @AppStorage("selected_voice_preference") private var selectedVoiceRaw:
        String = AIVoice.sky.rawValue
    var selectedVoice: AIVoice {
        get { AIVoice(rawValue: selectedVoiceRaw) ?? .sky }
        set { selectedVoiceRaw = newValue.rawValue }
    }

    // TTS Playback Speed (0.5 - 2.0)
    @AppStorage("tts_playback_speed") var ttsPlaybackSpeed: Double = 1.0

    // TTS Pitch for AVSpeechSynthesizer (0.5 - 2.0)
    @AppStorage("tts_pitch") var ttsPitch: Double = 1.0

    // TTS Font Size
    @AppStorage("tts_font_size") private var ttsFontSizeRaw: String = TTSFontSize.medium.rawValue
    var ttsFontSize: TTSFontSize {
        get { TTSFontSize(rawValue: ttsFontSizeRaw) ?? .medium }
        set { ttsFontSizeRaw = newValue.rawValue }
    }

    // TTS Highlighting Style
    @AppStorage("tts_highlighting_style") private var ttsHighlightingStyleRaw: String = TTSHighlightingStyle.word.rawValue
    var ttsHighlightingStyle: TTSHighlightingStyle {
        get { TTSHighlightingStyle(rawValue: ttsHighlightingStyleRaw) ?? .word }
        set { ttsHighlightingStyleRaw = newValue.rawValue }
    }

    // TTS Theme
    @AppStorage("tts_theme") private var ttsThemeRaw: String = TTSTheme.system.rawValue
    var ttsTheme: TTSTheme {
        get { TTSTheme(rawValue: ttsThemeRaw) ?? .system }
        set { ttsThemeRaw = newValue.rawValue }
    }

    // TTS Sleep Timer
    @AppStorage("tts_sleep_timer") private var ttsSleepTimerRaw: Int = TTSSleepTimerOption.off.rawValue
    var ttsSleepTimer: TTSSleepTimerOption {
        get { TTSSleepTimerOption(rawValue: ttsSleepTimerRaw) ?? .off }
        set { ttsSleepTimerRaw = newValue.rawValue }
    }

    // TTS Auto Resume
    @AppStorage("tts_auto_resume") var ttsAutoResume: Bool = true

    // TTS Reading Positions (filePathHash -> chunkIndex)
    @AppStorage("tts_reading_positions") private var ttsReadingPositionsData: Data = Data()
    var ttsReadingPositions: [String: Int] {
        get {
            (try? JSONDecoder().decode([String: Int].self, from: ttsReadingPositionsData)) ?? [:]
        }
        set {
            ttsReadingPositionsData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    // TTS Last Played File
    @AppStorage("tts_last_played_file") var ttsLastPlayedFile: String = ""

    // PDF → MD Converter
    @Published var showPDFtoMDConverter: Bool = false

    // Ads Unlock
    func unlockAdsRemoval() {
        let trimmed = adsPasswordInput.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if trimmed == ADMINPASSWORD {
            manually_adsDisabled = true
            adsPasswordInput = ""
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    func relockAds() {
        manually_adsDisabled = false
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    init() {
        $chipGroupsOrder
            .sink { newOrder in
                if let data = try? JSONEncoder().encode(newOrder) {
                    UserDefaults.standard.set(data, forKey: "chip_groups_order")
                }
            }
            .store(in: &cancellables)

        setupSubscriptionObserver()
    }

    private func setupSubscriptionObserver() {
        SubscriptionManager.shared.$isSubscribed
            .removeDuplicates()
            .sink { [weak self] isSubscribed in
                guard let self = self else { return }

                if isSubscribed {
                    if !self.adsDisabled {
                        self.adsDisabled = true
                        print("Premium subscription active → Ads automatically disabled")
                    }
                } else {
                    if self.adsDisabled {
                        self.adsDisabled = false
                        print("Subscription ended → Ads re-enabled")
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    @AppStorage("chip_groups_order") private var chipOrderRaw: Data = {
        let defaultOrder: [ChipGroup] = [
            .starred, .tags, .markdown, .text, .pdf, .docx, .pptx,
        ]
        return try! JSONEncoder().encode(defaultOrder)
    }()

    @Published var chipGroupsOrder: [ChipGroup] = {
        let defaultOrder: [ChipGroup] = [
            .starred, .tags, .markdown, .text, .pdf, .docx, .pptx,
        ]
        if let data = UserDefaults.standard.data(forKey: "chip_groups_order"),
            let decoded = try? JSONDecoder().decode(
                [ChipGroup].self,
                from: data
            )
        {
            var result = decoded
            for item in ChipGroup.allCases where !result.contains(item) {
                result.append(item)
            }
            return result
        }
        return defaultOrder
    }()

    private var cancellables = Set<AnyCancellable>()

    // Add these properties
    @AppStorage("kokoro_model_downloaded") var kokoroModelDownloaded: Bool =
        false
    @Published var isDownloadingModel = false
    @Published var downloadProgress: Double = 0.0
    @Published var downloadError: String?

    func downloadKokoroModel() {
        guard !isDownloadingModel else { return }
        isDownloadingModel = true
        downloadProgress = 0.0
        downloadError = nil

        let urlString =
            "https://huggingface.co/mlx-community/Kokoro-82M-bf16/resolve/main/kokoro-v1_0.safetensors"
        guard let url = URL(string: urlString) else {
            downloadError = "Invalid URL"
            isDownloadingModel = false
            return
        }

        let task = URLSession.shared.downloadTask(with: url) {
            tempURL,
            response,
            error in
            DispatchQueue.main.async {
                self.isDownloadingModel = false

                if let error = error {
                    self.downloadError =
                        "Download failed: \(error.localizedDescription)"
                    return
                }

                guard let tempURL = tempURL else {
                    self.downloadError = "No file downloaded"
                    return
                }

                // Move to Documents directory
                let documentsURL = FileManager.default.urls(
                    for: .documentDirectory,
                    in: .userDomainMask
                )[0]
                let modelURL = documentsURL.appendingPathComponent(
                    "kokoro-v1_0.safetensors"
                )

                do {
                    if FileManager.default.fileExists(atPath: modelURL.path) {
                        try FileManager.default.removeItem(at: modelURL)
                    }
                    try FileManager.default.moveItem(at: tempURL, to: modelURL)
                    self.kokoroModelDownloaded = true
                    self.downloadProgress = 1.0
                    print("Kokoro model downloaded successfully")
                } catch {
                    self.downloadError =
                        "Save failed: \(error.localizedDescription)"
                }
            }
        }

        // Optional: Track progress (Hugging Face doesn't send progress, but we can simulate or skip)
        task.resume()
    }
    struct WidgetFlashcardItem: Identifiable {
        let id = UUID()
        let filename: String
        let displayName: String
        let fileURL: URL
        let cardCount: Int
    }

    func loadWidgetFlashcardItems() -> [WidgetFlashcardItem] {
        guard
            let containerURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier:
                    "group.com.alfredchen.MarkdownOpener"
            )
        else { return [] }

        let enumerator = FileManager.default.enumerator(
            at: containerURL,
            includingPropertiesForKeys: nil
        )
        var items: [WidgetFlashcardItem] = []

        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "json" else { continue }

            let filename = url.lastPathComponent
            let displayName = String(filename.dropLast(5))  // Remove ".json"

            // Try to count flashcards
            var cardCount = 0
            if let data = try? Data(contentsOf: url),
                let cards = try? JSONDecoder().decode(
                    [Flashcard].self,
                    from: data
                )
            {
                cardCount = cards.count
            }

            items.append(
                WidgetFlashcardItem(
                    filename: filename,
                    displayName: displayName,
                    fileURL: url,
                    cardCount: cardCount
                )
            )
        }

        return items.sorted { $0.displayName < $1.displayName }
    }

    func deleteWidgetFlashcard(at url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
            // Clear saved index for this file
            let indexKey = "widget_currentIndex_\(url.lastPathComponent)"
            sharedDefaults?.removeObject(forKey: indexKey)
            let lastTapKey = "widget_lastNextIntent_\(url.lastPathComponent)"
            sharedDefaults?.removeObject(forKey: lastTapKey)

            // Reload all widgets to reflect changes immediately
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            print("Failed to delete widget file: \(error)")
        }
    }

    private var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: "group.com.alfredchen.MarkdownOpener")
    }
}

// MARK: - Ad Gate
enum AdGate {
    static func shouldShowAds() -> Bool {
        !UserDefaults.standard.bool(forKey: "ads_disabled")
    }
}

// MARK: - Prompt Builder
enum PromptBuilder {
    
    static var currentLanguage: AIReplyLanguage {
        let raw = UserDefaults.standard.string(forKey: "ai_reply_language") ?? AIReplyLanguage.english.rawValue
        return AIReplyLanguage(rawValue: raw) ?? .english
    }
    
    static var isChinese: Bool {
        currentLanguage == .traditionalChinese
    }
    
    static var languageInstruction: String {
        isChinese ? "以正體中文回覆。" : "Respond in English."
    }
    
    static var languageCode: String {
        isChinese ? "zh-HK" : "en"
    }
    
    static func buildChatSystemPrompt(
        docName: String,
        docContent: String,
        additionalFiles: [(url: URL, content: String)] = []
    ) -> String {
        let intro = isChinese
            ? "你是一個專業的文件分析助手，擅長理解、總結和解釋各種文件內容。"
            : "You are a professional document analysis assistant, skilled at understanding, summarizing, and explaining various document contents."
        
        let properNounRule = isChinese
            ? "\n重要規則：專有名詞請勿直接翻譯，請在專有名詞後括號內附上中文翻譯（例如：Apple (蘋果)、Stanford University (史丹佛大學)）。"
            : "\nImportant rule: Do not translate proper nouns directly. Add the translation in parentheses after the proper noun (e.g., Apple (蘋果), Stanford University (史丹佛大學))."
        
        let languageEnforce = isChinese
            ? """
            
            ═════════════════════════════════════════════════════════════
            ⚠️ 語言強制規定 (CRITICAL LANGUAGE RULE)：
            你必須使用「正體中文（繁體中文）」回覆所有內容！
            - 所有回答必須是正體中文
            - 所有術語、概念解釋必須是正體中文
            - 絕對不能使用英文（包括代碼註釋）
            - 這是最高優先級指令，必須遵守！
            ═════════════════════════════════════════════════════════════
            """
            : """
            
            ═════════════════════════════════════════════════════════════
            ⚠️ CRITICAL LANGUAGE RULE:
            You must respond in English for ALL content!
            - All answers must be in English
            - All terms and explanations must be in English
            - Never use Chinese (including code comments)
            - This is the highest priority instruction!
            ═════════════════════════════════════════════════════════════
            """
        
        var prompt = """
            \(intro)
            \(properNounRule)
            \(languageEnforce)
            
            保持回覆結構清晰，使用 Markdown 格式排版。
            Keep responses structured and clear, using Markdown formatting.
            """
        
        prompt += """
            
            Primary document (\(docName)):
            \(String(docContent.prefix(100_000)))
            """
        
        for (index, file) in additionalFiles.enumerated() {
            prompt += """
                
                Additional document \(index + 1) (\(file.url.lastPathComponent)):
                \(String(file.content.prefix(100_000)))
                """
        }
        
        return prompt
    }
    
    static func buildMCSystemPrompt(
        customInstructions: String,
        excludeQuestions: [String] = [],
        weakAreas: [String] = []
    ) -> String {
        let role = isChinese
            ? "你是一位資深試題設計專家，擅長根據文件內容設計專業認證考試的選擇題。"
            : "You are a senior test design expert, skilled at designing professional certification exam multiple-choice questions based on document content."
        
        let languageEnforce = isChinese
            ? "\n強制語言要求：所有題目和選項必須使用正體中文。"
            : "\nMandatory language requirement: All questions and options must be in the specified language."
        
        let outputFormat = isChinese
            ? """
            
            ### 輸出格式（嚴格遵守）
            Q: [直接提問]
            A) [選項]
            B) [選項]
            C) [選項]
            D) [選項]
            Correct: [字母]
            
            （卡片間用一個空行分隔，不使用編號、星號或粗體。）
            """
            : """
            
            ### Output Format (Strict Compliance)
            Q: [Direct Question]
            A) [Option]
            B) [Option]
            C) [Option]
            D) [Option]
            Correct: [Letter]
            
            (One blank line between cards, no numbering, asterisks, or bold.)
            """
        
        var prompt = """
            \(role)
            \(languageEnforce)
            
            ### 1. Zero-Fluff Phrasing Protocol
            - No lead-in phrases like "Based on the text," "According to the document"
            - Direct start: Every question must start with the core noun or action
            - Question stem: 10-15 words. Options: 1-6 words.
            
            ### 2. Competitive Interference Principle
            - All incorrect options must be real terms/concepts from the document
            - All options must belong to the same category
            - No two options can mean the same thing
            - Never use "All of the above" or "None of the above"
            
            ### 3. Quality Control
            - Each question must target different content from the document
            - Questions must be independent and self-contained
            - Grammatically parallel options
            \(outputFormat)
            """
        
        if !excludeQuestions.isEmpty {
            let excludedList = excludeQuestions.prefix(30).map { "- \($0)" }.joined(separator: "\n")
            let exclusionNote = isChinese
                ? "\n### 排除題目（不要使用這些概念）\n\(excludedList)"
                : "\n### Excluded Questions (Do not use these concepts)\n\(excludedList)"
            prompt += exclusionNote
        }
        
        if !weakAreas.isEmpty {
            let weakList = weakAreas.prefix(10).map { "- REINFORCE: \($0)" }.joined(separator: "\n")
            let focusNote = isChinese
                ? "\n### 重點強化（針對以下弱點設計新題目）\n\(weakList)"
                : "\n### Focus Areas (Design new questions addressing these weaknesses)\n\(weakList)"
            prompt += focusNote
        }
        
        if !customInstructions.isEmpty {
            let customNote = isChinese
                ? "\n### 自訂要求\n\(customInstructions)"
                : "\n### Custom Requirements\n\(customInstructions)"
            prompt += customNote
        }
        
        return prompt
    }
    
    static func buildFlashcardSystemPrompt(
        mode: FlashcardMode,
        customInstructions: String = ""
    ) -> String {
        let languageEnforce = isChinese
            ? "\n強制語言要求：所有內容必須使用正體中文。"
            : "\nMandatory language requirement: All content must be in English."
        
        let outputFormat = isChinese
            ? """
            
            ### 輸出格式（嚴格遵守）
            Q: [正面內容]
            A: [背面內容]
            
            （卡片間用一個空行分隔，不使用編號或標題。）
            """
            : """
            
            ### Output Format (Strict Compliance)
            Q: [Front content]
            A: [Back content]
            
            (One blank line between cards, no numbering or headers.)
            """
        
        var prompt: String
        
        switch mode {
        case .bilingual:
            let direction = "Front → Back translation"
            prompt = """
                \(languageEnforce)
                
                You are an expert in bilingual terminology and proper noun translation.
                Generate atomic flashcards for term recognition and translation.
                
                Direction: \(direction)
                
                Rules:
                - Each term appears EXACTLY ONCE
                - Use the most standard, official translation
                - Keep extremely concise: 1-6 words max
                - No explanations, examples, context, or extra text
                - Extract only from the provided document
                \(outputFormat)
                """
                
        case .explanation:
            prompt = """
                \(languageEnforce)
                
                You are an expert educator specializing in clear, memorable explanations.
                Generate atomic flashcards for active recall from the provided document.
                
                Rules:
                - One focused idea per card only
                - Front: Natural recall-forcing question or prompt
                - Back: Concise explanation (3-6 short sentences max)
                - Include one brief analogy or key example if helpful
                - Prioritize important concepts, definitions, processes
                - Avoid overlap across cards
                \(outputFormat)
                """
        }
        
        if !customInstructions.isEmpty {
            prompt += "\n\nAdditional instructions: \(customInstructions)"
        }
        
        return prompt
    }
    
    static func buildSelectionChatPrompt(
        selectedText: String,
        fullDocText: String,
        isFullDoc: Bool
    ) -> String {
        let intro = isChinese
            ? "你是一個專業的文本解說助手。"
            : "You are a professional text explanation assistant."
        
        let languageEnforce = isChinese
            ? "\n強制要求：使用正體中文回覆。"
            : "\nMandatory requirement: Respond in English."
        
        let scope = isFullDoc
            ? (isChinese ? "請根據完整文件內容回答。" : "Answer based on the full document content.")
            : (isChinese ? "僅根據選取的文本回答，不要總結全文。" : "Answer based ONLY on the selected text, do not summarize the entire document.")
        
        return """
            \(intro)
            \(languageEnforce)
            
            \(scope)
            
            Selected text:
            \(selectedText)
            
            Full document context (use sparingly if needed):
            \(String(fullDocText.prefix(30_000)))
            """
    }
}


