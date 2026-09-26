import XCTest
@testable import Niyat

/// Loads the Uthmani text once for these tests.
@MainActor
private func loadUthmani() async -> QuranStore {
    let store = QuranStore.shared
    await store.load()
    await store.setEdition(.uthmani)
    return store
}

final class RecitationMatcherTests: XCTestCase {
    func testNormalizeIgnoresHarakatAndSpellingVariants() {
        XCTAssertEqual(RecitationMatcher.normalize("إِيَّاكَ"), RecitationMatcher.normalize("اياك"))
        XCTAssertEqual(RecitationMatcher.normalize("رَحْمَةً"), RecitationMatcher.normalize("رحمه"))
        // The dagger alif is read as an alif: the Uthmani spelling matches the
        // everyday one, and is close to the spelling without it.
        XCTAssertEqual(RecitationMatcher.normalize("ٱلْكِتَٰبِ"), RecitationMatcher.normalize("الكتاب"))
        XCTAssertEqual(RecitationMatcher.normalize("ٱلسَّمَٰوَٰتِ"), RecitationMatcher.normalize("السماوات"))
        XCTAssertTrue(RecitationMatcher.similar(RecitationMatcher.normalize("الرَّحْمَٰنِ"), RecitationMatcher.normalize("الرحمن")))
        XCTAssertFalse(RecitationMatcher.similar("الناس", "الفلق"))
    }
}

/// The words layer: splitting verses into words must never lose or change a character.
final class QuranWordsTests: XCTestCase {
    @MainActor
    func testEveryCharacterBelongsToAWord() async {
        let store = QuranStore.shared
        await store.load()
        for edition in QuranEdition.allCases {
            await store.setEdition(edition)
            var words = 0
            for surah in store.surahs {
                for verse in store.verses(for: surah.id) {
                    let split = VerseWords(surah: verse.surah, verse: verse.number, text: verse.arabic)
                    let units = Array(verse.arabic.utf16)
                    var covered = Array(repeating: false, count: units.count)
                    var previousEnd = 0
                    for word in split.words {
                        XCTAssertGreaterThanOrEqual(word.displayRange.location, previousEnd, "\(edition) \(verse.surah):\(verse.number)")
                        XCTAssertTrue(NSLocationInRange(word.range.location, word.displayRange)
                                      && NSMaxRange(word.range) <= NSMaxRange(word.displayRange))
                        XCTAssertFalse(word.normalized.isEmpty, "\(edition) \(verse.surah):\(verse.number)")
                        for index in word.displayRange.location..<NSMaxRange(word.displayRange) { covered[index] = true }
                        previousEnd = NSMaxRange(word.displayRange)
                    }
                    // Only the spaces between words are left over.
                    for (index, unit) in units.enumerated() where !covered[index] {
                        XCTAssertEqual(unit, 0x20, "\(edition) \(verse.surah):\(verse.number) at \(index)")
                    }
                    words += split.words.count
                }
            }
            XCTAssertGreaterThan(words, 76_000, "\(edition)")
        }
        await store.setEdition(.uthmani)
    }

    /// Mushaf pages also show the "fewer marks" script: it must have the same words.
    @MainActor
    func testMinimalScriptHasTheSameWords() async {
        let store = QuranStore.shared
        await store.load()
        await store.setEdition(.uthmani)
        let full = store.surahs.flatMap { store.verses(for: $0.id) }
            .map { VerseWords(surah: $0.surah, verse: $0.number, text: $0.arabic).words.map(\.normalized) }
        await store.setEdition(.uthmaniMinimal)
        let minimal = store.surahs.flatMap { store.verses(for: $0.id) }
            .map { VerseWords(surah: $0.surah, verse: $0.number, text: $0.arabic).words.count }
        XCTAssertEqual(full.map(\.count), minimal)
        await store.setEdition(.uthmani)
    }
}

