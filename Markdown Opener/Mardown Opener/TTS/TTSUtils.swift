import AVFoundation
import Foundation

final class ChineseTTSDelegate: NSObject, AVSpeechSynthesizerDelegate {
    let completion: () -> Void

    init(completion: @escaping () -> Void) {
        self.completion = completion
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        completion()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        completion()
    }
}

struct TTSUtils {
    static func detectContentLanguage(_ text: String) -> (isChinese: Bool, voiceLocale: String) {
        let chineseCount = text.unicodeScalars.filter {
            (0x4E00...0x9FFF).contains($0.value) || (0x3400...0x4DBF).contains($0.value) || (0xF900...0xFAFF).contains($0.value)
        }.count

        let chineseRatio = Double(chineseCount) / Double(text.count)
        return (chineseRatio > 0.3, "zh-HK")
    }

    static func canKokoroHandleText(_ text: String) -> Bool {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { return false }

        let nonEnglishCount = cleanText.unicodeScalars.filter { scalar in
            let value = scalar.value
            let isCJK = (0x4E00...0x9FFF).contains(value) || (0x3400...0x4DBF).contains(value) || (0xF900...0xFAFF).contains(value)
            let isJapanese = (0x3040...0x309F).contains(value) || (0x30A0...0x30FF).contains(value)
            let isKorean = (0xAC00...0xD7AF).contains(value) || (0x1100...0x11FF).contains(value)
            let isCyrillic = (0x0400...0x04FF).contains(value)
            let isArabic = (0x0600...0x06FF).contains(value) || (0x0750...0x077F).contains(value)
            let isThai = (0x0E00...0x0E7F).contains(value)
            return isCJK || isJapanese || isKorean || isCyrillic || isArabic || isThai
        }.count

        return Double(nonEnglishCount) / Double(cleanText.count) < 0.1
    }

    static func cleanMarkdownForTTS(_ text: String) -> String {
        var s = text

        if let regex = try? NSRegularExpression(pattern: "```[\\s\\S]*?```", options: []) {
            s = regex.stringByReplacingMatches(in: s, options: [], range: NSRange(s.startIndex..., in: s), withTemplate: " ")
        }

        if let regex = try? NSRegularExpression(pattern: "`([^`]+)`", options: []) {
            s = regex.stringByReplacingMatches(in: s, options: [], range: NSRange(s.startIndex..., in: s), withTemplate: "$1")
        }

        let replacements: [(String, String, NSRegularExpression.Options)] = [
            ("!\\[[^\\]]*\\]\\([^)]*\\)", "", []),
            ("^#{1,6}\\s+", "", [.anchorsMatchLines]),
            ("^[-*_]{3,}$", "", [.anchorsMatchLines]),
            ("\\*\\*(.*?)\\*\\*", "$1", []),
            ("__(.*?)__", "$1", []),
            ("\\*(.*?)\\*", "$1", []),
            ("_(.*?)_", "$1", []),
            ("^\\s*[-*+•]\\s+", "", [.anchorsMatchLines]),
            ("^\\s*\\d+\\.\\s+", "", [.anchorsMatchLines]),
            ("\\[([^\\]]+)\\]\\([^)]+\\)", "$1", [])
        ]

        for (pattern, replacement, options) in replacements {
            if let regex = try? NSRegularExpression(pattern: pattern, options: options) {
                s = regex.stringByReplacingMatches(in: s, options: [], range: NSRange(s.startIndex..., in: s), withTemplate: replacement)
            }
        }

        return s
    }

    static func linguisticSentenceSplit(_ text: String) -> [String] {
        var sentences: [String] = []
        let tagger = NSLinguisticTagger(tagSchemes: [.tokenType], options: 0)
        tagger.string = text

        let range = NSRange(text.startIndex..., in: text)
        var currentSentence = ""

        tagger.enumerateTags(in: range, unit: .word, scheme: .tokenType, options: []) { _, tokenRange, _ in
            let word = String(text[Range(tokenRange, in: text)!])

            if let punctuationRange = text.range(of: word, range: tokenRange.lowerBound..<text.endIndex),
               punctuationRange.upperBound < text.endIndex {
                let afterWord = text[punctuationRange.upperBound]
                currentSentence += word

                if ".!?".contains(afterWord) {
                    currentSentence += String(afterWord)
                    sentences.append(currentSentence.trimmingCharacters(in: .whitespacesAndNewlines))
                    currentSentence = ""
                } else {
                    currentSentence += " "
                }
            }
        }

        if !currentSentence.isEmpty {
            let remaining = String(text[text.index(text.startIndex, offsetBy: sentences.reduce(0) { $0 + $1.count + 1 }, limitedTo: text.endIndex)...])
            sentences.append(contentsOf: remaining.components(separatedBy: .newlines).filter { !$0.isEmpty })
        }

        return sentences.isEmpty ? [text] : sentences
    }
}