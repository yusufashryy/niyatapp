import Foundation

/// Compares words heard by the speech recogniser with the words of the Qur'an
/// text. Pure logic, no audio, so it's fully unit-tested. Only ever used for
/// comparing: the recognition forms made here are never displayed.
enum RecitationMatcher {
    /// Letters only, with the spelling differences between Qur'anic and modern
    /// Arabic folded together (alef forms, hamza seats, ta marbuta, alef maqsura).
    /// The dagger alif of the Uthmani script counts as an alef, so ٱلْكِتَٰبِ and
    /// ٱلسَّمَٰوَٰتِ match the everyday spellings الكتاب and السماوات.
    static func normalize(_ word: String) -> String {
        var result = String.UnicodeScalarView()
        for scalar in word.unicodeScalars {
            switch scalar.value {
            case 0x0622, 0x0623, 0x0625, 0x0671, 0x0672, 0x0673, 0x0670: result.append("ا")
            case 0x0649, 0x0626: result.append("ي")
            case 0x0629: result.append("ه")
            case 0x0624: result.append("و")
            case 0x0621, 0x0640: continue
            default:
                if ArabicLetters.isLetter(scalar.value) { result.append(scalar) }
            }
        }
        return String(result)
    }

    /// Words of a phrase that contain letters.
    static func words(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init).filter { !normalize($0).isEmpty }
    }

    /// Close enough to count as the same word (allows one letter off in
    /// short words, a quarter of the letters in longer ones).
    static func similar(_ a: String, _ b: String) -> Bool {
        RecitationTracker.similar(Array(a.utf16), Array(b.utf16))
    }
}
