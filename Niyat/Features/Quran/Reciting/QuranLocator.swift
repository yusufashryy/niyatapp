import Foundation

/// Finds where a recited phrase is, anywhere in the Qur'an, so live recitation
/// can follow someone who starts (or moves on to) a different surah.
///
/// Pure logic: every pair of neighbouring words is indexed once; a phrase
/// votes for the places where its word pairs appear in the same order. A place
/// is only returned when enough of the phrase agrees and no other place does
/// as well (common phrases such as "إن الله" appear in many verses).
struct QuranLocator {
    /// Every word of the text, in order.
    let ids: [WordID]
    private let index: [String: [Int]]

    init(verses: [VerseWords]) {
        var ids: [WordID] = []
        var forms: [String] = []
        for verse in verses {
            for word in verse.words {
                ids.append(word.id)
                forms.append(word.normalized)
            }
        }
        var index: [String: [Int]] = [:]
        index.reserveCapacity(forms.count)
        for position in forms.indices.dropLast() {
            index[forms[position] + " " + forms[position + 1], default: []].append(position)
        }
        self.ids = ids
        self.index = index
    }

    /// The word the reciter has reached, if the phrase heard can be placed
    /// with confidence. Uses the last dozen words heard.
    func locate(_ heard: [String]) -> WordID? {
        let words = heard.map(RecitationMatcher.normalize).filter { !$0.isEmpty }.suffix(12)
        let phrase = Array(words)
        guard phrase.count >= 3 else { return nil }
        var votes: [Int: Int] = [:]
        for offset in phrase.indices.dropLast() {
            for position in index[phrase[offset] + " " + phrase[offset + 1]] ?? [] {
                votes[position - offset, default: 0] += 1
            }
        }
        let ranked = votes.sorted { $0.value > $1.value }
        guard let best = ranked.first else { return nil }
        // Several word pairs agree (at least half the phrase), and no other place ties.
        let needed = max(2, (phrase.count - 1) / 2)
        guard best.value >= needed, ranked.count < 2 || ranked[1].value < best.value else { return nil }
        let reached = min(max(best.key + phrase.count - 1, 0), ids.count - 1)
        return ids.indices.contains(reached) ? ids[reached] : nil
    }
}
