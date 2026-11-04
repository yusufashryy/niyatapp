import Foundation

/// Finds where a loosely written phrase is in the Qur'an, letter by letter,
/// when the words themselves don't match exactly (the recitation model's
/// spelling slips: يؤمن for يؤمنون). Every run of three letters is indexed
/// once; a phrase votes for where its runs line up, and the best few places
/// are checked letter by letter.
///
/// Measured on the model's transcripts of 564 professional recordings, this
/// alone found the right ayah 88% of the time (9% wrong), so callers wait for
/// the same answer twice before acting on it.
struct QuranLetterSearch {
    struct Match: Equatable {
        let verse: VerseReference
        /// 0 (identical) to 1.
        let distance: Double
    }

    private let letters: [UInt16]
    private let owners: [VerseReference]
    private let index: [UInt64: [Int32]]

    /// Too few letters says too little about where it is.
    static let minimumLetters = 10
    /// Further than this isn't the same text.
    static let maximumDistance = 0.35

    init(verses: [VerseWords]) {
        var letters: [UInt16] = []
        var owners: [VerseReference] = []
        for verse in verses {
            let reference = VerseReference(surah: verse.key.surah, verse: verse.key.verse)
            for word in verse.words {
                for unit in word.normalized.utf16 {
                    letters.append(unit)
                    owners.append(reference)
                }
            }
        }
        var index: [UInt64: [Int32]] = [:]
        if letters.count >= 3 {
            for position in 0...(letters.count - 3) {
                index[Self.key(letters, position), default: []].append(Int32(position))
            }
        }
        self.letters = letters
        self.owners = owners
        self.index = index
    }

    private static func key(_ letters: [UInt16], _ position: Int) -> UInt64 {
        UInt64(letters[position]) << 32 | UInt64(letters[position + 1]) << 16 | UInt64(letters[position + 2])
    }

    /// The likeliest place for words heard, or nil when nothing is close.
    func find(_ heard: [String]) -> Match? {
        let query = Array(heard.map(RecitationMatcher.normalize).joined().utf16)
        guard query.count >= Self.minimumLetters else { return nil }
        var votes: [Int: Int] = [:]
        for position in 0...(query.count - 3) {
            // Very common runs (ال...) say little; skip them.
            guard let places = index[Self.key(query, position)], places.count < 4000 else { continue }
            for place in places { votes[Int(place) - position, default: 0] += 1 }
        }
        let candidates = votes.sorted { $0.value > $1.value }.prefix(8)
        var best: (start: Int, distance: Double)?
        for (start, _) in candidates {
            let from = max(start, 0)
            let to = min(start + query.count, letters.count)
            guard to > from else { continue }
            let distance = Double(Self.editDistance(query, letters[from..<to])) / Double(max(query.count, to - from))
            if best.map({ distance < $0.distance }) ?? true { best = (from, distance) }
        }
        guard let best, best.distance <= Self.maximumDistance else { return nil }
        // Where the phrase begins: following carries on from there.
        return Match(verse: owners[min(best.start, owners.count - 1)], distance: best.distance)
    }

    static func editDistance(_ a: [UInt16], _ b: ArraySlice<UInt16>) -> Int {
        let b = Array(b)
        guard !a.isEmpty else { return b.count }
        guard !b.isEmpty else { return a.count }
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}