/// The 15-line layout must place every word of the verified text exactly once, in order.
final class MushafLayoutTests: XCTestCase {
    @MainActor
    func testEveryWordOnceInOrder() async {
        let store = await loadUthmani()
        let layout = MushafLayout.shared
        await layout.load()
        XCTAssertEqual(layout.pages.count, MushafLayout.pageCount)

        var expected: [WordID] = []
        var counts: [VerseKey: Int] = [:]
        for surah in store.surahs {
            for verse in store.verses(for: surah.id) {
                let count = VerseWords(surah: verse.surah, verse: verse.number, text: verse.arabic).words.count
                counts[VerseKey(surah: verse.surah, verse: verse.number)] = count
                expected += (0..<count).map { WordID(surah: verse.surah, verse: verse.number, index: $0) }
            }
        }

        var placed: [WordID] = []
        var lastHeader: Int?
        var sawBasmala = false
        for (index, rows) in layout.pages.enumerated() {
            let page = index + 1
            XCTAssertEqual(rows.count, page <= 2 ? 8 : 15, "page \(page)")
            for row in rows {
                switch row {
                case .header(let surah):
                    lastHeader = surah
                    sawBasmala = false
                case .basmala:
                    sawBasmala = true
                case .text(let from, let to):
                    var word = from
                    while true {
                        if word.index == 0, word.verse == 1 {
                            // A surah starts: its title (and Bismillah) come first.
                            XCTAssertEqual(lastHeader, word.surah, "page \(page)")
                            XCTAssertEqual(sawBasmala, word.surah != 1 && word.surah != 9, "page \(page)")
                        }
                        placed.append(word)
                        if word == to { break }
                        guard let count = counts[word.verseKey], placed.count <= expected.count else {
                            XCTFail("page \(page): no verse \(word.surah):\(word.verse)")
                            break
                        }
                        if word.index + 1 < count {
                            word = WordID(surah: word.surah, verse: word.verse, index: word.index + 1)
                        } else {
                            word = WordID(surah: word.surah, verse: word.verse + 1, index: 0)
                        }
                    }
                }
            }
            // Pages start where Tanzil's verified page divisions say.
            let start = store.pageStarts[index]
            XCTAssertEqual(layout.firstWord(onPage: page), WordID(surah: start.surah, verse: start.verse, index: 0), "page \(page)")
        }
        XCTAssertEqual(placed.count, expected.count)
        XCTAssertEqual(placed, expected)
    }

    @MainActor
    func testFindsTheRightPage() async {
        let layout = MushafLayout.shared
        await layout.load()
        XCTAssertEqual(layout.page(containing: WordID(surah: 1, verse: 1, index: 0)), 1)
        XCTAssertEqual(layout.page(containing: WordID(surah: 13, verse: 43, index: 0)), 255)
        XCTAssertEqual(layout.page(containing: WordID(surah: 14, verse: 1, index: 0)), 255)
        XCTAssertEqual(layout.page(containing: WordID(surah: 114, verse: 6, index: 2)), 604)
    }
}

/// Live recitation's tracker, with the recogniser's side played by the
/// Imla'i (everyday spelling) text, which is what speech recognition writes.
final class RecitationTrackerTests: XCTestCase {
    private static let imlaei: [String: [[String: Any]]] = {
        guard let url = Bundle.main.url(forResource: "quran-imlaei", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: [[String: Any]]] else { return [:] }
        return json
    }()

    /// Words as a recogniser would write them (verse 1 without the Bismillah).
    private func speech(_ surah: Int, _ verse: Int, from: Int = 0, to: Int? = nil) -> [String] {
        let text = Self.imlaei[String(surah)]?[verse - 1]["text"] as? String ?? ""
        var words = RecitationMatcher.words(text)
        if verse == 1, surah != 1, surah != 9 { words.removeFirst(4) }
        return Array(words[from..<(to ?? words.count)])
    }

    @MainActor
    private func tracker(_ verses: [(Int, Int)]) async -> RecitationTracker {
        let store = await loadUthmani()
        let words = verses.compactMap { store.verse(VerseReference(surah: $0.0, verse: $0.1)) }
            .map { QuranWords.shared.words(for: $0, edition: .uthmani) }
        var tracker = RecitationTracker(tokens: RecognitionForms.tokens(for: words, edition: .uthmani))
        tracker.begin(at: 0)
        return tracker
    }

    private func sure(_ words: [String]) -> [Float] { Array(repeating: 0.9, count: words.count) }

    private func position(_ tracker: RecitationTracker) -> WordID? {
        tracker.position.map { tracker.tokens[$0].id }
    }

