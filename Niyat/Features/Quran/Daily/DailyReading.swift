import Foundation

/// A place in the daily reader: an ayah in the shown reading's own numbering.
struct DailyPlace: Equatable, Hashable {
    let surah: Int
    let verse: Int

    /// Saved as "surah:verse".
    var storageKey: String { "\(surah):\(verse)" }

    init(surah: Int, verse: Int) {
        self.surah = surah
        self.verse = verse
    }

    init?(storageKey: String) {
        let parts = storageKey.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, parts[0] >= 1, parts[1] >= 1 else { return nil }
        self.init(surah: parts[0], verse: parts[1])
    }
}

/// The rules of the daily reader: one ayah at a time, counted once you read
/// on past it (tap Next or swipe), or hear it to the end. It keeps its own
/// bookmark, apart from the reader's ribbon. Pure, so it's tested.
enum DailyReading {
    /// The daily reader's bookmark (a Hafs `VerseReference`).
    static let markKey = "quran.daily.mark"
    /// Where the daily reader was, as "surah:verse", before it had a bookmark.
    static let legacyPlaceKey = "quran.daily.place"

    /// Reading on counts the ayah you leave; going back doesn't.
    static func countsWhenMoving(forwards: Bool) -> Bool { forwards }

    /// The daily bookmark: the saved one, else the place the daily reader kept before.
    static func initialMark(saved: VerseReference?, legacy: String) -> VerseReference? {
        if let saved { return saved }
        return DailyPlace(storageKey: legacy).map { VerseReference(surah: $0.surah, verse: $0.verse) }
    }

    /// The ayah after `place`, on into the next surah; nil after the last ayah.
    /// `verseCounts[i]` is the number of ayat in surah i + 1.
    static func next(after place: DailyPlace, verseCounts: [Int]) -> DailyPlace? {
        guard verseCounts.indices.contains(place.surah - 1) else { return nil }
        if place.verse < verseCounts[place.surah - 1] { return DailyPlace(surah: place.surah, verse: place.verse + 1) }
        return place.surah < verseCounts.count ? DailyPlace(surah: place.surah + 1, verse: 1) : nil
    }

    /// The ayah before `place`, back into the previous surah; nil before the first.
    static func previous(before place: DailyPlace, verseCounts: [Int]) -> DailyPlace? {
        if place.verse > 1 { return DailyPlace(surah: place.surah, verse: place.verse - 1) }
        guard place.surah > 1, verseCounts.indices.contains(place.surah - 2) else { return nil }
        return DailyPlace(surah: place.surah - 1, verse: verseCounts[place.surah - 2])
    }

    /// Where to open: the daily bookmark, else the reader's ribbon (a first
    /// daily reading starts where you left off), else Al-Fatiha; always a
    /// real ayah of the shown reading.
    static func start(mark: DailyPlace?, ribbon: DailyPlace?, verseCounts: [Int]) -> DailyPlace {
        let candidate = mark ?? ribbon ?? DailyPlace(surah: 1, verse: 1)
        guard verseCounts.indices.contains(candidate.surah - 1) else { return DailyPlace(surah: 1, verse: 1) }
        return DailyPlace(surah: candidate.surah, verse: min(candidate.verse, max(verseCounts[candidate.surah - 1], 1)))
    }

    /// The hizb (1...60) a Hafs verse is in, from where each quarter starts.
    static func hizb(of key: Int, quarterStarts: [Int]) -> Int {
        let quarter = quarterStarts.lastIndex { $0 <= key } ?? 0
        return quarter / 4 + 1
    }

    /// Ayat after `place` before the next juz starts (or the Qur'an ends), in
    /// Hafs numbering. `juzStarts` are the first ayah of each juz, in order.
    static func ayatLeftInJuz(after place: DailyPlace, juzStarts: [DailyPlace], verseCounts: [Int]) -> Int {
        let key = { (p: DailyPlace) in p.surah * 1000 + p.verse }
        let end = juzStarts.first { key($0) > key(place) }
        var count = 0
        var cursor = place
        while let next = DailyReading.next(after: cursor, verseCounts: verseCounts) {
            if let end, key(next) >= key(end) { break }
            count += 1
            cursor = next
        }
        return count
    }
}
