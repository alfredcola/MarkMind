//
//  BilingualDirection.swift
//  Markdown Opener
//
//  Created by alfred chen on 8/3/2026.
//
internal import AVFAudio
import SwiftUI



// MARK: - Bilingual Direction Choice
enum BilingualDirection: String, CaseIterable, Identifiable {
    case englishToChinese = "English → 正體中文"
    case chineseToEnglish = "正體中文 → English"

    var id: String { rawValue }

    var frontLanguageDescription: String {
        switch self {
        case .englishToChinese: return "English"
        case .chineseToEnglish: return "正體中文"
        }
    }

    var backLanguageDescription: String {
        switch self {
        case .englishToChinese: return "正體中文"
        case .chineseToEnglish: return "English"
        }
    }
}

// MARK: - Flashcard Mode
enum FlashcardMode: String, CaseIterable, Identifiable {
    case bilingual = "中英對照"
    case explanation = "文字解釋"

    var id: String { rawValue }

    var systemPrompt: String {
        let languageInfo =
            "AI Reply Language: \(AIReplyLanguage.english.displayName) (\(AIReplyLanguage.english.localeIdentifier))"
        switch self {
        case .bilingual:
            return """
                You are an expert in standard bilingual terminology and proper nouns across languages.

                Generate atomic flashcards strictly for proper noun/term recognition and translation.

                Direction: Front → \(BilingualDirection.placeholderFront) only
                Back → \(BilingualDirection.placeholderBack) only
                (User has explicitly selected this fixed direction.)

                Key Rules:
                - Each proper noun or key term appears EXACTLY ONCE (no duplicates or reverse-direction pairs).
                - Use the single most standard, official, and widely accepted translation.
                - Both front and back must be extremely concise: 1–6 words max, pure name/term only.
                - No explanations, examples, context, pinyin/romanization, articles ("the"), or extra text.
                - Prioritize variety: people (historical & modern), places, organizations, brands, theories, laws, treaties, events, works (books/films), scientific terms, etc.
                - Extract only from the provided document content — do not invent terms.

                STRICT OUTPUT FORMAT (nothing else):
                Q: [front term exactly as it appears]
                A: [back translation exactly]

                One blank line between cards. No numbering, headers, or commentary.

                Document content:
                """

        case .explanation:
            return """
                You are a master \(languageInfo) educator specializing in clear, memorable explanations for intermediate-to-advanced learners.

                Generate atomic flashcards optimized for strong active recall from the provided \(languageInfo) document.

                Rules:
                - One single, focused idea/concept per card only (atomic principle).
                - Front: A natural, recall-forcing question or prompt in \(languageInfo) only.
                  • Vary phrasing for better retention: e.g., "什麼是[概念]？", "[概念]的定義？", "[概念]如何運作？", "[事件]的起因是？", etc.
                  • Keep front short and precise — force retrieval without giving away the answer.
                - Back: Concise explanation in natural, clear \(languageInfo) only.
                  • 3–6 short sentences max.
                  • Use simple, precise language.
                  • Include one brief analogy, key example, or distinguishing feature if it strengthens recall (but keep brief).
                  • No bullet points, \(languageInfo), or unnecessary details.
                - Prioritize important concepts, definitions, processes, historical events, cultural notes, etc.
                - Avoid overlap or duplicate ideas across cards.

                STRICT OUTPUT FORMAT (nothing else):
                Q: [front question/prompt]
                A: [back explanation]

                One blank line between cards. No numbering, headers, extras, or commentary.

                Document content:
                """
        }
    }
}

extension BilingualDirection {
    static let placeholderFront = "{FRONT_LANG}"
    static let placeholderBack = "{BACK_LANG}"
}
