import XCTest
@testable import Niyat

/// Finding where someone is reciting, from the words the model wrote down.
final class FindByRecitingTests: XCTestCase {
    @MainActor
    private func search() async -> (QuranLocator, QuranLetterSearch) {
        let store = QuranStore.shared
        await store.load()
        let verses = store.surahs.flatMap { store.verses(for: $0.id) }
            .map { QuranWords.shared.words(for: $0, edition: .uthmani) }
        return (QuranLocator(verses: verses), QuranLetterSearch(verses: verses))
    }

    @MainActor
    func testExactWordsAreTrustedAtOnce() async {
        let (words, letters) = await search()
        var confirmation = FindConfirmation()
        // As the model wrote 2:255 (everyday spelling, a dropped letter).
        let heard = "اللَّهُ لَ إِلَهَ إِلَّا هُوَ الْحَيُّ الْقَيُّومُ لَا تَأْخُذُهُ سِنَةٌ".split(separator: " ").map(String.init)
        XCTAssertEqual(confirmation.place(for: heard, words: words, letters: letters)?.surah, 2)
    }

    @MainActor
    func testLooseLettersNeedTheSameAnswerTwice() async {
        let (words, letters) = await search()
        // An-Nas 114:1-2 with slips in every word: no exact word pairs.
        let heard = ["قُل", "اعوذ", "برب", "الناسي", "ملكي", "الناسو"]
        XCTAssertEqual(letters.find(heard)?.verse.surah, 114)
        var confirmation = FindConfirmation()
        XCTAssertNil(confirmation.place(for: heard, words: words, letters: letters))
        XCTAssertEqual(confirmation.place(for: heard, words: words, letters: letters)?.surah, 114)
    }

    @MainActor
    func testTooLittleIsNotPlaced() async {
        let (words, letters) = await search()
        var confirmation = FindConfirmation()
        XCTAssertNil(confirmation.place(for: ["يس"], words: words, letters: letters))
        XCTAssertNil(letters.find(["يس"]))
    }

    func testEditDistance() {
        XCTAssertEqual(QuranLetterSearch.editDistance(Array("كتاب".utf16), Array("كتب".utf16)[...]), 1)
        XCTAssertEqual(QuranLetterSearch.editDistance(Array("".utf16), Array("ab".utf16)[...]), 2)
    }

    @MainActor
    func testHandoffIsTakenOnceBySurah() {
        RecitationHandoff.pending = VerseReference(surah: 18, verse: 10)
        XCTAssertNil(RecitationHandoff.take(for: 2))
        XCTAssertEqual(RecitationHandoff.take(for: 18), VerseReference(surah: 18, verse: 10))
        XCTAssertNil(RecitationHandoff.take(for: 18))
    }
}
