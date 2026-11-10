import XCTest
@testable import Niyat

final class SurahSearchTests: XCTestCase {
    private let surahs = [
        SurahSearch.Entry(id: 1, name: "الفاتحة", transliteration: "Al-Faatiha", translation: "The Opening"),
        SurahSearch.Entry(id: 2, name: "البقرة", transliteration: "Al-Baqara", translation: "The Cow"),
        SurahSearch.Entry(id: 18, name: "الكهف", transliteration: "Al-Kahf", translation: "The Cave"),
        SurahSearch.Entry(id: 112, name: "الإخلاص", transliteration: "Al-Ikhlaas", translation: "Sincerity"),
    ]

    func testEmptyFindsEverySurah() {
        XCTAssertEqual(SurahSearch.matches(surahs, query: "  ").map(\.id), [1, 2, 18, 112])
    }

    func testANumberFindsThatSurah() {
        XCTAssertEqual(SurahSearch.matches(surahs, query: "18").map(\.id), [18])
    }

    func testNamesIgnoreCaseHyphensAndATrailingH() {
        XCTAssertEqual(SurahSearch.matches(surahs, query: "baqarah").map(\.id), [2])
        XCTAssertEqual(SurahSearch.matches(surahs, query: "al kahf").map(\.id), [18])
        XCTAssertEqual(SurahSearch.matches(surahs, query: "ikhlas").map(\.id), [112])
    }

    func testMeaningAndArabicMatch() {
        XCTAssertEqual(SurahSearch.matches(surahs, query: "cave").map(\.id), [18])
        XCTAssertEqual(SurahSearch.matches(surahs, query: "البقرة").map(\.id), [2])
    }

    func testAnAyahReference() {
        let counts = [7, 286]
        XCTAssertEqual(SurahSearch.place(in: "2:255", verseCounts: counts), DailyPlace(surah: 2, verse: 255))
        XCTAssertEqual(SurahSearch.place(in: "2 255", verseCounts: counts), DailyPlace(surah: 2, verse: 255))
        XCTAssertNil(SurahSearch.place(in: "2:300", verseCounts: counts), "Al-Baqara has 286 ayat")
        XCTAssertNil(SurahSearch.place(in: "3:1", verseCounts: counts), "unknown surah")
        XCTAssertNil(SurahSearch.place(in: "2", verseCounts: counts), "a surah alone isn't an ayah")
    }
}

final class VerseBookmarkTests: XCTestCase {
    private let kursi = VerseReference(surah: 2, verse: 255)
    private let kahf = VerseReference(surah: 18, verse: 10)

    private func bookmark(_ verse: VerseReference, _ title: String, minutesAgo: Double = 0) -> VerseBookmark {
        VerseBookmark(verse: verse, title: title, note: "", occasion: .general,
                      created: Date(timeIntervalSince1970: 1_800_000_000 - minutesAgo * 60))
    }

    func testNewestFirst() {
        let old = bookmark(kursi, "Old", minutesAgo: 10)
        let new = bookmark(kahf, "New")
        XCTAssertEqual(VerseBookmarks.saving(new, in: [old]).map(\.title), ["New", "Old"])
    }

    func testSavingAgainEditsInPlace() {
        var first = bookmark(kursi, "Before")
        let list = VerseBookmarks.saving(first, in: [])
        first.title = "After"
        first.note = "For Laylat al-Qadr"
        let edited = VerseBookmarks.saving(first, in: list)
        XCTAssertEqual(edited.count, 1)
        XCTAssertEqual(edited[0].title, "After")
        XCTAssertEqual(edited[0].note, "For Laylat al-Qadr")
    }

    func testRemoving() {
        let a = bookmark(kursi, "A"), b = bookmark(kahf, "B")
        XCTAssertEqual(VerseBookmarks.removing(a.id, from: [a, b]).map(\.title), ["B"])
    }

    func testOnAVerse() {
        let a = bookmark(kursi, "A"), b = bookmark(kahf, "B"), c = bookmark(kursi, "C", minutesAgo: 5)
        XCTAssertEqual(VerseBookmarks.on(kursi, in: [a, b, c]).map(\.title), ["A", "C"])
    }

    func testAnEmptyTitleShowsTheOccasion() {
        var mark = bookmark(kursi, "  ")
        mark.occasion = .ramadan
        XCTAssertEqual(mark.displayTitle, "Ramadan")
        mark.title = "Night prayer"
        XCTAssertEqual(mark.displayTitle, "Night prayer")
    }

    func testOldSavesWithoutAnOccasionStillLoad() throws {
        let json = #"[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","verse":{"surah":2,"verse":255},"title":"x","note":"","created":0}]"#
        let loaded = try JSONDecoder().decode([VerseBookmark].self, from: Data(json.utf8))
        XCTAssertEqual(loaded.first?.occasion, .general)
    }
}
