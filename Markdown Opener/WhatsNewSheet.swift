import SwiftUI

struct WhatsNewSheet: View {
    @Binding var isPresented: Bool
    @State private var forceChinese = false
    
    private var isZH: Bool {
        forceChinese || (Locale.current.language.languageCode?.identifier == "zh" &&
                        Locale.current.region?.identifier == "HK")
    }
    
    private var latestVersion: Version {
        versions[0] // Always show latest first
    }
    
    
    // MARK: - Version History Data
    private let versions: [Version] = [
        Version(
            version: "1.1.4",
            date: "2026年3月",
            dateEN: "March 2026",
            title: "編輯器全面升級",
            titleEN: "Editor Enhanced",
            isLatest: true,
            features: [
                Feature(
                    emoji: "📊",
                    en: "Editor Stats Bar",
                    zh: "編輯器統計列",
                    enDesc: "Real-time word count, character count, line count, and reading time estimate displayed at the bottom of the editor.",
                    zhDesc: "即時顯示字數、字元數、行數與預估閱讀時間，讓你掌握文件詳細資訊。"
                ),
                Feature(
                    emoji: "✨",
                    en: "Enhanced File Organization",
                    zh: "強化的檔案整理",
                    enDesc: "Tags now save their expanded/collapsed state. File groups and favorites section also remember your preferences after restart.",
                    zhDesc: "標籤的展開/收合狀態現在會自動儲存。檔案群組與收藏區塊也會記住你的偏好設定，App 重啟後依然保留。"
                ),
                Feature(
                    emoji: "⌨️",
                    en: "Keyboard Shortcuts",
                    zh: "鍵盤快速鍵",
                    enDesc: "Quick actions with keyboard shortcuts: ⌘O (Open), ⌘N (New), ⌘S (Save), ⌘F (Find), ⌘R (Rename), ⌘⌫ (Delete).",
                    zhDesc: "使用鍵盤快速鍵快速操作：⌘O（開啟）、⌘N（新增）、⌘S（儲存）、⌘F（尋找）、⌘R（重新命名）、⌘⌫（刪除）。"
                ),
                Feature(
                    emoji: "🎨",
                    en: "Improved Theme Support",
                    zh: "改善的主題支援",
                    enDesc: "Better dark/light mode support that automatically follows system settings for a seamless experience.",
                    zhDesc: "更好的深色/淺色模式支援，自動跟隨系統設定，提供無縫的使用體驗。"
                )
            ]
        ),
        Version(
            version: "1.1.3",
            date: "2025年12月",
            dateEN: "December 2025",
            title: "聊天紀錄儲存與選取文字問 AI",
            titleEN: "Chat History Saving & Ask AI on Selected Text",
            isLatest: true,
            features: [
                Feature(
                    emoji: "💬",
                    en: "Save Chat Sessions Anytime",
                    zh: "隨時儲存聊天紀錄",
                    enDesc: "You can now save any ongoing document chat at any time with a custom title. All saved chats appear in the sidebar for quick access and review later — even after closing the app.",
                    zhDesc: "現在可隨時為目前的文件聊天對話命名並儲存。所有儲存的對話會出現在側邊欄，方便之後快速開啟與回顧，即使關閉 App 後也能保留。"
                ),
                Feature(
                    emoji: "✨",
                    en: "Ask AI About Selected Text",
                    zh: "選取文字直接問 AI",
                    enDesc: "Select any text in the document and tap 'Ask AI about selection' — instantly get a focused explanation or analysis of just that passage. Includes dedicated chat view, automatic initial response, follow-up questions, and ability to save these selection chats too.",
                    zhDesc: "在文件中選取任何文字後，點擊「詢問 AI 關於選取內容」——立即獲得針對該段落的專注解釋或分析。提供專屬聊天視窗、自動初始回應、可繼續提問，並同樣支援儲存這些選取文字的對話紀錄。"
                ),
                Feature(
                    emoji: "📂",
                    en: "Saved Selection Chats Sidebar",
                    zh: "儲存的選取對話側邊欄",
                    enDesc: "All saved selection-based chats are organized in the sidebar with previews, message counts, and relative dates for easy management.",
                    zhDesc: "所有儲存的選取文字對話統一集中在側邊欄，顯示標題預覽、訊息數量與相對時間，管理更方便。"
                ),
                Feature(
                    emoji: "🃏",
                    en: "Flashcard Widget – Study on Home Screen",
                    zh: "閃卡小工具 – 主畫面直接複習",
                    enDesc: "Turn your generated flashcards into beautiful interactive Home Screen widgets! Choose any saved flashcard set, tap to reveal answers and swipe through cards with smooth progress tracking. Supports small, medium, and large sizes — perfect for quick daily reviews without opening the app.",
                    zhDesc: "將生成的閃卡直接變成主畫面互動小工具！選擇任意儲存的閃卡集，點擊顯示答案、輕鬆切換卡片，並有進度條追蹤。支援小、中、大三種尺寸，適合每天快速複習，完全不用打開 App。"
                ),
                Feature(
                    emoji: "📊",
                    en: "Review Multiple-Choice Study History",
                    zh: "檢視多選題複習歷史",
                    enDesc: "Track your progress with a dedicated history view for multiple-choice study sessions. See past scores, dates, and performance percentages for each document (or all documents combined). Easily review details and delete old records.",
                    zhDesc: "全新多選題複習歷史檢視頁面，追蹤每份文件的練習進度。顯示每次測驗的日期、得分、正確率，可檢視詳細結果，也支援刪除舊記錄。同時提供「全部文件」總覽模式。"
                )
            ]
        ),
        Version(
            version: "1.01.2",
            date: "2025年12月",
            dateEN: "December 2025",
            title: "iPad 體驗再升級",
            titleEN: "iPad experience upgraded",
            isLatest: false,
            features: [
                Feature(
                    emoji: "≡",
                    en: "All-New iPad Experience",
                    zh: "全新 iPad 體驗",
                    enDesc: "A gorgeous collapsible sidebar, floating show/hide button, and full toolbar that never disappears.",
                    zhDesc: "可收合的側邊欄、懸浮顯示按鈕、永遠保留的完整工具列 "
                )
            ]
        ),
        Version(
            version: "1.01.1",
            date: "2025年12月",
            dateEN: "December 2025",
            title: "自訂圖書館排序，體驗再升級",
            titleEN: "Custom Library Order & Refined Experience",
            isLatest: true,
            features: [
                Feature(
                    emoji: "✨",
                    en: "Reorder Library Chips Your Way",
                    zh: "完全自由排序頂部標籤列",
                    enDesc: "Drag to reorder Starred, Tags, Markdown, PDF, etc. chips at the top of your library — now in any order you prefer!",
                    zhDesc: "終於可以拖曳重新排序「星號」、「標籤」、Markdown、PDF 等頂部快捷芯片啦！完全按照你的使用習慣排列"
                ),
                
                Feature(
                    emoji: "🖌️",
                    en: "Smoother Sheet Presentation",
                    zh: "更優雅的滑出式設定",
                    enDesc: "Library chip ordering now opens in a beautiful bottom sheet — consistent with Tag Manager and other modern flows.",
                    zhDesc: "排序設定改為底部滑出面板，與標籤管理等介面風格統一，手感更流暢舒適"
                )
            ]
        ),
        Version(
            version: "1.01",
            date: "2025年12月",
            dateEN: "December 2025",
            title: "升級 AI TTS 與全螢幕編輯器",
            titleEN: "AI TTS & Full-Screen Editor",
            isLatest: false,
            features: [
                Feature(
                    emoji: "🔊",
                    en: "AI TTS (A16 Bionic chip or later, iPhone 14 Pro+ / M1 iPad+ only)",
                    zh: "升級 AI 語音朗讀（僅 A16 Bionic chip or later, iPhone 14 Pro+ / M1 iPad+）",
                    enDesc: "Neural AI TTS for natural English speech on iPhone 14 Pro+ and M1+ iPads. Other devices use built-in TTS. Supports Markdown, Chat, and Flashcards.",
                    zhDesc: "iPhone 14 Pro 及 M1 iPad 以上使用自然 AI 神經語音，其他裝置使用內建TTS。支援 Markdown、聊天與閃卡。"
                ),
                Feature(
                    emoji: "📱",
                    en: "Full-Screen Editor Mode",
                    zh: "全螢幕編輯模式",
                    enDesc: "Click bottom area to expand editor to full screen — larger text for easy reading, immersive editing experience.",
                    zhDesc: "點擊底部空白區域開啟全螢幕 — 更大字體易讀、沉浸式編輯，iPad 大螢幕完美利用。"
                )
            ]
        ),


        Version(
            version: "1.0.17",
            date: "2025年12月",
            dateEN: "December 2025",
            title: "全面支援 iPadOS",
            titleEN: "Full iPadOS Support",
            isLatest: false,
            features: [
                Feature(emoji: "iPad",
                        en: "Native iPadOS Experience",
                        zh: "真正原生 iPad 體驗",
                        enDesc: "App now launches with the last opened or shared file automatically — exactly like on iPhone. No more 'Not yet selected' on startup!",
                        zhDesc: "iPad 啟動時終於跟 iPhone 一樣智慧！自動載入上次檔案或外部分享進來的檔案，開啟 App 就直接進入內容，再也不用手動點「開啟檔案」"),
            ]
        ),
        Version(
            version: "1.0.16",
            date: "2025年12月",
            dateEN: "December 2025",
            title: "標籤上線 + 細節全面升級",
            titleEN: "Tags Arrived + Ultimate Polish",
            isLatest: false,
            features: [
                Feature(emoji: "🏷️",
                        en: "Smart Tag System",
                        zh: "全新智慧標籤系統",
                        enDesc: "Tag your files with custom colors! Tagged files automatically appear in dedicated sections at the top — just like Favorites, but more powerful and flexible!",
                        zhDesc: "為你的檔案加上自訂顏色標籤！被標記的檔案會自動出現在列表頂部專屬區塊，就像星標一樣強大，但更多樣、更自由！"),

                Feature(emoji: "🎨",
                        en: "Custom Tag Colors & Management",
                        zh: "自訂標籤顏色與完整管理",
                        enDesc: "Create, rename, recolor, and delete tags anytime. Every change instantly reflects across all files.",
                        zhDesc: "隨時新增、改名、換色、刪除標籤，所有變更即時同步到每一份檔案"),

                Feature(emoji: "📁",
                        en: "Full File Names Displayed",
                        zh: "完整顯示檔案名稱",
                        enDesc: "No more truncated names — see the entire file name clearly in the list!",
                        zhDesc: "不再被截斷！檔案列表現在完整顯示所有檔名"),

                Feature(emoji: "📜",
                        en: "Full Question & Answer View",
                        zh: "完整顯示題目與答案",
                        enDesc: "Flashcards now show the complete question and answer without cutting off text.",
                        zhDesc: "閃卡終於能完整顯示整段題目與答案，再也不會被截斷")
            ]
        ),
        Version(
            version: "1.0.15",
            date: "2025年11月",
            dateEN: "November 2025",
            title: "MarkMind 又升級啦！",
            titleEN: "MarkMind just got better!",
            isLatest: false,
            features: [
                Feature(emoji: "⭐", en: "Pin Your Favorite Files", zh: "收藏最愛檔案",
                        enDesc: "Swipe right on any file — favorites stay pinned at the top!",
                        zhDesc: "向右滑動即可收藏，檔案會永久固定在最頂！"),
                Feature(emoji: "🃏", en: "Smarter Flashcards", zh: "更聰明的閃卡",
                        enDesc: "All progress & spaced repetition status are fully saved.",
                        zhDesc: "所有學習進度與間隔重複狀態現已完整儲存"),
                Feature(emoji: "📄", en: "Plain Text Support", zh: "支援純文字檔案",
                        enDesc: "Open and edit .txt files directly in MarkMind.",
                        zhDesc: "現可直接開啟並編輯 .txt 檔案"),
                Feature(emoji: "🤖", en: "Generate Explanations One-by-One", zh: "逐張生成 AI 解釋",
                        enDesc: "Tap the wand — get AI explanations card-by-card instantly!",
                        zhDesc: "輕點魔法棒，逐張即時生成詳細 AI 解釋！"),
                Feature(emoji: "❤️", en: "Better Experience", zh: "整體體驗大提升",
                        enDesc: "Faster, smoother, more reliable than ever.",
                        zhDesc: "更快、更流暢、更穩定，體驗全面升級")
            ]
        ),
        Version(
            version: "1.0.14",
            date: "2025年10月",
            dateEN: "October 2025",
            title: "AI 解釋全面升級",
            titleEN: "AI Explanations Upgraded",
            isLatest: false,
            features: [
                Feature(emoji: "✨", en: "Smarter AI Explanations", zh: "更聰明的 AI 解釋",
                        enDesc: "Now with context-aware, beautiful formatting.",
                        zhDesc: "現支援上下文理解，排版更優美"),
                Feature(emoji: "🎯", en: "Focus Mode", zh: "專注模式",
                        enDesc: "Distraction-free reading experience.",
                        zhDesc: "無干擾閱讀體驗")
            ]
        ),
        Version(
            version: "1.0.12",
            date: "2025年9月",
            dateEN: "September 2025",
            title: "閃卡革命來了！",
            titleEN: "Flashcards Revolution!",
            isLatest: false,
            features: [
                Feature(emoji: "🧠", en: "Spaced Repetition", zh: "間隔重複學習",
                        enDesc: "Scientifically proven to boost memory retention.",
                        zhDesc: "科學驗證的記憶增強法"),
                Feature(emoji: "🎨", en: "Custom Themes", zh: "自訂主題",
                        enDesc: "Dark mode, sepia, and more.",
                        zhDesc: "深色模式、棕褐色護眼等")
            ]
        )
    ]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 32, pinnedViews: [.sectionHeaders]) {
                    Section {
                        VersionView(version: latestVersion, isZH: isZH, isLatest: true)
                    } header: {
                        HeaderView(isZH: isZH, forceChinese: $forceChinese, versionString: latestVersion.version)
                    }

                    
                    ForEach(versions.dropFirst()) { version in
                        Section {
                            VersionView(version: version, isZH: isZH, isLatest: false)
                        } header: {
                            VersionHeader(version: version.version,
                                          date: isZH ? version.date : version.dateEN,
                                          isLatest: version.isLatest)
                        }
                    }
                }
                
                VStack(spacing: 12) {
                    Button(isZH ? "開始使用！" : "Awesome! Let's Go") {
                        isPresented = false
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(.indigo)
                    .fontWeight(.semibold)
                }
                .padding(.vertical)
            }
            .navigationTitle(isZH ? "更新日誌" : "What's New")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isZH ? "關閉" : "Close") {
                        isPresented = false
                    }
                    .fontWeight(.medium)
                }
            }
        }
    }
}

