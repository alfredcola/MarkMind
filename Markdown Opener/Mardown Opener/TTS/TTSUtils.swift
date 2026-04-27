import AVFoundation
import Foundation
import Markdown

struct TTSUtils {
    static let maxSentenceLength: Int = 220
    static let maxOverflowLength: Int = 50
    static let maxEffectiveLength: Int = maxSentenceLength + maxOverflowLength
    static let maxChunkLength: Int = 250
    static let sentenceBoundaryOverflow: Int = 80
    static let minChunkLength: Int = 20

    private static let sentenceContinuityMarkers: Set<Character> = [",", ";", ":", "，", "；", "："]

    private static let chinesePunctuation = CharacterSet(charactersIn: "\u{300C}\u{300D}\u{300E}\u{300F}\u{201C}\u{201D}\u{2018}\u{2019}。？！，；：…「」《》（）")
    private static let sentenceTerminals: Set<Character> = [".", "!", "?", "。", "！", "？", "…"]
    private static let clauseBreaks: Set<Character> = [",", ";", "，", "；"]
    private static let englishClauseBreaks = [", ", "; ", " and ", " but ", " or ", " however ", " therefore ", " moreover ", " nevertheless ", " thus ", " hence ", " — ", " – ", " so ", " yet ", " because ", " since ", " although ", " though "]
    private static let chineseClauseBreaks = ["，", "；", "、", "（", "——", "「"]
    private static let sentenceLikeAbbreviations: Set<String> = [
        "i.e.", "e.g.", "etc.", "vs.", "et al.",
        "Dr.", "Mr.", "Mrs.", "Ms.", "Prof.", "Inc.", "Ltd.", "Jr.", "Sr.",
        "U.S.", "U.K.", "U.N.", "E.U.", "E.g.", "I.e.",
        "a.m.", "p.m.", "A.M.", "P.M.",
        "approx.", "def.", "fig.", "no.", "nos.",
        "vol.", "ch.", "pt.", "p.",
        "St.", "Ste.", "Ave.", "Blvd.",
        "Corp.", "Gov.", "Dept.", "Div.", "Co.",
        "Jan.", "Feb.", "Mar.", "Apr.", "Jun.", "Jul.", "Aug.", "Sep.", "Oct.", "Nov.", "Dec.",
        "Mon.", "Tue.", "Wed.", "Thu.", "Fri.", "Sat.", "Sun.",
        " ed.", " ed",
        "pp.", "p"
    ]

    private static var hardSplitLog: [(text: String, chunk: String, reason: String)] = []
    private static let maxHardSplitLogSize = 20

    private static func logHardSplit(text: String, chunk: String, reason: String) {
        #if DEBUG
        hardSplitLog.append((text: text, chunk: chunk, reason: reason))
        if hardSplitLog.count > maxHardSplitLogSize {
            hardSplitLog.removeFirst()
        }
        #endif
    }

    static func getHardSplitLog() -> [(text: String, chunk: String, reason: String)] {
        return hardSplitLog
    }

    static func clearHardSplitLog() {
        hardSplitLog.removeAll()
    }

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

