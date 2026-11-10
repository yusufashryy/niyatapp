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

/// The rules of the daily reader: one ayah at a time, counted only once it
/// has been on screen long enough to read, or heard to the end. Pure, so it's tested.
enum DailyReading {
    static let placeKey = "quran.daily.place"

    /// Letters read per second, at an unhurried pace (recitation is slower;
    /// reading silently is faster, so this sits between them).
    static let lettersPerSecond = 15.0
    /// Even the shortest ayah stays this long before it counts.
    static let shortestTime = 2.0
    /// And the longest never asks for more than this.
    static let longestTime = 25.0

    /// How long an ayah of this many letters must stay on screen to count.
    static func readingTime(letters: Int) -> Double {
        min(max(Double(letters) / lettersPerSecond, shortestTime), longestTime)
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

    /// Where to open: the ribbon (the one place "where I left off" is kept,
    /// shared with the reader and the mushaf), else the daily reader's own
    /// last place, else Al-Fatiha; always a real ayah of the shown reading.
    static func start(saved: String, ribbon: DailyPlace?, verseCounts: [Int]) -> DailyPlace {
        let candidate = ribbon ?? DailyPlace(storageKey: saved) ?? DailyPlace(surah: 1, verse: 1)
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
