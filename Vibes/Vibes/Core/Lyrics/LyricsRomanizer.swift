import Foundation

/// Romanizes lyrics in Japanese, Korean, and Cyrillic scripts
class LyricsRomanizer {

    /// Romanize text if it contains Japanese, Korean, or Cyrillic characters
    static func romanize(_ text: String) -> String? {
        // Detect script type
        if containsJapanese(text) {
            return romanizeJapanese(text)
        } else if containsKorean(text) {
            return romanizeKorean(text)
        } else if containsCyrillic(text) {
            return romanizeCyrillic(text)
        }
        return nil  // No romanization needed
    }

    // MARK: - Script Detection

    private static func containsJapanese(_ text: String) -> Bool {
        // Check for Hiragana (3040-309F), Katakana (30A0-30FF), or Kanji (4E00-9FAF)
        let japaneseRange = /[\u{3040}-\u{309F}\u{30A0}-\u{30FF}\u{4E00}-\u{9FAF}]/
        return text.contains(japaneseRange)
    }

    private static func containsKorean(_ text: String) -> Bool {
        // Check for Hangul syllables (AC00-D7AF) or Jamo (1100-11FF)
        let koreanRange = /[\u{AC00}-\u{D7AF}\u{1100}-\u{11FF}]/
        return text.contains(koreanRange)
    }

    private static func containsCyrillic(_ text: String) -> Bool {
        // Check for Cyrillic block (0400-04FF)
        let cyrillicRange = /[\u{0400}-\u{04FF}]/
        return text.contains(cyrillicRange)
    }

    // MARK: - Japanese Romanization

    private static func romanizeJapanese(_ text: String) -> String {
        // Use CFStringTransform for Hiragana/Katakana to Romaji
        // This is built into iOS and handles most cases well
        let mutableString = NSMutableString(string: text)
        CFStringTransform(mutableString, nil, kCFStringTransformHiraganaKatakana, false)
        CFStringTransform(mutableString, nil, kCFStringTransformLatinHiragana, false)

        return mutableString as String
    }

    // MARK: - Korean Romanization

    private static func romanizeKorean(_ text: String) -> String {
        // Revised Romanization of Korean (국어의 로마자 표기법)
        var result = ""

        for char in text {
            if let scalar = char.unicodeScalars.first,
               scalar.value >= 0xAC00 && scalar.value <= 0xD7AF {
                // Hangul syllable - decompose and romanize
                result += romanizeHangulSyllable(scalar)
            } else {
                result.append(char)
            }
        }

        return result
    }

    private static func romanizeHangulSyllable(_ scalar: UnicodeScalar) -> String {
        // Hangul syllable decomposition formula
        let syllableBase: UInt32 = 0xAC00
        let initialBase: UInt32 = 0x1100
        let medialBase: UInt32 = 0x1161

        let syllableIndex = scalar.value - syllableBase
        let initialIndex = syllableIndex / 588
        let medialIndex = (syllableIndex % 588) / 28
        let finalIndex = syllableIndex % 28

        // Romanization tables (Revised Romanization)
        let initials = ["g", "kk", "n", "d", "tt", "r", "m", "b", "pp", "s", "ss", "", "j", "jj", "ch", "k", "t", "p", "h"]
        let medials = ["a", "ae", "ya", "yae", "eo", "e", "yeo", "ye", "o", "wa", "wae", "oe", "yo", "u", "wo", "we", "wi", "yu", "eu", "ui", "i"]
        let finals = ["", "g", "kk", "gs", "n", "nj", "nh", "d", "l", "lg", "lm", "lb", "ls", "lt", "lp", "lh", "m", "b", "bs", "s", "ss", "ng", "j", "ch", "k", "t", "p", "h"]

        let initial = initials[Int(initialIndex)]
        let medial = medials[Int(medialIndex)]
        let final = finals[Int(finalIndex)]

        return initial + medial + final
    }

    // MARK: - Cyrillic Romanization

    private static func romanizeCyrillic(_ text: String) -> String {
        // ISO 9 / GOST 7.79 transliteration (covers Russian, Ukrainian, Serbian, etc.)
        let cyrillicMap: [Character: String] = [
            // Russian uppercase
            "А": "A", "Б": "B", "В": "V", "Г": "G", "Д": "D", "Е": "E", "Ё": "Yo", "Ж": "Zh",
            "З": "Z", "И": "I", "Й": "Y", "К": "K", "Л": "L", "М": "M", "Н": "N", "О": "O",
            "П": "P", "Р": "R", "С": "S", "Т": "T", "У": "U", "Ф": "F", "Х": "Kh", "Ц": "Ts",
            "Ч": "Ch", "Ш": "Sh", "Щ": "Shch", "Ъ": "", "Ы": "Y", "Ь": "", "Э": "E", "Ю": "Yu", "Я": "Ya",

            // Russian lowercase
            "а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "е": "e", "ё": "yo", "ж": "zh",
            "з": "z", "и": "i", "й": "y", "к": "k", "л": "l", "м": "m", "н": "n", "о": "o",
            "п": "p", "р": "r", "с": "s", "т": "t", "у": "u", "ф": "f", "х": "kh", "ц": "ts",
            "ч": "ch", "ш": "sh", "щ": "shch", "ъ": "", "ы": "y", "ь": "", "э": "e", "ю": "yu", "я": "ya",

            // Ukrainian specific
            "Є": "Ye", "І": "I", "Ї": "Yi", "Ґ": "G",
            "є": "ye", "і": "i", "ї": "yi", "ґ": "g",

            // Serbian specific (Cyrillic)
            "Ђ": "Đ", "Ј": "J", "Љ": "Lj", "Њ": "Nj", "Ћ": "Ć", "Џ": "Dž",
            "ђ": "đ", "ј": "j", "љ": "lj", "њ": "nj", "ћ": "ć", "џ": "dž"
        ]

        var result = ""
        for char in text {
            if let romanized = cyrillicMap[char] {
                result += romanized
            } else {
                result.append(char)
            }
        }

        return result
    }
}