        s = parseTables(s)

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
            ("\\n{3,}", "\n\n", []),
            ("^\\s*>\\s+", "Quote: ", [.anchorsMatchLines]),
            ("- \\[ \\]", "○", []),
            ("- \\[x\\]", "✓", [.caseInsensitive]),
            ("^\\s*[-*+]\\s+\\[[ x]\\]\\s+", "", [.anchorsMatchLines])
        ]

        for (pattern, replacement, options) in replacements {
            if let regex = try? NSRegularExpression(pattern: pattern, options: options) {
                s = regex.stringByReplacingMatches(in: s, options: [], range: NSRange(s.startIndex..., in: s), withTemplate: replacement)
            }
        }

        if let regex = try? NSRegularExpression(pattern: "\\[([^\\]]+)\\]\\([^)]*\\)", options: []) {
            s = regex.stringByReplacingMatches(in: s, options: [], range: NSRange(s.startIndex..., in: s), withTemplate: "$1")
        }

        s = transformProblematicPatternsForTTS(s)

        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func transformProblematicPatternsForTTS(_ text: String) -> String {
        var result = text

        result = transformSystemReminders(result)
        result = transformEmojis(result)
        result = transformFractions(result)
        result = transformTime(result)
        result = transformPhoneNumbers(result)
        result = transformKeyboardShortcuts(result)
        result = transformMeasurements(result)
        result = transformSpecialLinks(result)
        result = transformVersionNumbers(result)
        result = transformGFMNestedListNumbers(result)
        result = transformDecimalNumbers(result)
        result = transformSymbolsForTTS(result)

        return result
    }

    private static func transformSystemReminders(_ text: String) -> String {
        var result = text

        if let regex = try? NSRegularExpression(pattern: "<system-reminder>[\\s\\S]*?</system-reminder>", options: [.caseInsensitive]) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: " ")
        }

        return result
    }

    private static func transformEmojis(_ text: String) -> String {
        var result = text

        let emojiMap: [String: String] = [
            "📝": "note",
            "💡": "idea",
            "🔗": "link",
            "⭐": "star",
            "🎯": "bullseye",
            "🔥": "fire",
            "✨": "sparkle",
            "👀": "eyes",
            "❤️": "heart",
            "👍": "thumbs up",
            "👎": "thumbs down",
            "👏": "applause",
            "🙌": "hooray",
            "😊": "smiling",
            "😂": "laughing",
            "😭": "crying",
            "😎": "cool",
            "🤔": "thinking",
            "🤷": "shrug",
            "📖": "book",
            "📄": "document",
            "📊": "chart",
            "📈": "graph up",
            "📉": "graph down",
            "🎉": "celebration",
            "🎊": "confetti ball",
            "✅": "checked",
            "❌": "crossed",
            "⚠️": "warning",
            "❓": "question",
            "❗": "exclamation",
            "💻": "computer",
            "📱": "phone",
            "🔽": "arrow down",
            "🔼": "arrow up",
            "➡️": "arrow right",
            "⬅️": "arrow left",
            "⬆️": "arrow up",
            "⬇️": "arrow down",
            "↩️": "arrow back",
            "↪️": "arrow forward",
            "🔀": "shuffle",
            "🔁": "repeat",
            "🔂": "repeat one",
            "⏮️": "previous",
            "⏭️": "next",
            "⏯️": "play pause",
            "⏸️": "pause",
            "⏹️": "stop",
            "⏺️": "record",
            "🎵": "music note",
            "🎶": "music notes",
            "🔇": "muted",
            "🔈": "speaker",
            "🔉": "speaker medium",
            "🔊": "speaker loud",
            "💬": "speech bubble",
            "💭": "thought bubble",
            "🗣️": "speaking",
            "👤": "person",
            "👥": "people",
            "👋": "waving hand",
            "🤚": "raised hand",
            "✊": "fist",
            "👊": "punch",
            "🤝": "handshake",
            "🙏": "folded hands",
            "💪": "muscle",
            "🦵": "leg",
            "🦶": "foot",
            "👣": "footprints",
            "👁️": "eye",
            "👅": "tongue",
            "👄": "lips",
            "🧠": "brain",
            "💇": "haircut",
            "💅": "nail polish",
            "🎮": "video game",
            "🎲": "dice",
            "🧩": "puzzle piece",
            "♟️": "chess pawn",
            "🎳": "bowling",
            "🏀": "basketball",
            "⚽": "soccer ball",
            "🏈": "football",
            "⚾": "baseball",
            "🎾": "tennis",
            "🏐": "volleyball",
            "🏓": "ping pong",
            "🏸": "badminton",
            "🥊": "boxing glove",
            "⛳": "golf",
            "🏌️": "golf swing",
            "🎣": "fishing",
            "🎿": "skiing",
            "⛷️": "skier",
            "🏂": "snowboarder",
            "🏄": "surfer",
            "🏊": "swimming",
            "🚴": "biking",
            "🚵": "mountain biking",
            "🎒": "backpack",
            "👓": "glasses",
            "👒": "hat",
            "🎩": "top hat",
            "👑": "crown",
            "👛": "purse",
            "👜": "handbag",
            "💰": "money bag",
            "💵": "dollar bill",
            "💴": "yen",
            "💶": "euro",
            "💷": "pound",
            "💸": "money with wings",
            "💳": "credit card",
            "🔮": "crystal ball",
            "🎱": "8 ball",
            "🧲": "magnet",
            "🔑": "key",
            "🗝️": "old key",
            "🚪": "door",
            "🛏️": "bed",
            "🛋️": "couch",
            "🚿": "shower",
            "🛁": "bathtub",
            "🚽": "toilet",
            "🧴": "lotion bottle",
            "🧷": "safety pin",
            "🧹": "broom",
            "🧺": "laundry basket",
            "🧻": "roll of paper",
            "🧽": "sponge",
            "🧯": "plunger",
            "🛒": "shopping cart",
            "🚗": "car",
            "🚕": "taxi",
            "🚙": "SUV",
            "🚌": "bus",
            "🚎": "trolleybus",
            "🏎️": "race car",
            "🚓": "police car",
            "🚑": "ambulance",
            "🚒": "fire truck",
            "🚐": "van",
            "🛻": "truck",
            "🚚": "delivery truck",
            "🚂": "steam engine",
            "🚆": "train",
            "🚇": "metro",
            "🚊": "tram",
            "🚝": "monorail",
            "🚄": "high speed train",
            "🚅": "bullet train",
            "✈️": "airplane",
            "🛫": "airplane departure",
            "🛬": "airplane arrival",
            "🚀": "rocket",
            "🛸": "flying saucer",
            "🚁": "helicopter",
            "⛵": "sailboat",
            "🚤": "speedboat",
            "🛳️": "cruise ship",
            "⛴️": "ferry",
            "🚢": "ship",
            "⚓": "anchor",
            "🗻": "mountain",
            "🏔️": "mountain",
            "🌋": "volcano",
            "🏕️": "camping",
            "⛺": "tent",
            "🏞️": "park",
            "🏜️": "desert island",
            "🏝️": "island",
            "🏖️": "beach",
            "🌅": "sunrise",
            "🌄": "sunrise over mountain",
            "🌃": "night",
            "🌉": "bridge at night",
            "🌌": "milky way",
            "🎡": "ferris wheel",
            "🎢": "roller coaster",
            "🎠": "carousel",
            "🏰": "castle",
            "🗼": "tower",
            "🗽": "statue of liberty",
            "⛪": "church",
            "⛩️": "shrine",
            "🕌": "mosque",
            "🕍": "synagogue",
            "🛕": "temple",
            "⛲": "fountain",
            "⛱": "umbrella",
            "💒": "wedding",
            "🎪": "circus",
            "🏟️": "stadium",
            "🎭": "performing arts",
            "🎨": "art",
            "🎬": "clapperboard",
            "🎤": "microphone",
            "🎧": "headphones",
            "🎼": "musical score",
            "🎹": "piano keys",
            "🎸": "guitar",
            "🎷": "saxophone",
            "🎺": "trumpet",
            "🎻": "violin",
            "🥁": "drum",
            "🏆": "trophy",
            "🥇": "gold medal",
            "🥈": "silver medal",
            "🥉": "bronze medal",
            "🏅": "medal",
            "🎖️": "military medal",
            "🏵️": "rosette",
            "🎗️": "ribbon",
            "🎫": "ticket",
            "🎟️": "admission ticket",
            "🎁": "gift",
            "🎀": "ribbon bow",
            "🔔": "bell",
            "🔕": "no bell",
            "📌": "pin",
            "📍": "location pin",
            "📎": "paperclip",
            "🖇️": "linked paperclips",
            "📏": "straight ruler",
            "📐": "triangular ruler",
            "✂️": "scissors",
            "🗑️": "wastebasket",
            "🔒": "locked",
            "🔓": "unlocked",
            "🔏": "locked with pen",
            "🔐": "locked with key",
            "🔎": "magnifying glass",
            "🔍": "magnifying glass left",
            "🔨": "hammer",
            "⛏️": "pick",
            "🪓": "axe",
            "🔧": "wrench",
            "🔩": "nut and bolt",
            "⚙️": "gear",
            "🗜️": "clamp",
            "⚖️": "scale",
            "🦯": "white cane",
            "⛓️": "chains",
            "🧰": "toolbox",
            "💉": "syringe",
            "🩸": "blood",
            "💊": "pill",
            "🩹": "adhesive bandage",
            "🩺": "stethoscope",
            "🧼": "soap",
            "🧸": "teddy bear",
            "🧵": "knitting",
            "🧶": "yarn",
            "🪡": "needle",
            "🪢": "knot",
            "🧮": "abacus",
            "🎰": "slot machine",
            "🧱": "lego brick",
            "🛠️": "hammer and wrench",
            "🗡️": "dagger",
            "⚔️": "crossed swords",
            "🕹️": "joystick"
        ]

        for (emoji, text) in emojiMap {
            result = result.replacingOccurrences(of: emoji, with: " \(text) ")
        }

        result = result.replacingOccurrences(of: "  ", with: " ")

        return result
    }

    private static func transformFractions(_ text: String) -> String {
        var result = text

        let fractionMap: [String: String] = [
            "½": " half ",
            "¼": " quarter ",
            "¾": " three quarters ",
            "⅓": " one third ",
            "⅔": " two thirds ",
            "⅛": " one eighth ",
            "⅜": " three eighths ",
            "⅝": " five eighths ",
            "⅞": " seven eighths ",
            "⅑": " one ninth ",
            "⅒": " one tenth ",
            "⅖": " two fifths ",
            "⅗": " three fifths ",
            "⅘": " four fifths ",
            "⅙": " one sixth ",
            "⅚": " five sixths "
        ]

        for (fraction, replacement) in fractionMap {
            result = result.replacingOccurrences(of: fraction, with: replacement)
        }

        return result
    }

    private static func transformMathExpressions(_ text: String) -> String {
        var result = text

        let mathReplacements: [(String, String)] = [
            ("\\frac{([^}]+)}{([^}]+)}", "$1 over $2"),
            ("\\sqrt{([^}]+)}", "square root of $1"),
            ("\\sqrt", "root"),
            ("\\sum", "sum"),
            ("\\int", "integral"),
            ("\\infty", "infinity"),
            ("\\pm", "plus or minus"),
            ("\\times", "times"),
            ("\\div", "divided by"),
            ("\\pi", "pi"),
            ("\\alpha", "alpha"),
            ("\\beta", "beta"),
            ("\\gamma", "gamma"),
            ("\\delta", "delta"),
            ("\\theta", "theta"),
            ("\\lambda", "lambda"),
            ("\\mu", "mu"),
            ("\\sigma", "sigma"),
            ("\\omega", "omega"),
            ("\\Delta", "delta"),
            ("\\Sigma", "sigma"),
            ("\\Omega", "omega"),
            ("\\vec{([^}]+)}", "vector $1"),
            ("\\hat{([^}]+)}", "hat $1"),
            ("\\bar{([^}]+)}", "bar $1"),
            ("\\dot{([^}]+)}", "dot $1"),
            ("\\ddot{([^}]+)}", "double dot $1"),
            ("x\\^2", "x squared"),
            ("x\\^3", "x cubed"),
            ("x\\^n", "x to the power of n"),
            ("x\\^{([^}]+)}", "x to the power of $1"),
            ("\\lim_{([^}]+)}", "limit as $1"),
            ("\\log_{([^}]+)}", "log base $1"),
            ("\\ln", "natural log"),
            ("\\sin", "sine"),
            ("\\cos", "cosine"),
            ("\\tan", "tangent"),
            ("\\cot", "cotangent"),
            ("\\sec", "secant"),
            ("\\csc", "cosecant"),
            ("\\arcsin", "arc sine"),
            ("\\arccos", "arc cosine"),
            ("\\arctan", "arc tangent")
        ]

        for (pattern, replacement) in mathReplacements {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: replacement)
            }
        }

        result = result.replacingOccurrences(of: "  ", with: " ")

        return result
    }

    private static func transformTime(_ text: String) -> String {
        var result = text

        if let regex = try? NSRegularExpression(pattern: "\\b(\\d{1,2}):(\\d{2})\\s*(AM|PM|am|pm)?\\b", options: []) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "$1 $2 $3")
        }

        if let regex = try? NSRegularExpression(pattern: "\\bAM\\b", options: [.caseInsensitive]) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "A M")
        }

        if let regex = try? NSRegularExpression(pattern: "\\bPM\\b", options: [.caseInsensitive]) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "P M")
        }

        return result
    }

    private static func transformPhoneNumbers(_ text: String) -> String {
        var result = text

        let phonePatterns = [
            "\\b(\\d{3})[-.](\\d{3})[-.](\\d{4})\\b": "$1 $2 $3",
            "\\b(\\d{3})\\s+(\\d{3})\\s+(\\d{4})\\b": "$1 $2 $3",
            "\\((\\d{3})\\)\\s*(\\d{3})[-.](\\d{4})": "$1 $2 $3",
            "\\+\\d{1,3}[\\s.-]?\\d{1,4}[\\s.-]?\\d{1,4}[\\s.-]?\\d{1,9}": " "
        ]

        for (pattern, replacement) in phonePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: replacement)
            }
        }

        return result
    }

    private static func transformKeyboardShortcuts(_ text: String) -> String {
        var result = text

        let shortcutReplacements: [(String, String)] = [
            ("⌘\\+C", "command C"),
            ("⌘\\+V", "command V"),
            ("⌘\\+X", "command X"),
            ("⌘\\+Z", "command Z"),
            ("⌘\\+A", "command A"),
            ("⌘\\+S", "command S"),
            ("⌘\\+F", "command F"),
            ("⌘\\+P", "command P"),
            ("⌘\\+Q", "command Q"),
            ("⌘\\+W", "command W"),
            ("⌘\\+N", "command N"),
            ("⌘\\+O", "command O"),
            ("⌘\\+R", "command R"),
            ("⌘\\+T", "command T"),
            ("⌘\\+\\+", "command plus"),
            ("⌘\\+=", "command equals"),
            ("⌘\\+-", "command minus"),
            ("⌘\\+0", "command zero"),
            ("⌘\\+1", "command 1"),
            ("⌘\\+2", "command 2"),
            ("⌘\\+3", "command 3"),
            ("⌘\\+4", "command 4"),
            ("⌘\\+5", "command 5"),
            ("⌘\\+6", "command 6"),
            ("⌘\\+7", "command 7"),
            ("⌘\\+8", "command 8"),
            ("⌘\\+9", "command 9"),
            ("Ctrl\\+C", "control C"),
            ("Ctrl\\+V", "control V"),
            ("Ctrl\\+X", "control X"),
            ("Ctrl\\+Z", "control Z"),
            ("Ctrl\\+A", "control A"),
            ("Ctrl\\+S", "control S"),
            ("Ctrl\\+F", "control F"),
            ("Ctrl\\+P", "control P"),
            ("Ctrl\\+Shift\\+Esc", "control shift escape"),
            ("Shift\\+Esc", "shift escape"),
            ("Alt\\+Tab", "alt tab"),
            ("Alt\\+F4", "alt F4"),
            ("Cmd\\+Opt\\+S", "command option S"),
            ("Ctrl\\+Shift\\+N", "control shift N"),
            ("Ctrl\\+Alt\\+Del", "control alt delete")
        ]

        for (pattern, replacement) in shortcutReplacements {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: replacement)
            }
        }

        return result
    }

    private static func transformMeasurements(_ text: String) -> String {
        var result = text

        let measurementPatterns: [(String, String)] = [
            ("(\\d+(?:\\.\\d+)?)\\s*px", "$1 pixels"),
            ("(\\d+(?:\\.\\d+)?)\\s*pt", "$1 points"),
            ("(\\d+(?:\\.\\d+)?)\\s*rem", "$1 root ems"),
            ("(\\d+(?:\\.\\d+)?)\\s*em", "$1 ems"),
            ("(\\d+(?:\\.\\d+)?)\\s*vw", "$1 viewport width"),
            ("(\\d+(?:\\.\\d+)?)\\s*vh", "$1 viewport height"),
            ("(\\d+(?:\\.\\d+)?)\\s*vmin", "$1 viewport minimum"),
            ("(\\d+(?:\\.\\d+)?)\\s*vmax", "$1 viewport maximum"),
            ("(\\d+(?:\\.\\d+)?)\\s*cm", "$1 centimeters"),
            ("(\\d+(?:\\.\\d+)?)\\s*mm", "$1 millimeters"),
            ("(\\d+(?:\\.\\d+)?)\\s*in", "$1 inches"),
            ("(\\d+(?:\\.\\d+)?)\\s*ft", "$1 feet"),
            ("(\\d+(?:\\.\\d+)?)\\s*km", "$1 kilometers"),
            ("(\\d+(?:\\.\\d+)?)\\s*m(?:\\b)", "$1 meters"),
            ("(\\d+(?:\\.\\d+)?)\\s*lb", "$1 pounds"),
            ("(\\d+(?:\\.\\d+)?)\\s*oz", "$1 ounces"),
            ("(\\d+(?:\\.\\d+)?)\\s*kg", "$1 kilograms"),
            ("(\\d+(?:\\.\\d+)?)\\s*g(?:\\b)", "$1 grams"),
            ("(\\d+(?:\\.\\d+)?)\\s*ml", "$1 milliliters"),
            ("(\\d+(?:\\.\\d+)?)\\s*l(?:\\b)", "$1 liters"),
            ("(\\d+(?:\\.\\d+)?)\\s*deg", "$1 degrees"),
            ("(\\d+(?:\\.\\d+)?)\\s*°C", "$1 degrees Celsius"),
            ("(\\d+(?:\\.\\d+)?)\\s*°F", "$1 degrees Fahrenheit"),
            ("(\\d+(?:\\.\\d+)?)\\s*%", "$1 percent")
        ]

        for (pattern, replacement) in measurementPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: replacement)
            }
        }

        return result
    }

    private static func transformSpecialLinks(_ text: String) -> String {
        var result = text

        let linkPatterns: [(String, String)] = [
            ("\\[\\^([^\\]]+)\\]", " "),
            ("\\{\\#fn[^}]+\\}", " "),
            ("\\[\\d+\\]", " "),
            ("\\[\\[([^\\]|]+)\\]\\]", "$1"),
            ("\\[\\[([^\\]|]+)\\|([^\\]]+)\\]\\]", "$2"),
            ("!?\\[\\[([^\\]]+)\\]\\]", "$1")
        ]

        for (pattern, replacement) in linkPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: replacement)
            }
        }

        result = result.replacingOccurrences(of: "  ", with: " ")

        return result
    }

    private static func transformVersionNumbers(_ text: String) -> String {
        let patterns = [
            "v\\d+(\\.\\d+)+",
            "V\\d+(\\.\\d+)+",
            "\\d+\\.\\d+\\.\\d+(\\.\\d+)*"
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(text.startIndex..., in: text)
                let matches = regex.matches(in: text, options: [], range: range).reversed()

                var modifiedText = text
                for match in matches {
                    guard let matchRange = Range(match.range, in: modifiedText) else { continue }
                    let original = String(modifiedText[matchRange])
                    let transformed = transformDotsToWords(original)
                    modifiedText.replaceSubrange(matchRange, with: transformed)
                }
                return modifiedText
            }
        }
        return text
    }

    private static func transformGFMNestedListNumbers(_ text: String) -> String {
        let pattern = "\\d+\\.\\d+\\.(\\s)?"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return text
        }

        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, options: [], range: range).reversed()

        var modifiedText = text
        for match in matches {
            guard let matchRange = Range(match.range, in: modifiedText) else { continue }
            let original = String(modifiedText[matchRange])

            var transformed = ""
            var digits = ""
            var inNumber = false
            var trailingSpace = ""

            for char in original {
                if char.isNumber {
                    digits.append(char)
                    inNumber = true
                } else if char == "." {
                    if inNumber && !digits.isEmpty {
                        if !transformed.isEmpty {
                            transformed += " point "
                        }
                        transformed += digits
                        digits = ""
                    }
                    inNumber = false
                } else if char == " " {
                    trailingSpace = " "
                } else {
                    transformed.append(char)
                }
            }

            if trailingSpace.isEmpty && transformed.hasSuffix(" point ") {
                transformed.removeLast(6)
                transformed += "."
            } else if !trailingSpace.isEmpty && transformed.hasSuffix(" point ") {
                transformed.removeLast(6)
                transformed += ". "
            }

            modifiedText.replaceSubrange(matchRange, with: transformed)
        }

        return modifiedText
    }

    private static func transformDecimalNumbers(_ text: String) -> String {
        let pattern = "(?<![a-zA-Z])(\\d+\\.\\d+)(?![a-zA-Z\\d])"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return text
        }

        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, options: [], range: range).reversed()

        var modifiedText = text
        for match in matches {
            guard let matchRange = Range(match.range, in: modifiedText),
                  let fullRange = Range(match.range(at: 1), in: modifiedText) else { continue }
            let original = String(modifiedText[fullRange])
            let transformed = transformSingleDecimalNumber(original)
            modifiedText.replaceSubrange(matchRange, with: transformed)
        }

        return modifiedText
    }

    private static func transformDotsToWords(_ text: String) -> String {
        var result = ""
        var currentNumber = ""

        for char in text {
            if char.isNumber {
                if !currentNumber.isEmpty && (char == "." || !currentNumber.contains(".")) == false {
                    if !result.isEmpty {
                        result += " point "
                    }
                    result += currentNumber
                    currentNumber = ""
                }
                currentNumber.append(char)
            } else if char == "." {
                if !currentNumber.isEmpty {
                    if !result.isEmpty {
                        result += " point "
                    }
                    result += currentNumber
                    currentNumber = ""
                }
            } else {
                if !currentNumber.isEmpty {
                    if !result.isEmpty {
                        result += " point "
                    }
                    result += currentNumber
                    currentNumber = ""
                }
                result.append(char)
            }
        }

        if !currentNumber.isEmpty {
            if !result.isEmpty {
                result += " point "
            }
            result += currentNumber
        }

        return result
    }

    private static func transformSingleDecimalNumber(_ text: String) -> String {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        if parts.count == 2 {
            return "\(parts[0]) point \(parts[1])"
        }
        return text
    }

    private static func transformSymbolsForTTS(_ text: String) -> String {
        var result = text

        let htmlEntities: [(String, String)] = [
            ("&amp;", " and "),
            ("&lt;", " less than "),
            ("&gt;", " greater than "),
            ("&quot;", "\""),
            ("&apos;", "'"),
            ("&nbsp;", " "),
            ("&copy;", " copyright "),
            ("&reg;", " registered trademark "),
            ("&trade;", " trademark "),
            ("&mdash;", " — "),
            ("&ndash;", " – "),
            ("&hellip;", "..."),
            ("&bull;", " • "),
            ("&middot;", " · "),
            ("&sect;", " section "),
            ("&para;", " paragraph "),
            ("&dagger;", " dagger "),
            ("&Dagger;", " double dagger "),
            ("&times;", " times "),
            ("&divide;", " divided by ")
        ]

        for (entity, replacement) in htmlEntities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }

        let symbolReplacements: [(String, String)] = [
            ("&", " and "),
            ("<=", " less than or equal to "),
            (">=", " greater than or equal to "),
            ("<", " less than "),
            (">", " greater than "),
            ("<=", " less than or equal to "),
            (">=", " greater than or equal to "),
            ("=", " equals "),
            ("==", " equals "),
            ("===", " equals "),
            ("!=", " not equal to "),
            ("!==", " not equal to "),
            ("±", " plus or minus "),
            ("×", " times "),
            ("÷", " divided by "),
            ("≠", " not equal to "),
            ("≤", " less than or equal to "),
            ("≥", " greater than or equal to "),
            ("∞", " infinity "),
            ("°", " degrees "),
            ("@", " at "),
            ("#", " number "),
            ("$", " dollar "),
            ("€", " euro "),
            ("£", " pound "),
            ("¥", " yen "),
            ("₹", " rupee "),
            ("©", " copyright "),
            ("®", " registered "),
            ("™", " trademark "),
            ("†", " dagger "),
            ("‡", " double dagger "),
            ("§", " section "),
            ("¶", " paragraph "),
            ("…", "..."),
            ("•", " • "),
            ("·", " · ")
        ]

        for (symbol, replacement) in symbolReplacements {
            result = result.replacingOccurrences(of: symbol, with: replacement)
        }

        result = result.replacingOccurrences(of: "+", with: " plus ")

        result = result.replacingOccurrences(of: "*", with: " times ")

        return result
    }

    private static func parseTables(_ text: String) -> String {
        var result = text
        let tablePattern = "\\|[^|]+\\|[\\r\\n]+(\\|[-: ]+\\|[\\r\\n]+)?(\\|[^|]+\\|[\\r\\n]*)+"

        guard let regex = try? NSRegularExpression(pattern: tablePattern, options: [.dotMatchesLineSeparators]) else {
            return result
        }

        let range = NSRange(result.startIndex..., in: result)
        let matches = regex.matches(in: result, options: [], range: range)

        for match in matches.reversed() {
            guard let matchRange = Range(match.range, in: result) else { continue }
            let tableBlock = String(result[matchRange])
            let readableTable = convertTableToReadableText(tableBlock)
            result.replaceSubrange(matchRange, with: readableTable)
        }

        return result
    }

    private static func convertTableToReadableText(_ table: String) -> String {
        let lines = table.components(separatedBy: CharacterSet.newlines).filter { !$0.isEmpty }
        guard lines.count >= 2 else { return table }

        var result: [String] = []
        var headerCells: [String] = []

        for (index, line) in lines.enumerated() {
            let cells = extractTableCells(line)

            if cells.isEmpty { continue }

            if index == 0 {
                headerCells = cells
                result.append(cells.joined(separator: ", ") + ".")
            } else if index == 1 && line.contains("---") {
                continue
            } else {
                var rowParts: [String] = []
                for (cellIndex, cell) in cells.enumerated() {
                    if cellIndex < headerCells.count {
                        rowParts.append("\(headerCells[cellIndex]): \(cell)")
                    } else {
                        rowParts.append(cell)
                    }
                }
                result.append(rowParts.joined(separator: ", ") + ".")
            }
        }

        return result.joined(separator: " ")
    }

    private static func extractTableCells(_ line: String) -> [String] {
        var cleaned = line
        if cleaned.hasPrefix("|") { cleaned = String(cleaned.dropFirst()) }
        if cleaned.hasSuffix("|") { cleaned = String(cleaned.dropLast()) }

        return cleaned.components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.contains("---") }
    }

    private static func endsWithNaturalTerminal(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if trimmed.hasSuffix("...") || trimmed.hasSuffix("……") {
            return true
        }

        for abbrev in sentenceLikeAbbreviations {
            if trimmed.hasSuffix(abbrev) {
                return false
            }
        }

        if let last = trimmed.unicodeScalars.last {
            return sentenceTerminals.contains(Character(last))
        }
        return false
    }

    private static func endsWithClauseBreak(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if let last = trimmed.unicodeScalars.last {
            return clauseBreaks.contains(Character(last))
        }
        return false
    }

    private static func endsMidSentence(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if endsWithNaturalTerminal(trimmed) { return false }
        if endsWithClauseBreak(trimmed) { return false }
        if let last = trimmed.unicodeScalars.last {
            if sentenceContinuityMarkers.contains(Character(last)) { return true }
        }
        return trimmed.count > maxSentenceLength
    }

    private static func shouldEndChunkAtSentence(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return endsWithNaturalTerminal(trimmed)
    }

    private static func computeAdaptiveMaxLength(for text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let wordCount = trimmed.split(separator: " ").count
        let avgWordLength = wordCount > 0 ? Double(trimmed.count) / Double(wordCount) : 5.0

        if avgWordLength > 8 {
            return max(180, maxSentenceLength - 40)
        }
        return maxSentenceLength
    }

    private static func addSentencePauseMarker(to chunk: String) -> String {
        let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return chunk }

        if endsMidSentence(trimmed) {
            if let last = trimmed.unicodeScalars.last, sentenceContinuityMarkers.contains(Character(last)) {
                return chunk + "."
            }
        }
        return chunk
    }

    private static func findBestSplitPoint(in text: String, maxLength: Int, maxOverflow: Int = maxOverflowLength) -> String.Index? {
        guard text.count > maxLength else { return nil }

        if let hyphenSplit = findHyphenatedCompoundInRange(text, maxLength: maxLength) {
            return hyphenSplit
        }

        func searchInRange(_ searchText: String, preferLater: Bool = false) -> String.Index? {
            if preferLater {
                for clause in englishClauseBreaks {
                    if let range = searchText.range(of: clause) {
                        let splitIndex = range.upperBound
                        if splitIndex != text.startIndex {
                            return splitIndex
                        }
                    }
                }
                for clause in chineseClauseBreaks {
                    if let range = searchText.range(of: clause) {
                        let splitIndex = range.upperBound
                        if splitIndex != text.startIndex {
                            return splitIndex
                        }
                    }
                }
            }

            for clause in englishClauseBreaks.reversed() {
                if let range = searchText.range(of: clause, options: .backwards) {
                    let splitIndex = range.upperBound
                    if splitIndex != text.startIndex {
                        return splitIndex
                    }
                }
            }

            for clause in chineseClauseBreaks.reversed() {
                if let range = searchText.range(of: clause, options: .backwards) {
                    let splitIndex = range.upperBound
                    if splitIndex != text.startIndex {
                        return splitIndex
                    }
                }
            }

            if let range = searchText.rangeOfCharacter(from: .whitespacesAndNewlines, options: .backwards) {
                return range.upperBound
            }

            return nil
        }

        let primarySearchRange = text.index(text.startIndex, offsetBy: maxLength)
        let primarySearchText = String(text[..<primarySearchRange])

        if let splitPoint = searchInRange(primarySearchText) {
            return splitPoint
        }

        let extendedLength = min(maxLength + maxOverflow, text.count)
        let extendedRange = text.index(text.startIndex, offsetBy: extendedLength)
        let extendedSearchText = String(text[..<extendedRange])

        return searchInRange(extendedSearchText, preferLater: true)
    }

    private static func safeHardSplit(_ text: String, at index: String.Index) -> (String, String) {
        let firstPart = String(text[..<index]).trimmingCharacters(in: .whitespacesAndNewlines)
        let secondPart = String(text[index...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (firstPart, secondPart)
    }

    static func smartSentenceSplit(sentence: String, maxLength: Int = maxSentenceLength, maxOverflow: Int = maxOverflowLength) -> [String] {
        let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        if trimmed.count <= maxLength {
            return [trimmed]
        }

        if trimmed.count <= maxLength + maxOverflow && endsWithNaturalTerminal(trimmed) {
            return [trimmed]
        }

        let linguisticSentences = linguisticSentenceSplit(trimmed)
        if linguisticSentences.count > 1 && linguisticSentences.count < 50 {
            var parts: [String] = []
            var currentPart = ""
            for sentenceChunk in linguisticSentences {
                let chunkLen = sentenceChunk.count
                if currentPart.isEmpty {
                    currentPart = sentenceChunk
                } else if currentPart.count + 1 + chunkLen <= maxLength + maxOverflow {
                    currentPart += " " + sentenceChunk
                } else {
                    if currentPart.count > maxLength {
                        let subParts = smartSentenceSplitRecursive(sentence: currentPart, maxLength: maxLength, maxOverflow: maxOverflow)
                        parts.append(contentsOf: subParts.dropLast())
                        currentPart = subParts.last ?? currentPart
                    } else {
                        parts.append(currentPart)
                        currentPart = sentenceChunk
                    }
                }
            }
            if !currentPart.isEmpty {
                if currentPart.count > maxLength {
                    let subParts = smartSentenceSplitRecursive(sentence: currentPart, maxLength: maxLength, maxOverflow: maxOverflow)
                    parts.append(contentsOf: subParts)
                } else {
                    parts.append(currentPart)
                }
            }
            return parts.filter { !$0.isEmpty }
        }

        return smartSentenceSplitRecursive(sentence: trimmed, maxLength: maxLength, maxOverflow: maxOverflow)
    }

    private static func smartSentenceSplitRecursive(sentence: String, maxLength: Int, maxOverflow: Int) -> [String] {
        let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        if trimmed.count <= maxLength {
            return [trimmed]
        }

        if trimmed.count <= maxLength + maxOverflow && endsWithNaturalTerminal(trimmed) {
            return [trimmed]
        }

        var parts: [String] = []
        var remaining = trimmed

        while remaining.count > maxLength {
            if remaining.count <= maxLength + maxOverflow && endsWithNaturalTerminal(remaining) {
                parts.append(remaining)
                remaining = ""
                break
            }

            if let terminalIndex = findNaturalTerminalInRange(remaining, maxLength: maxLength, tolerance: 50) {
                let (first, second) = safeHardSplit(remaining, at: terminalIndex)
                if !first.isEmpty {
                    parts.append(first)
                }
                remaining = second
                continue
            }

            if let ellipsisIndex = findEllipsisBreak(in: remaining, maxLength: maxLength) {
                let (first, second) = safeHardSplit(remaining, at: ellipsisIndex)
                if !first.isEmpty {
                    parts.append(first)
                }
                remaining = second
                continue
            }

            if let splitPoint = findBestSplitPoint(in: remaining, maxLength: maxLength, maxOverflow: maxOverflow) {
                let (first, second) = safeHardSplit(remaining, at: splitPoint)
                if !first.isEmpty {
                    parts.append(first)
                }
                remaining = second
            } else {
                let hardLimit = findWordBoundaryHardSplit(remaining, maxLength: maxLength)
                let firstPart = String(remaining[..<hardLimit]).trimmingCharacters(in: .whitespaces)
                if !firstPart.isEmpty {
                    parts.append(firstPart)
                    logHardSplit(text: remaining, chunk: firstPart, reason: "forced_hard_split")
                }
                remaining = String(remaining[hardLimit...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        if !remaining.isEmpty {
            parts.append(remaining)
        }

        return parts.filter { !$0.isEmpty }
    }

    private static func isContraction(_ word: String) -> Bool {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let contractions = [
            "don't", "didn't", "doesn't", "can't", "couldn't", "won't", "wouldn't",
            "shouldn't", "isn't", "aren't", "wasn't", "weren't", "haven't", "hasn't",
            "hadn't", "i'm", "you're", "he's", "she's", "it's", "we're", "they're",
            "i've", "you've", "we've", "they've", "i'll", "you'll", "he'll", "she'll",
            "it'll", "we'll", "they'll", "i'd", "you'd", "he'd", "she'd", "we'd",
            "they'd", "let's", "that's", "what's", "here's", "there's", "who's",
            "ain't", "gonna", "wanna", "gotta", "kinda", "sorta", "outta", "gimme",
            "lemme", "betcha", "whatcha", "dunno", "y'all", "ma'am", "o'clock"
        ]
        return contractions.contains(trimmed) || (trimmed.hasSuffix("'s") && trimmed.count <= 5)
    }

    private static func isInContraction(_ text: String, at index: String.Index) -> Bool {
        let beforeIndex = text.index(index, offsetBy: -1, limitedBy: text.startIndex)
        guard let bi = beforeIndex else { return false }

        if text[bi] == "'" {
            var wordStart = bi
            while wordStart > text.startIndex {
                let prev = text.index(before: wordStart)
                if text[prev].isLetter {
                    wordStart = prev
                } else {
                    break
                }
            }
            let afterIndex = text.index(index, offsetBy: 1, limitedBy: text.endIndex) ?? index
            let wordRange = wordStart..<afterIndex
            let word = String(text[wordRange])
            return isContraction(word)
        }

        return false
    }

    private static func findWordBoundaryHardSplit(_ text: String, maxLength: Int) -> String.Index {
        let searchLimit = min(maxLength + 20, text.count)
        let searchEnd = text.index(text.startIndex, offsetBy: searchLimit)

        if let wsRange = text[..<searchEnd].rangeOfCharacter(from: .whitespacesAndNewlines, options: .backwards) {
            let wsIndex = wsRange.lowerBound
            let distFromStart = text.distance(from: text.startIndex, to: wsIndex)

            if distFromStart >= maxLength - 30 {
                if isInContraction(text, at: wsIndex) {
                    if let earlierWs = text[..<wsIndex].rangeOfCharacter(from: .whitespacesAndNewlines, options: .backwards) {
                        return earlierWs.upperBound
                    }
                }
                return wsIndex
            }
        }

        let hardIndex = text.index(text.startIndex, offsetBy: maxLength)
        if isInContraction(text, at: hardIndex) {
            let beforeIndex = text.index(hardIndex, offsetBy: -1, limitedBy: text.startIndex) ?? text.startIndex
            if let earlierWs = text[..<beforeIndex].rangeOfCharacter(from: .whitespacesAndNewlines, options: .backwards) {
                return earlierWs.upperBound
            }
        }

        return hardIndex
    }

    private static func findURLBoundaryInRange(_ text: String, maxLength: Int) -> String.Index? {
        guard text.count > maxLength else { return nil }
        let searchRange = text.index(text.startIndex, offsetBy: maxLength)
        let searchText = String(text[..<searchRange])

        let urlPatterns = [
            "https://", "http://", "www.", "ftp://", "file://",
            "mailto:", "tel:", "smsto:", "app://"
        ]

        for pattern in urlPatterns {
            if let range = searchText.range(of: pattern) {
                let urlStart = range.lowerBound
                if let endRange = searchText[urlStart...].range(of: "[\\s\\)\\]\"']", options: .regularExpression) {
                    return endRange.upperBound
                }
                if let endRange = searchText[urlStart...].rangeOfCharacter(from: .whitespacesAndNewlines) {
                    return endRange.lowerBound
                }
            }
        }

        let pathPatterns = ["/", "\\"]
        for pathPattern in pathPatterns {
            if let range = searchText.range(of: pathPattern, options: .regularExpression) {
                var lastMatch = range
                while let nextRange = searchText[lastMatch.upperBound...].range(of: pathPattern, options: .regularExpression) {
                    lastMatch = nextRange
                }
                let endOfPathSearch = text.index(lastMatch.upperBound, offsetBy: 50, limitedBy: text.endIndex) ?? text.endIndex
                if let wsRange = text[lastMatch.upperBound..<endOfPathSearch].rangeOfCharacter(from: .whitespacesAndNewlines) {
                    return wsRange.lowerBound
                }
            }
        }

        return nil
    }

    private static func findHyphenatedCompoundInRange(_ text: String, maxLength: Int) -> String.Index? {
        guard text.count > maxLength else { return nil }
        let searchRange = text.index(text.startIndex, offsetBy: maxLength)
        let searchText = String(text[..<searchRange])

        if let hyphenRange = searchText.range(of: "-", options: .backwards) {
            let hyphenIndex = hyphenRange.lowerBound
            if text.distance(from: text.startIndex, to: hyphenIndex) >= maxLength - 30 {
                if hyphenIndex > text.startIndex {
                    let charBefore = text[text.index(before: hyphenIndex)]
                    let charAfter = text[hyphenRange.upperBound]
                    if charBefore.isLetter && charAfter.isLetter {
                        if let wsBefore = text[..<hyphenIndex].rangeOfCharacter(from: .whitespacesAndNewlines, options: .backwards) {
                            return wsBefore.upperBound
                        }
                    }
                }
            }
        }

        return nil
    }

    private static func shouldSplitAtPeriod(_ text: String, index: String.Index) -> Bool {
        let periodString = String(text[index...].prefix(10))

        let beforeIndex = text.index(index, offsetBy: -1, limitedBy: text.startIndex) ?? text.startIndex
        guard beforeIndex != index else { return true }
        let charBefore = text[beforeIndex]

        if charBefore.isNumber { return false }

        if let prevIndex = text.index(index, offsetBy: -1, limitedBy: text.startIndex), prevIndex != index {
            let charTwoBefore = text[prevIndex]
            if charTwoBefore.isNumber {
                let afterPeriod = String(periodString.dropFirst()).trimmingCharacters(in: .whitespaces)
                if let firstChar = afterPeriod.first, firstChar.isNumber || firstChar == "." || firstChar == "," {
                    return false
                }
            }
        }

        let contextBefore = text[..<index]
        if isGFMNestedListPattern(text: String(contextBefore)) {
            return false
        }

        for abbrev in sentenceLikeAbbreviations {
            if periodString.hasPrefix(abbrev) {
                return false
            }
        }

        let pathPatterns: [Character] = ["/", "\\", ":"]
        if pathPatterns.contains(charBefore) { return false }

        return true
    }

    private static func isGFMNestedListPattern(text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let nestedListPattern = try? NSRegularExpression(pattern: "\\d+\\.\\d+\\.$", options: [])
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        return nestedListPattern?.firstMatch(in: trimmed, options: [], range: range) != nil
    }

    private static func findEllipsisBreak(in text: String, maxLength: Int) -> String.Index? {
        guard text.count > maxLength else { return nil }
        let searchRange = text.index(text.startIndex, offsetBy: maxLength)
        let searchText = String(text[..<searchRange])

        if let range = searchText.range(of: "...", options: .backwards) {
            return range.upperBound
        }
        if let range = searchText.range(of: "……", options: .backwards) {
            return range.upperBound
        }
        return nil
    }

    private static func findNaturalTerminalInRange(_ text: String, maxLength: Int, tolerance: Int = 25) -> String.Index? {
        let effectiveMax = min(maxLength + tolerance, text.count)
        let searchText = String(text.prefix(effectiveMax))

        if let urlSplit = findURLBoundaryInRange(text, maxLength: maxLength) {
            if text.distance(from: text.startIndex, to: urlSplit) <= effectiveMax {
                return urlSplit
            }
        }

        let terminals: [(String, String)] = [
            (". ", ". "), ("! ", "! "), ("? ", "? "),
            ("。", "。"), ("！", "！"), ("？", "？"),
            ("…", "…"), ("……", "……")
        ]

        for (terminal, _) in terminals {
            if let range = searchText.range(of: terminal, options: .backwards) {
                let splitIndex = range.upperBound
                if splitIndex != text.startIndex && splitIndex != text.endIndex {
                    if terminal == ". " || terminal == "! " || terminal == "? " {
                        let periodIndex = range.lowerBound
                        if shouldSplitAtPeriod(text, index: periodIndex) {
                            return splitIndex
                        }
                    } else {
                        return splitIndex
                    }
                }
            }
        }

        for (terminal, _) in terminals {
            if let range = searchText.range(of: terminal, options: .backwards) {
                let splitIndex = range.upperBound
                if splitIndex != text.startIndex && splitIndex != text.endIndex {
                    if terminal.contains(".") {
                        let periodIndex = text.index(range.lowerBound, offsetBy: terminal.first == "." ? 0 : 0)
                        if shouldSplitAtPeriod(text, index: periodIndex) {
                            return splitIndex
                        }
                    } else {
                        return splitIndex
                    }
                }
            }
        }

        return nil
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

    static func computeTTSChunks(from text: String, isChinese: Bool) -> [String] {
        let rawBlocks = splitByGFMStructure(text)
        var chunks: [String] = []
        var currentChunk = ""

        for block in rawBlocks {
            let cleaned = cleanMarkdownPreserveNewlines(block)
            let transformed = transformProblematicPatternsForTTS(cleaned)
            let lines = transformed.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }

                let blockLength = trimmed.count

                if blockLength > maxChunkLength {
                    if !currentChunk.isEmpty && currentChunk.count >= minChunkLength {
                        chunks.append(currentChunk)
                        currentChunk = ""
                    }

                    let subChunks = smartSentenceSplit(sentence: trimmed, maxLength: maxSentenceLength, maxOverflow: maxOverflowLength)
                    for subChunk in subChunks {
                        let subTrimmed = subChunk.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !subTrimmed.isEmpty else { continue }

                        if currentChunk.isEmpty {
                            currentChunk = subTrimmed
                        } else if currentChunk.count + 1 + subTrimmed.count <= maxChunkLength {
                            currentChunk += " ... " + subTrimmed
                        } else {
                            if currentChunk.count >= minChunkLength {
                                chunks.append(currentChunk)
                            }
                            currentChunk = subTrimmed
                        }
                    }
                } else if currentChunk.isEmpty {
                    currentChunk = trimmed
                } else if currentChunk.count + 3 + blockLength <= maxChunkLength {
                    currentChunk += " ... " + trimmed
                } else {
                    if currentChunk.count >= minChunkLength {
                        chunks.append(currentChunk)
                    }
                    currentChunk = trimmed
                }
            }
        }

        if currentChunk.count >= minChunkLength {
            chunks.append(currentChunk)
        }

        return chunks.filter { !$0.isEmpty }
    }

    private static func cleanMarkdownPreserveNewlines(_ text: String) -> String {
        var s = text

        if let regex = try? NSRegularExpression(pattern: "```[\\s\\S]*?```", options: []) {
            s = regex.stringByReplacingMatches(in: s, options: [], range: NSRange(s.startIndex..., in: s), withTemplate: " ")
        }

        if let regex = try? NSRegularExpression(pattern: "`([^`]+)`", options: []) {
            s = regex.stringByReplacingMatches(in: s, options: [], range: NSRange(s.startIndex..., in: s), withTemplate: "$1")
        }

        s = parseTables(s)

        let replacements: [(String, String, NSRegularExpression.Options)] = [
            ("!\\[[^\\]]*\\]\\([^)]*\\)", "", []),
            ("^#{1,6}\\s+", "", [.anchorsMatchLines]),
            ("^[-*_]{3,}$", "", [.anchorsMatchLines]),
            ("\\*\\*(.*?)\\*\\*", "$1", []),
            ("__(.*?)__", "$1", []),
            ("\\*(.*?)\\*", "$1", []),
            ("_(.*?)_", "$1", []),
            ("^\\s*>\\s+", "Quote: ", [.anchorsMatchLines]),
            ("- \\[ \\]", "○", []),
            ("- \\[x\\]", "✓", [.caseInsensitive])
        ]

        for (pattern, replacement, options) in replacements {
            if let regex = try? NSRegularExpression(pattern: pattern, options: options) {
                s = regex.stringByReplacingMatches(in: s, options: [], range: NSRange(s.startIndex..., in: s), withTemplate: replacement)
            }
        }

        if let regex = try? NSRegularExpression(pattern: "\\[([^\\]]+)\\]\\([^)]*\\)", options: []) {
            s = regex.stringByReplacingMatches(in: s, options: [], range: NSRange(s.startIndex..., in: s), withTemplate: "$1")
        }

        return s
    }

    private static func splitByGFMStructure(_ text: String) -> [String] {
        var blocks: [String] = []
        let lines = text.components(separatedBy: "\n")
        var currentBlock = ""
        var inCodeBlock = false
        var codeBlockContent = ""

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            if trimmedLine.hasPrefix("```") {
                if inCodeBlock {
                    codeBlockContent += "\n" + line
                    blocks.append(codeBlockContent)
                    codeBlockContent = ""
                    inCodeBlock = false
                } else {
                    if !currentBlock.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        blocks.append(currentBlock)
                    }
                    currentBlock = ""
                    codeBlockContent = line
                    inCodeBlock = true
                }
            } else if inCodeBlock {
                codeBlockContent += "\n" + line
            } else if trimmedLine.isEmpty {
                if !currentBlock.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    blocks.append(currentBlock)
                }
                currentBlock = ""
            } else if isHeadingLine(trimmedLine) || isListItemLine(trimmedLine) || isBlockQuoteLine(trimmedLine) {
                if !currentBlock.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    blocks.append(currentBlock)
                }
                currentBlock = line
            } else {
                if currentBlock.isEmpty {
                    currentBlock = line
                } else {
                    currentBlock += "\n" + line
                }
            }
        }

        if inCodeBlock && !codeBlockContent.isEmpty {
            blocks.append(codeBlockContent)
        }

        if !currentBlock.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            blocks.append(currentBlock)
        }

        return blocks.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private static func isHeadingLine(_ line: String) -> Bool {
        return line.hasPrefix("#")
    }

    private static func isListItemLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
            return true
        }
        let pattern = "^\\d+\\.\\s"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let range = NSRange(trimmed.startIndex..., in: trimmed)
            return regex.firstMatch(in: trimmed, options: [], range: range) != nil
        }
        return false
    }

    private static func isBlockQuoteLine(_ line: String) -> Bool {
        return line.trimmingCharacters(in: .whitespaces).hasPrefix(">")
    }

    enum TTSBlock: Identifiable {
        case heading(level: Int, text: String)
        case paragraph(text: String)
        case table(header: [String], rows: [[String]])
        case unorderedList(items: [String])
        case orderedList(items: [String])
        case blockQuote(text: String)
        case codeBlock(language: String, code: String)
        case thematicBreak
        case htmlBlock(html: String)

        var id: String {
            switch self {
            case .heading(let level, let text): return "h\(level)-\(text.hashValue)"
            case .paragraph(let text): return "p-\(text.hashValue)"
            case .table(let header, let rows): return "t-\(header.hashValue)-\(rows.hashValue)"
            case .unorderedList(let items): return "ul-\(items.hashValue)"
            case .orderedList(let items): return "ol-\(items.hashValue)"
            case .blockQuote(let text): return "bq-\(text.hashValue)"
            case .codeBlock(let lang, let code): return "code-\(lang)-\(code.hashValue)"
            case .thematicBreak: return "hr"
            case .htmlBlock(let html): return "html-\(html.hashValue)"
            }
        }

        var ttsText: String {
            switch self {
            case .heading(let level, let text):
                let prefix: String
                switch level {
                case 1: prefix = "Heading: "
                case 2: prefix = "Section: "
                case 3: prefix = "Subsection: "
                default: prefix = ""
                }
                return prefix + text

            case .paragraph(let text):
                return text

            case .table(let header, let rows):
                var result = "Table."
                if !header.isEmpty {
                    result += " Columns: \(header.joined(separator: ", "))."
                }
                for (index, row) in rows.enumerated() {
                    var rowParts: [String] = []
                    for (colIndex, cell) in row.enumerated() {
                        if colIndex < header.count {
                            rowParts.append("\(header[colIndex]): \(cell)")
                        } else {
                            rowParts.append(cell)
                        }
                    }
                    result += " Row \(index + 1): \(rowParts.joined(separator: ", "))."
                }
                return result

            case .unorderedList(let items):
                return items.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: " ")

            case .orderedList(let items):
                return items.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: " ")

            case .blockQuote(let text):
                return "Quote: \(text)"

            case .codeBlock(_, let code):
                return "Code block: \(code)"

            case .thematicBreak:
                return "---"

            case .htmlBlock(let html):
                return html
            }
        }

        var isAtomic: Bool {
            switch self {
            case .table, .codeBlock, .blockQuote, .thematicBreak, .htmlBlock:
                return true
            case .heading, .paragraph, .unorderedList, .orderedList:
                return false
            }
        }
    }

    static func parseMarkdownIntoBlocks(_ markdown: String) -> [TTSBlock] {
        let document = Document(parsing: markdown, options: [.parseBlockDirectives, .parseSymbolLinks])
        var parser = TTSBlockParser()
        return parser.parse(document)
    }

    static func parseMarkdownForTTS(_ markdown: String) -> String {
        let blocks = parseMarkdownIntoBlocks(markdown)
        return blocks.map { $0.ttsText }.filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static func chunkBlocks(_ blocks: [TTSBlock], isChinese: Bool) -> [String] {
        var chunks: [String] = []
        var currentChunk = ""

        for block in blocks {
            let blockText = block.ttsText
            guard !blockText.isEmpty else { continue }
            let blockLength = blockText.count

            if block.isAtomic {
                if currentChunk.isEmpty {
                    currentChunk = blockText
                    chunks.append(currentChunk)
                    currentChunk = ""
                } else if currentChunk.count + blockLength + 1 <= maxChunkLength {
                    currentChunk += " " + blockText
                    chunks.append(currentChunk)
                    currentChunk = ""
                } else {
                    if !currentChunk.isEmpty {
                        chunks.append(currentChunk)
                    }
                    currentChunk = ""
                    chunks.append(blockText)
                    currentChunk = ""
                }
                continue
            }

            if blockLength > 500 {
                if currentChunk.count >= minChunkLength {
                    chunks.append(currentChunk)
                }
                currentChunk = ""
                let adaptiveMax = computeAdaptiveMaxLength(for: blockText)
                let subChunks = smartSentenceSplit(sentence: blockText, maxLength: adaptiveMax, maxOverflow: maxOverflowLength)

                for subChunk in subChunks {
                    let effectiveMaxChunk = shouldEndChunkAtSentence(subChunk)
                        ? maxChunkLength + sentenceBoundaryOverflow
                        : maxChunkLength

                    if subChunk.count <= effectiveMaxChunk {
                        if currentChunk.isEmpty {
                            currentChunk = subChunk
                        } else if currentChunk.count + subChunk.count + 1 <= effectiveMaxChunk {
                            currentChunk += " " + subChunk
                        } else {
                            if currentChunk.count >= minChunkLength {
                                let markedChunk = addSentencePauseMarker(to: currentChunk)
                                chunks.append(markedChunk)
                            }
                            currentChunk = subChunk
                        }
                    }
                }
                continue
            }

            if currentChunk.isEmpty {
                currentChunk = blockText
            } else if currentChunk.count + blockLength + 1 <= maxChunkLength {
                currentChunk += " " + blockText
            } else {
                if currentChunk.count >= minChunkLength {
                    let markedChunk = addSentencePauseMarker(to: currentChunk)
                    chunks.append(markedChunk)
                }
                currentChunk = blockText
            }
        }

        if currentChunk.count >= minChunkLength {
            let markedChunk = addSentencePauseMarker(to: currentChunk)
            chunks.append(markedChunk)
        }

        return chunks.filter { !$0.isEmpty }
    }

    private class TTSBlockParser {
        private var blocks: [TTSBlock] = []
        private var listItemCounters: [Int] = []

        func parse(_ document: Document) -> [TTSBlock] {
            blocks = []
            walk(document)
            return blocks
        }

        private func walk(_ markup: Markup) {
            switch markup {
            case let paragraph as Paragraph:
                let text = extractText(from: paragraph)
                if !text.isEmpty {
                    blocks.append(.paragraph(text: text))
                }

            case let heading as Heading:
                let text = extractText(from: heading)
                if !text.isEmpty {
                    blocks.append(.heading(level: heading.level, text: text))
                }

            case is ThematicBreak:
                blocks.append(.thematicBreak)

            case let codeBlock as CodeBlock:
                blocks.append(.codeBlock(language: codeBlock.language ?? "", code: codeBlock.code))

            case let blockQuote as BlockQuote:
                let text = extractText(from: blockQuote)
                if !text.isEmpty {
                    blocks.append(.blockQuote(text: text))
                }

            case let unorderedList as UnorderedList:
                var items: [String] = []
                for child in unorderedList.children {
                    if let listItem = child as? ListItem {
                        let itemText = extractText(from: listItem)
                        var prefix = ""
                        if let checkbox = listItem.checkbox {
                            switch checkbox {
                            case .checked: prefix = "[Done] "
                            case .unchecked: prefix = "[Todo] "
                            @unknown default: break
                            }
                        }
                        items.append("\(prefix)\(itemText)")
                    }
                }
                if !items.isEmpty {
                    blocks.append(.unorderedList(items: items))
                }

            case let orderedList as OrderedList:
                listItemCounters.append(0)
                var items: [String] = []
                for child in orderedList.children {
                    if let listItem = child as? ListItem {
                        listItemCounters[listItemCounters.count - 1] += 1
                        let counter = listItemCounters[listItemCounters.count - 1]
                        let itemText = extractText(from: listItem)
                        items.append("\(counter). \(itemText)")
                    }
                }
                listItemCounters.removeLast()
                if !items.isEmpty {
                    blocks.append(.orderedList(items: items))
                }

            case let table as Table:
                parseTable(table)

            case let htmlBlock as HTMLBlock:
                blocks.append(.htmlBlock(html: htmlBlock.rawHTML))

            case is Document:
                for child in markup.children {
                    walk(child)
                }

            default:
                if markup.childCount > 0 {
                    for child in markup.children {
                        walk(child)
                    }
                }
            }
        }

        private func parseTable(_ table: Table) {
            var columnNames: [String] = []
            var rows: [[String]] = []

            for child in table.children {
                if let head = child as? Table.Head {
                    columnNames = head.cells.map { self.extractText(from: $0) }
                } else if let row = child as? Table.Row {
                    let rowValues = row.cells.map { self.extractText(from: $0) }
                    rows.append(Array(rowValues))
                }
            }

            if !columnNames.isEmpty || !rows.isEmpty {
                blocks.append(.table(header: columnNames, rows: rows))
            }
        }

        private func extractText(from markup: Markup) -> String {
            var result = ""
            for child in markup.children {
                result += renderInline(child)
            }
            return result.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private func renderInline(_ markup: Markup) -> String {
            switch markup {
            case let text as Markdown.Text:
                return text.string
            case let emph as Emphasis:
                return emph.children.map { renderInline($0) }.joined()
            case let strong as Strong:
                return strong.children.map { renderInline($0) }.joined()
            case is Strikethrough:
                return markup.children.map { renderInline($0) }.joined()
            case let inlineCode as InlineCode:
                return inlineCode.code
            case let link as Link:
                return link.children.map { renderInline($0) }.joined()
            case is SoftBreak:
                return " "
            case is LineBreak:
                return "\n"
            case let inlineHTML as InlineHTML:
                return inlineHTML.rawHTML
            default:
                return markup.plainText
            }
        }
    }
}