// MARK: - Subviews
struct HeaderView: View {
    let isZH: Bool
    @Binding var forceChinese: Bool
    let versionString: String // Use String instead of Version
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 56))
                .foregroundStyle(.indigo.gradient)
                .symbolEffect(.pulse, options: .repeating)
            
            Text(isZH ? "MarkMind 又升級啦！" : "MarkMind just got better!")
                .font(.title).bold()
                .multilineTextAlignment(.center)
            
            Text(isZH ? "最新版本 \(versionString)" : "Latest Version \(versionString)")
                .font(.title3)
                .foregroundStyle(.secondary)
            
            HStack {
                Text("Language")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("", isOn: $forceChinese)
                    .labelsHidden()
                Text(forceChinese ? "中文" : "English")
                    .font(.caption).bold()
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
        }
        .frame(maxWidth: .infinity)
        .background(.ultraThickMaterial)
        .cornerRadius(12)
        .padding()
    }
}



struct VersionHeader: View {
    let version: String
    let date: String
    let isLatest: Bool
    
    var body: some View {
        HStack {
            Text("Version \(version)")
                .font(.headline)
                .fontWeight(.semibold)
            Spacer()
            Text(date)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

fileprivate struct VersionView: View {
    let version: Version
    let isZH: Bool
    let isLatest: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            LazyVGrid(columns: [GridItem(.flexible())], spacing: 16) {
                ForEach(version.features) { f in
                    HStack(spacing: 16) {
                        Text(f.emoji)
                            .font(.title2)
                            .frame(width: 48, height: 48)
                            .background(Circle().fill(.indigo.opacity(isLatest ? 0.2 : 0.1)))
                            .overlay(Circle().stroke(.indigo.opacity(0.4), lineWidth: 1))
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text(isZH ? f.zh : f.en)
                                .font(.headline)
                                .fontWeight(.medium)
                            
                            Text(isZH ? (f.zhDesc ?? f.enDesc ?? "") : (f.enDesc ?? f.zhDesc ?? ""))
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .lineLimit(nil)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            .padding(.horizontal)
        }
    }
}

// MARK: - Models
fileprivate struct Version: Identifiable {
    let id = UUID()
    let version: String
    let date: String
    let dateEN: String
    let title: String
    let titleEN: String
    let isLatest: Bool
    let features: [Feature]
}

fileprivate struct Feature: Identifiable {
    let id = UUID()
    let emoji: String
    let en: String
    let zh: String
    let enDesc: String?   // Now optional
    let zhDesc: String?   // Now optional
    
    init(emoji: String, en: String, zh: String, enDesc: String? = nil, zhDesc: String? = nil) {
        self.emoji = emoji
        self.en = en
        self.zh = zh
        self.enDesc = enDesc
        self.zhDesc = zhDesc
    }
}

// MARK: - Previews

#Preview("English") {
    WhatsNewSheet(isPresented: .constant(true))
}

#Preview("繁體中文 (HK)") {
    WhatsNewSheet(isPresented: .constant(true))
        .environment(\.locale, .init(identifier: "zh-HK"))
}