    private func flagged(_ tracker: RecitationTracker) -> [WordID: RecitationTracker.Result] {
        Dictionary(uniqueKeysWithValues: tracker.flagged.map { (tracker.tokens[$0.index].id, $0.result) })
    }

    @MainActor
    func testFollowsAlongWordByWord() async {
        var tracker = await tracker([(14, 1), (14, 2), (14, 3)])
        let heard = speech(14, 1)
        for count in [2, 5] {
            XCTAssertEqual(tracker.update(heard: Array(heard.prefix(count)), isFinal: false), .following)
        }
        XCTAssertEqual(position(tracker), WordID(surah: 14, verse: 1, index: 4))
        XCTAssertEqual(tracker.update(heard: heard, confidences: sure(heard), isFinal: true), .following)
        XCTAssertEqual(position(tracker), WordID(surah: 14, verse: 1, index: 15))
        XCTAssertTrue(tracker.flagged.isEmpty)
    }

    @MainActor
    func testStartsInTheMiddleOfAnAyah() async {
        var tracker = await tracker([(14, 1), (14, 2), (14, 3)])
        let heard = speech(14, 2, from: 3)
        _ = tracker.update(heard: heard, confidences: sure(heard), isFinal: true)
        XCTAssertEqual(position(tracker), WordID(surah: 14, verse: 2, index: 13))
        XCTAssertTrue(tracker.flagged.isEmpty)
    }

    @MainActor
    func testStartsLaterThanExpected() async {
        var tracker = await tracker([(14, 1), (14, 2), (14, 3)])
        let heard = speech(14, 3)
        XCTAssertEqual(tracker.update(heard: Array(heard.prefix(6)), isFinal: false), .following)
        _ = tracker.update(heard: heard, confidences: sure(heard), isFinal: true)
        XCTAssertEqual(position(tracker), WordID(surah: 14, verse: 3, index: 15))
        XCTAssertTrue(tracker.flagged.isEmpty)
    }

    @MainActor
    func testSkippedWord() async {
        var tracker = await tracker([(14, 1), (14, 2), (14, 3)])
        var heard = speech(14, 1)
        heard.remove(at: 5)
        _ = tracker.update(heard: heard, confidences: sure(heard), isFinal: true)
        XCTAssertEqual(flagged(tracker), [WordID(surah: 14, verse: 1, index: 5): .skipped])
    }

    /// A clearly different word is a likely mistake only when the recogniser
    /// was confident; otherwise it is only "uncertain".
    @MainActor
    func testDifferentWordNeedsConfidence() async {
        var heard = speech(14, 1)
        heard[4] = "قلم"
        var confident = await tracker([(14, 1), (14, 2), (14, 3)])
        _ = confident.update(heard: heard, confidences: sure(heard), isFinal: true)
        XCTAssertEqual(flagged(confident), [WordID(surah: 14, verse: 1, index: 4): .mistake])

        var unsure = await tracker([(14, 1), (14, 2), (14, 3)])
        _ = unsure.update(heard: heard, confidences: Array(repeating: 0.3, count: heard.count), isFinal: true)
        XCTAssertEqual(flagged(unsure), [WordID(surah: 14, verse: 1, index: 4): .uncertain])
    }

    @MainActor
    func testRepeatsPausesAndRestartsAreNotMistakes() async {
        let heard = speech(14, 1)
        // Repeating a phrase.
        var repeated = await tracker([(14, 1), (14, 2), (14, 3)])
        let again = Array(heard[..<6] + heard[3..<6] + heard[6...])
        _ = repeated.update(heard: again, confidences: sure(again), isFinal: true)
        XCTAssertTrue(repeated.flagged.isEmpty)
        XCTAssertEqual(position(repeated), WordID(surah: 14, verse: 1, index: 15))

        // A pause, then carrying on.
        var paused = await tracker([(14, 1), (14, 2), (14, 3)])
        let first = Array(heard[..<7]), rest = Array(heard[7...])
        _ = paused.update(heard: first, confidences: sure(first), isFinal: true)
        _ = paused.update(heard: rest, confidences: sure(rest), isFinal: true)
        XCTAssertTrue(paused.flagged.isEmpty)
        XCTAssertEqual(position(paused), WordID(surah: 14, verse: 1, index: 15))

        // Starting the ayah again.
        var restarted = await tracker([(14, 1), (14, 2), (14, 3)])
        let part = Array(heard[..<9])
        _ = restarted.update(heard: part, confidences: sure(part), isFinal: true)
        _ = restarted.update(heard: heard, confidences: sure(heard), isFinal: true)
        XCTAssertTrue(restarted.flagged.isEmpty)
    }

