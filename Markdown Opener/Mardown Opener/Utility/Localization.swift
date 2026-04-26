import Foundation

enum Localization {
    static func loc(_ en: String, _ zh: String) -> String {
        let isChinese = Locale.current.language.languageCode?.identifier == "zh"
        return isChinese ? zh : en
    }

    static func locWithUserPreference(_ en: String, _ zh: String) -> String {
        let aiReplyLanguageRaw = UserDefaults.standard.string(forKey: "ai_reply_language") ?? AIReplyLanguage.english.rawValue
        let aiReplyLanguage = AIReplyLanguage(rawValue: aiReplyLanguageRaw) ?? .english
        return aiReplyLanguage == .traditionalChinese ? zh : en
    }
}