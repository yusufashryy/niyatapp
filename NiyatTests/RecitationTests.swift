import XCTest
import AVFoundation
import Speech
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
        // everyday one; other spellings need explicit accepted alternatives.
        XCTAssertEqual(RecitationMatcher.normalize("ٱلْكِتَٰبِ"), RecitationMatcher.normalize("الكتاب"))
        XCTAssertEqual(RecitationMatcher.normalize("ٱلسَّمَٰوَٰتِ"), RecitationMatcher.normalize("السماوات"))
        XCTAssertNotEqual(RecitationMatcher.normalize("الرَّحْمَٰنِ"), RecitationMatcher.normalize("الرحمن"))
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
    private func makeTracker(_ verses: [(Int, Int)]) async -> RecitationTracker {
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
    func testFatihaAcceptsDocumentedEverydaySpellings() async {
        var tracker = await makeTracker((1...7).map { (1, $0) })
        for verse in 1...7 {
            let heard = speech(1, verse)
            _ = tracker.update(heard: heard, confidences: sure(heard), isFinal: true)
        }
        XCTAssertTrue(tracker.flagged.isEmpty)
        XCTAssertEqual(tracker.committed.count, tracker.tokens.count)
    }

    @MainActor
    func testFollowsAlongWordByWord() async {
        var tracker = await makeTracker([(14, 1), (14, 2), (14, 3)])
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
        var tracker = await makeTracker([(14, 1), (14, 2), (14, 3)])
        let heard = speech(14, 2, from: 3)
        _ = tracker.update(heard: heard, confidences: sure(heard), isFinal: true)
        XCTAssertEqual(position(tracker), WordID(surah: 14, verse: 2, index: 13))
        XCTAssertTrue(tracker.flagged.isEmpty)
    }

    @MainActor
    func testStartsLaterThanExpected() async {
        var tracker = await makeTracker([(14, 1), (14, 2), (14, 3)])
        let heard = speech(14, 3)
        XCTAssertEqual(tracker.update(heard: Array(heard.prefix(6)), isFinal: false), .following)
        _ = tracker.update(heard: heard, confidences: sure(heard), isFinal: true)
        XCTAssertEqual(position(tracker), WordID(surah: 14, verse: 3, index: 15))
        XCTAssertTrue(tracker.flagged.isEmpty)
    }

    @MainActor
    func testSkippedWord() async {
        var tracker = await makeTracker([(14, 1), (14, 2), (14, 3)])
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
        var confident = await makeTracker([(14, 1), (14, 2), (14, 3)])
        _ = confident.update(heard: heard, confidences: sure(heard), isFinal: true)
        XCTAssertEqual(flagged(confident), [WordID(surah: 14, verse: 1, index: 4): .mistake])

        var unsure = await makeTracker([(14, 1), (14, 2), (14, 3)])
        _ = unsure.update(heard: heard, confidences: Array(repeating: 0.3, count: heard.count), isFinal: true)
        XCTAssertEqual(unsure.committed.count, 16)
        XCTAssertTrue(unsure.committed.values.allSatisfy { $0 == .uncertain })
    }

    /// Changed letters must not be accepted as a spelling variant.
    @MainActor
    func testChangedLettersNeverCountAsCorrect() async {
        var tracker = await makeTracker([(14, 1), (14, 2), (14, 3)])
        var heard = speech(14, 1)
        guard let index = heard.indices.first(where: { $0 > 1 && RecitationMatcher.normalize(heard[$0]).count >= 6 }) else {
            return XCTFail("No long word")
        }
        var letters = Array(heard[index])
        letters[letters.count / 2] = letters[letters.count / 2] == "ت" ? "ث" : "ت"
        letters.insert("ا", at: 1)
        heard[index] = String(letters)
        _ = tracker.update(heard: heard, confidences: sure(heard), isFinal: true)
        XCTAssertNotEqual(tracker.committed[index], .correct)
        XCTAssertFalse(tracker.flagged.isEmpty)
        XCTAssertEqual(position(tracker), WordID(surah: 14, verse: 1, index: 15))
    }

    /// A mismatch stays uncertain while partial, then is judged at finalization.
    @MainActor
    func testClearMistakeShowsBeforeThePause() async {
        var tracker = await makeTracker([(14, 1), (14, 2), (14, 3)])
        var heard = speech(14, 1)
        heard[4] = "قلم"
        _ = tracker.update(heard: Array(heard.prefix(7)), isFinal: false)
        XCTAssertEqual(tracker.early[4], .uncertain)
        _ = tracker.update(heard: heard, confidences: sure(heard), isFinal: true)
        XCTAssertTrue(tracker.early.isEmpty)
        XCTAssertEqual(flagged(tracker), [WordID(surah: 14, verse: 1, index: 4): .mistake])
    }

    /// Gaps between utterances stay visible as unverified words.
    @MainActor
    func testWordsLostBetweenUtterancesRemainUnverified() async {
        var tracker = await makeTracker([(14, 1), (14, 2), (14, 3)])
        let heard = speech(14, 1)
        let first = Array(heard[..<7]), rest = Array(heard[9...])
        _ = tracker.update(heard: first, confidences: sure(first), isFinal: true)
        _ = tracker.update(heard: rest, confidences: sure(rest), isFinal: true)
        XCTAssertEqual(tracker.committed[7], .uncertain)
        XCTAssertEqual(tracker.committed[8], .uncertain)
        XCTAssertEqual(position(tracker), WordID(surah: 14, verse: 1, index: 15))
    }

    @MainActor
    func testRepeatsPausesAndRestartsAreNotMistakes() async {
        let heard = speech(14, 1)
        // Repeating a phrase.
        var repeated = await makeTracker([(14, 1), (14, 2), (14, 3)])
        let again = Array(heard[..<6] + heard[3..<6] + heard[6...])
        _ = repeated.update(heard: again, confidences: sure(again), isFinal: true)
        XCTAssertTrue(repeated.flagged.isEmpty)
        XCTAssertEqual(position(repeated), WordID(surah: 14, verse: 1, index: 15))

        // A pause, then carrying on.
        var paused = await makeTracker([(14, 1), (14, 2), (14, 3)])
        let first = Array(heard[..<7]), rest = Array(heard[7...])
        _ = paused.update(heard: first, confidences: sure(first), isFinal: true)
        _ = paused.update(heard: rest, confidences: sure(rest), isFinal: true)
        XCTAssertTrue(paused.flagged.isEmpty)
        XCTAssertEqual(position(paused), WordID(surah: 14, verse: 1, index: 15))

        // Starting the ayah again.
        var restarted = await makeTracker([(14, 1), (14, 2), (14, 3)])
        let part = Array(heard[..<9])
        _ = restarted.update(heard: part, confidences: sure(part), isFinal: true)
        _ = restarted.update(heard: heard, confidences: sure(heard), isFinal: true)
        XCTAssertTrue(restarted.flagged.isEmpty)
    }

    @MainActor
    func testGoesOnToTheNextAyah() async {
        var tracker = await makeTracker([(14, 1), (14, 2), (14, 3)])
        let first = speech(14, 1), second = speech(14, 2)
        _ = tracker.update(heard: first, confidences: sure(first), isFinal: true)
        _ = tracker.update(heard: second, confidences: sure(second), isFinal: true)
        XCTAssertEqual(position(tracker), WordID(surah: 14, verse: 2, index: 13))
        XCTAssertTrue(tracker.flagged.isEmpty)
    }

    /// "يا أيها" is one word in the Uthmani text and two when recognised.
    @MainActor
    func testWordsSplitByTheRecogniser() async {
        var tracker = await makeTracker([(2, 21)])
        let heard = speech(2, 21)
        _ = tracker.update(heard: heard, confidences: sure(heard), isFinal: true)
        XCTAssertEqual(position(tracker), WordID(surah: 2, verse: 21, index: 10))
        XCTAssertTrue(tracker.flagged.isEmpty)
    }

    @MainActor
    func testUnrelatedSpeechIsNotFollowed() async {
        var tracker = await makeTracker([(14, 1), (14, 2), (14, 3)])
        let heard = "هذا كلام عادي عن الطقس اليوم في المدينة الجميلة جدا".split(separator: " ").map(String.init)
        XCTAssertEqual(tracker.update(heard: heard, isFinal: false), .lost)
        XCTAssertNil(tracker.position)
        XCTAssertTrue(tracker.flagged.isEmpty)
    }

    /// Reciting from another surah: the phrase is found anywhere in the Qur'an.
    @MainActor
    func testLocatesAPhraseAnywhere() async {
        let store = await loadUthmani()
        let verses = store.surahs.flatMap { store.verses(for: $0.id) }
            .map { VerseWords(surah: $0.surah, verse: $0.number, text: $0.arabic) }
        let locator = QuranLocator(verses: verses)
        XCTAssertEqual(locator.locate(speech(14, 1, from: 2, to: 10)), WordID(surah: 14, verse: 1, index: 9))
        XCTAssertEqual(locator.locate(speech(2, 255, from: 0, to: 8)), WordID(surah: 2, verse: 255, index: 7))
        // Too short, or not Qur'an: not placed.
        XCTAssertNil(locator.locate(["الحمد", "لله"]))
        XCTAssertNil(locator.locate("هذا كلام عادي عن الطقس اليوم".split(separator: " ").map(String.init)))
    }

    /// Timing a reciter's recording: only clearly recognised words are placed.
    @MainActor
    func testMatchedPairsPlaceOnlyRecognisedWords() async {
        let tracker = await makeTracker([(14, 1)])
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

/// Regression cases that do not depend on bundled text or a speech service.
final class RecitationSafetyTests: XCTestCase {
    private let words = ["الحمد", "لله", "رب", "العالمين", "الرحمن", "الرحيم"]

    private func tracker(_ words: [String]) -> RecitationTracker {
        var value = RecitationTracker(tokens: words.enumerated().map {
            RecitationTracker.Token(id: WordID(surah: 1, verse: 1, index: $0.offset),
                                    forms: [RecitationMatcher.normalize($0.element)])
        })
        value.begin(at: 0)
        return value
    }

    func testOneLetterSubstitutionIsNotGreen() {
        let target = ["الحمد", "لله", "من", "الرحمن", "الرحيم"]
        var value = tracker(target)
        var heard = target
        heard[2] = "عن"
        _ = value.update(heard: heard, confidences: Array(repeating: 0.9, count: heard.count), isFinal: true)
        XCTAssertEqual(value.committed[2], .mistake)
        XCTAssertEqual(value.position, 4)
    }

    func testPartialRevisionRetractsMatch() {
        var value = tracker(words)
        _ = value.update(heard: words, isFinal: false)
        XCTAssertEqual(value.result(at: 2), .uncertain)
        var revised = words
        revised[2] = "قلم"
        _ = value.update(heard: revised, isFinal: false)
        XCTAssertNotEqual(value.result(at: 2), .correct)
        _ = value.update(heard: revised, confidences: Array(repeating: 0.9, count: words.count), isFinal: true)
        XCTAssertEqual(value.result(at: 2), .mistake)
        XCTAssertTrue(value.early.isEmpty)
    }

    func testShortenedTranscriptRemovesTransientMarks() {
        var value = tracker(words)
        _ = value.update(heard: words, isFinal: false)
        _ = value.update(heard: Array(words.prefix(2)), isFinal: false)
        XCTAssertNil(value.result(at: 5))
        XCTAssertEqual(value.position, 1)
    }

    func testTimeoutCannotCertifyPartialWords() {
        var value = tracker(words)
        _ = value.update(heard: words, isFinal: false)
        value.finishUtterance()
        XCTAssertEqual(value.committed.count, words.count)
        XCTAssertTrue(value.committed.values.allSatisfy { $0 == .uncertain })
    }

    func testLowConfidenceMatchRemainsUncertain() {
        var value = tracker(words)
        _ = value.update(heard: words, confidences: [0.9, 0.9, 0, 0.9, 0.9, 0.9], isFinal: true)
        XCTAssertEqual(value.committed[2], .uncertain)
        XCTAssertEqual(value.committed[1], .correct)
    }

    func testTrailingSubstitutionIsReviewed() {
        var value = tracker(words)
        var heard = words
        heard[5] = "قلم"
        _ = value.update(heard: heard, confidences: Array(repeating: 0.9, count: words.count), isFinal: true)
        XCTAssertEqual(value.committed[5], .mistake)
    }

    func testSplitWordRequiresConfidenceInEveryPart() {
        var value = tracker(["ياايها", "الناس", "اعبدوا"])
        _ = value.update(heard: ["يا", "ايها", "الناس", "اعبدوا"],
                         confidences: [0.9, 0.1, 0.9, 0.9], isFinal: true)
        XCTAssertEqual(value.committed[0], .uncertain)
        XCTAssertEqual(value.committed[1], .correct)
    }

    func testMergedWordsDoNotForgiveChangedLetters() {
        var value = tracker(words)
        _ = value.update(heard: ["الحمد", "لله", "ربالعالمون", "الرحمن", "الرحيم"],
                         confidences: Array(repeating: 0.9, count: 5), isFinal: true)
        XCTAssertNotEqual(value.committed[2], .correct)
        XCTAssertNotEqual(value.committed[3], .correct)
    }

    func testLowConfidenceAnchorsDoNotCertifySkip() {
        var value = tracker(words)
        var heard = words
        heard.remove(at: 2)
        _ = value.update(heard: heard, confidences: Array(repeating: 0.1, count: heard.count), isFinal: true)
        XCTAssertEqual(value.committed[2], .uncertain)
    }

    func testLongStreamingTranscriptPerformance() {
        let target = Array(repeating: words, count: 34).flatMap { $0 }
        measure {
            var value = tracker(target)
            _ = value.update(heard: Array(target.prefix(150)), isFinal: false)
            XCTAssertNotNil(value.position)
        }
    }
}

final class RecitationAudioTests: XCTestCase {
    private final class Request: RecitationAudioRequest {
        var samples: [Float] = []
        var ends = 0
        func append(_ audioPCMBuffer: AVAudioPCMBuffer) {
            samples.append(audioPCMBuffer.floatChannelData![0][0])
        }
        func endAudio() { ends += 1 }
    }

    func testAudioDuringFinalizationReplaysOnceInOrder() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024))
        buffer.frameLength = 1024
        buffer.floatChannelData![0].initialize(repeating: 0, count: 1024)
        let box = RequestBox(), first = Request(), second = Request(), third = Request()
        box.set(first)
        buffer.floatChannelData![0][0] = 1
        box.append(buffer)
        box.endCurrentAudio()
        for value: Float in [2, 3] {
            buffer.floatChannelData![0][0] = value
            box.append(buffer)
        }
        XCTAssertEqual(first.samples, [1])
        XCTAssertEqual(first.ends, 1)
        box.set(second)
        XCTAssertEqual(second.samples, [2, 3])
        buffer.floatChannelData![0][0] = 4
        box.append(buffer)
        XCTAssertEqual(second.samples, [2, 3, 4])
        box.set(third)
        XCTAssertTrue(third.samples.isEmpty)
        box.set(nil)
    }

    func testStoppingDiscardsPendingAudio() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024))
        buffer.frameLength = 1024
        buffer.floatChannelData![0].initialize(repeating: 0.1, count: 1024)
        let box = RequestBox(), first = Request(), next = Request()
        box.set(first)
        box.endCurrentAudio()
        box.append(buffer)
        box.set(nil)
        box.set(next)
        XCTAssertTrue(next.samples.isEmpty)
        box.set(nil)
    }

    func testBufferedAudioOwnsItsSamples() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024))
        buffer.frameLength = 1024
        buffer.floatChannelData![0].initialize(repeating: 0.25, count: 1024)
        let copy = try XCTUnwrap(RequestBox.copy(buffer))
        buffer.floatChannelData![0][0] = 0
        XCTAssertEqual(copy.floatChannelData![0][0], 0.25)
        XCTAssertEqual(copy.frameLength, buffer.frameLength)
    }

    func testOldCallbackCannotEndNewRequest() {
        let box = RequestBox()
        let first = SFSpeechAudioBufferRecognitionRequest()
        let second = SFSpeechAudioBufferRecognitionRequest()
        box.set(first)
        XCTAssertTrue(box.endCurrentAudio(ifCurrent: first))
        XCTAssertFalse(box.endCurrentAudio(ifCurrent: first))
        box.set(second)
        XCTAssertFalse(box.endCurrentAudio(ifCurrent: first))
        XCTAssertTrue(box.endCurrentAudio(ifCurrent: second))
        box.set(nil)
        XCTAssertFalse(box.endCurrentAudio())
    }

    func testLackOfRecognitionCallbacksIsNotSilence() throws {
        let box = RequestBox()
        box.set(SFSpeechAudioBufferRecognitionRequest())
        XCTAssertFalse(box.hasSpeechPause)
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024))
        buffer.frameLength = 1024
        buffer.floatChannelData![0].initialize(repeating: 0.05, count: 1024)
        box.append(buffer)
        XCTAssertFalse(box.hasSpeechPause)
        box.set(nil)
    }
}
