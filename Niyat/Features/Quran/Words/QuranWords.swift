import Foundation

// The Qur'an as words. Everything that works word by word (the mushaf and
// verse renderer, live recitation, the reciter's word highlight) uses these
// types, so they all agree on what "word 5 of 14:1" is.
//
// Two layers are kept strictly apart:
// - display: the exact verified text (Tanzil), never changed;
// - recognition: a simplified, letters-only form used only to compare with
//   speech. It is never shown.

/// A verse in the reading being displayed.
struct VerseKey: Hashable, Comparable, Codable {
    let surah: Int
    let verse: Int

    static func < (lhs: VerseKey, rhs: VerseKey) -> Bool {
        (lhs.surah, lhs.verse) < (rhs.surah, rhs.verse)
    }
}

/// One word: its verse, and its position in the verse as displayed (0-based,
/// counting only pieces of text that contain letters, so pause and sajdah
/// marks are never counted as words).
struct WordID: Hashable, Comparable {
    let surah: Int
    let verse: Int
    let index: Int

    var verseKey: VerseKey { VerseKey(surah: surah, verse: verse) }

    static func < (lhs: WordID, rhs: WordID) -> Bool {
        (lhs.surah, lhs.verse, lhs.index) < (rhs.surah, rhs.verse, rhs.index)
    }
}

/// A verse split into words without changing a single character.
///
/// The text is split at spaces. Pieces with letters are words; pieces without
/// letters (pause marks such as ۚ, the sajdah mark ۩, the hizb mark ۞) stay
/// with the word they follow (or, at the very start, the word they precede).
struct VerseWords {
    struct Word {
        let id: WordID
        /// The word itself (letters and harakat), as a UTF-16 range of `text`.
        let range: NSRange
        /// The word with the marks that belong to it, and the spaces between them.
        let displayRange: NSRange
        /// Letters only, spelling variants folded. For speech matching only.
        let normalized: String
    }

    let key: VerseKey
    /// Exactly as in the bundled text.
    let text: String
    let words: [Word]

    init(surah: Int, verse: Int, text: String) {
        key = VerseKey(surah: surah, verse: verse)
        self.text = text
        let units = Array(text.utf16)

        // Pieces between spaces, as UTF-16 ranges.
        var pieces: [NSRange] = []
        var start = 0
        for index in 0...units.count where index == units.count || units[index] == 0x20 {
            if index > start { pieces.append(NSRange(location: start, length: index - start)) }
            start = index + 1
        }

        var words: [Word] = []
        var leadingMarks: Int?
        for piece in pieces {
            let hasLetter = units[piece.location..<NSMaxRange(piece)].contains { ArabicLetters.isLetter(UInt32($0)) }
            if hasLetter {
                let displayStart = leadingMarks ?? piece.location
                leadingMarks = nil
                let substring = (text as NSString).substring(with: piece)
                words.append(Word(id: WordID(surah: surah, verse: verse, index: words.count),
                                  range: piece,
                                  displayRange: NSRange(location: displayStart, length: NSMaxRange(piece) - displayStart),
                                  normalized: RecitationMatcher.normalize(substring)))
            } else if let last = words.last {
                // A mark after a word stays with that word.
                words[words.count - 1] = Word(id: last.id, range: last.range,
                                              displayRange: NSRange(location: last.displayRange.location,
                                                                    length: NSMaxRange(piece) - last.displayRange.location),
                                              normalized: last.normalized)
            } else if leadingMarks == nil {
                leadingMarks = piece.location
            }
        }
        self.words = words
    }
}

/// Splits verses into words once and remembers the result.
@MainActor
final class QuranWords {
    static let shared = QuranWords()

    private var cache: [String: VerseWords] = [:]

    private init() {}

    /// The words of a verse as displayed in the current reading.
    func words(for verse: Verse, edition: QuranEdition) -> VerseWords {
        let key = "\(edition.rawValue):\(verse.surah):\(verse.number)"
        if let cached = cache[key] { return cached }
        let words = VerseWords(surah: verse.surah, verse: verse.number, text: verse.arabic)
        cache[key] = words
        return words
    }

    func removeAll() { cache.removeAll() }
}
