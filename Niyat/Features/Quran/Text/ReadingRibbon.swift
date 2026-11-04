import Foundation

/// The reading ribbon: one marker for where you are in the Qur'an, like the
/// ribbon sewn into a printed mushaf. It moves instead of multiplying, and
/// "Continue reading", the Mushaf tile and the Qur'an reminder all open at it.
///
/// It only moves once you stay put on a place you went to yourself. Jumps
/// (search, the juz list, duas, following a recitation) leave it where it is.
enum ReadingRibbon {
    /// "Move the ribbon as I read" (on by default).
    static let followsKey = "quran.ribbonFollows"
    static let storageKey = "quran.ribbon"
    /// Where the reading position was kept before the ribbon.
    static let legacyKey = "quran.lastRead"
    /// The reader put the ribbon there themselves.
    static let pinnedKey = "quran.ribbonPinned"

    /// How long the verse reader must rest after you scroll before the ribbon moves.
    static let readerDwell: Duration = .seconds(2)

    /// The ribbon at launch: the saved one, or the old reading position.
    static func initial(saved: VerseReference?, legacy: VerseReference?) -> VerseReference? {
        saved ?? legacy
    }

    /// Whether settling on a place moves the ribbon.
    static func shouldMove(follows: Bool, movedByReader: Bool) -> Bool {
        follows && movedByReader
    }

    /// The page to offer the ribbon when closing the mushaf with "move as I
    /// read" off, or nil when there's nothing to ask.
    static func pageToOffer(follows: Bool, ribbonPage: Int?, currentPage: Int) -> Int? {
        guard !follows, ribbonPage != currentPage else { return nil }
        return currentPage
    }

    /// Whether following the reader moves the ribbon to `target`. A ribbon
    /// placed by hand stays put while you look back or around; once you
    /// read on past it, it follows you again, like a ribbon in a book.
    static func follows(to target: VerseReference, from ribbon: VerseReference?, pinned: Bool) -> Bool {
        guard let ribbon else { return true }
        guard target != ribbon else { return false }
        return !pinned || (target.surah, target.verse) > (ribbon.surah, ribbon.verse)
    }

    /// Seconds a mushaf page must stay open to count as read: about 1.5 s per
    /// verse, 4–20 s.
    static func pageDwell(verseCount: Int) -> Double {
        min(max(Double(verseCount) * 1.5, 4), 20)
    }
}
