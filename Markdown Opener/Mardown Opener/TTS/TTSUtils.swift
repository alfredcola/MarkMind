import AVFoundation
import Foundation

struct TTSUtils {
    static let maxSentenceLength: Int = 220

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
            ("\\n{3,}", "\n\n", [])
        ]

        for (pattern, replacement, options) in replacements {
            if let regex = try? NSRegularExpression(pattern: pattern, options: options) {
                s = regex.stringByReplacingMatches(in: s, options: [], range: NSRange(s.startIndex..., in: s), withTemplate: replacement)
            }
        }

        if let regex = try? NSRegularExpression(pattern: "\\[([^\\]]+)\\]\\([^)]*\\)", options: []) {
            s = regex.stringByReplacingMatches(in: s, options: [], range: NSRange(s.startIndex..., in: s), withTemplate: "$1")
        }

        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func linguisticSentenceSplit(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        let tagger = NSLinguisticTagger(tagSchemes: [.tokenType], options: 0)
        tagger.string = text
        var sentences: [String] = []
        let range = NSRange(text.startIndex..<text.endIndex, in: text)

        tagger.enumerateTags(in: range, unit: .sentence, scheme: .tokenType, options: [.omitWhitespace, .omitPunctuation, .joinNames]) { _, sentenceRange, _ in
            let sentence = (text as NSString).substring(with: sentenceRange)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty && ![".", "…", "•"].contains(sentence) {
                sentences.append(sentence)
            }
        }

        return sentences.isEmpty ? [text] : sentences
    }

    static func safeSplitLongSentence(sentence: String, maxLength: Int = maxSentenceLength) -> [String] {
        var parts: [String] = []
        var remaining = sentence

        while remaining.count > maxLength {
            let limit = remaining.index(remaining.startIndex, offsetBy: maxLength)
            if let splitPoint = remaining[..<limit].rangeOfCharacter(from: .whitespacesAndNewlines, options: .backwards)?.upperBound {
                let part = String(remaining[..<splitPoint]).trimmingCharacters(in: .whitespaces)
                if !part.isEmpty { parts.append(part) }
                remaining = String(remaining[splitPoint...]).trimmingCharacters(in: .whitespaces)
            } else {
                parts.append(String(remaining[..<limit]))
                remaining = String(remaining[limit...])
            }
        }
        if !remaining.isEmpty { parts.append(remaining) }
        return parts
    }

    static func computeTTSChunks(from text: String, isChinese: Bool) -> [String] {
        let maxLength = maxSentenceLength
        if isChinese {
            let punctuation = CharacterSet(charactersIn: "。？！，；：…")
            let sentences = text.components(separatedBy: punctuation)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.count > 1 }
            return
            sentences
                .flatMap {
                    safeSplitLongSentence(sentence: $0, maxLength: maxLength)
                }
                .filter { $0.count > 3 }
        } else {
            let sentences = linguisticSentenceSplit(text)
            var final: [String] = []
            for s in sentences {
                if s.count <= maxLength {
                    final.append(s)
                } else {
                    final.append(contentsOf: safeSplitLongSentence(sentence: s, maxLength: maxLength))
                }
            }
            return final.filter { !$0.isEmpty }
        }
    }
}