    @MainActor
    func testGoesOnToTheNextAyah() async {
        var tracker = await tracker([(14, 1), (14, 2), (14, 3)])
        let first = speech(14, 1), second = speech(14, 2)
        _ = tracker.update(heard: first, confidences: sure(first), isFinal: true)
        _ = tracker.update(heard: second, confidences: sure(second), isFinal: true)
        XCTAssertEqual(position(tracker), WordID(surah: 14, verse: 2, index: 13))
        XCTAssertTrue(tracker.flagged.isEmpty)
    }

    /// "يا أيها" is one word in the Uthmani text and two when recognised.
    @MainActor
    func testWordsSplitByTheRecogniser() async {
        var tracker = await tracker([(2, 21)])
        let heard = speech(2, 21)
        _ = tracker.update(heard: heard, confidences: sure(heard), isFinal: true)
        XCTAssertEqual(position(tracker), WordID(surah: 2, verse: 21, index: 10))
        XCTAssertTrue(tracker.flagged.isEmpty)
    }

    @MainActor
    func testUnrelatedSpeechIsNotFollowed() async {
        var tracker = await tracker([(14, 1), (14, 2), (14, 3)])
        let heard = "هذا كلام عادي عن الطقس اليوم في المدينة الجميلة جدا".split(separator: " ").map(String.init)
        XCTAssertEqual(tracker.update(heard: heard, isFinal: false), .lost)
        XCTAssertNil(tracker.position)
        XCTAssertTrue(tracker.flagged.isEmpty)
    }

    /// Timing a reciter's recording: only clearly recognised words are placed.
    @MainActor
    func testMatchedPairsPlaceOnlyRecognisedWords() async {
        let tracker = await tracker([(14, 1)])
        var heard = speech(14, 1)
        heard[4] = "قلم"   // misheard: left out
        heard.remove(at: 8) // not heard: left out
        let pairs = RecitationTracker.matchedPairs(tokens: tracker.tokens, heard: heard)
        let tokens = pairs.map(\.token)
        XCTAssertFalse(tokens.contains(4))
        XCTAssertFalse(tokens.contains(8))
        XCTAssertEqual(tokens, tokens.sorted())
        XCTAssertGreaterThanOrEqual(pairs.count, 12)
        for pair in pairs where pair.token < 4 { XCTAssertEqual(pair.heard, pair.token) }
    }
}

final class WordTimingsTests: XCTestCase {
    func testFillSharesTimeByLetters() {
        let starts = WordTimingAligner.fill(anchors: [0: 0, 2: 1, 4: 3], count: 5, letters: [2, 2, 2, 4, 2], duration: 4)
        let expected = [0, 0.5, 1, 1 + 2.0 / 3, 3]
        for (value, want) in zip(starts, expected) { XCTAssertEqual(value, want, accuracy: 0.001) }
        // Before the first placed word, from the start of the recording.
        let early = WordTimingAligner.fill(anchors: [2: 2, 3: 3], count: 4, letters: [1, 1, 1, 1], duration: 4)
        XCTAssertEqual(early[0], 0, accuracy: 0.001)
        XCTAssertEqual(early[1], 1, accuracy: 0.001)
    }

    func testWordAtTime() {
        let timings = WordTimings(starts: [0.2, 0.5, 1, 1.7, 3], anchored: 3)
        XCTAssertNil(timings.word(at: 0.1))
        XCTAssertEqual(timings.word(at: 0.2), 0)
        XCTAssertEqual(timings.word(at: 0.49), 0)
        XCTAssertEqual(timings.word(at: 1.2), 2)
        XCTAssertEqual(timings.word(at: 9), 4)
    }

    func testAnchorsMustBeInOrder() {
        XCTAssertTrue(WordTimingAligner.isInOrder([0: 0.1, 3: 0.9, 5: 2]))
        XCTAssertFalse(WordTimingAligner.isInOrder([0: 0.1, 3: 2.5, 5: 2]))
    }
}
