import XCTest
@testable import Niyat

final class DailyReadingTests: XCTestCase {
    /// Al-Fatiha 7, Al-Baqarah 286, Al-Imran 200.
    private let counts = [7, 286, 200]

    func testNextStaysInTheSurah() {
        XCTAssertEqual(DailyReading.next(after: DailyPlace(surah: 1, verse: 3), verseCounts: counts), DailyPlace(surah: 1, verse: 4))
    }

    func testNextGoesOnToTheNextSurah() {
        XCTAssertEqual(DailyReading.next(after: DailyPlace(surah: 1, verse: 7), verseCounts: counts), DailyPlace(surah: 2, verse: 1))
    }

    func testNothingAfterTheLastAyah() {
        XCTAssertNil(DailyReading.next(after: DailyPlace(surah: 3, verse: 200), verseCounts: counts))
    }

    func testPreviousGoesBackIntoThePreviousSurah() {
        XCTAssertEqual(DailyReading.previous(before: DailyPlace(surah: 2, verse: 1), verseCounts: counts), DailyPlace(surah: 1, verse: 7))
    }

    func testNothingBeforeTheFirstAyah() {
        XCTAssertNil(DailyReading.previous(before: DailyPlace(surah: 1, verse: 1), verseCounts: counts))
    }

    func testShortAyahStillTakesTheShortestTime() {
        XCTAssertEqual(DailyReading.readingTime(letters: 5), DailyReading.shortestTime)
    }

    func testReadingTimeGrowsWithLength() {
        XCTAssertEqual(DailyReading.readingTime(letters: 150), 10)
    }

    func testLongestAyahIsCapped() {
        // Ayat al-Dayn (2:282) has over 500 letters.
        XCTAssertEqual(DailyReading.readingTime(letters: 540), DailyReading.longestTime)
    }

    func testStartPrefersTheRibbon() {
        let start = DailyReading.start(saved: "2:30", ribbon: DailyPlace(surah: 3, verse: 1), verseCounts: counts)
        XCTAssertEqual(start, DailyPlace(surah: 3, verse: 1))
    }

    func testStartFallsBackToTheSavedPlaceThenAlFatiha() {
        XCTAssertEqual(DailyReading.start(saved: "2:30", ribbon: nil, verseCounts: counts), DailyPlace(surah: 2, verse: 30))
        XCTAssertEqual(DailyReading.start(saved: "", ribbon: nil, verseCounts: counts), DailyPlace(surah: 1, verse: 1))
    }

    func testStartKeepsToARealAyah() {
        // Saved in a reading with more ayat in this surah.
        XCTAssertEqual(DailyReading.start(saved: "1:9", ribbon: nil, verseCounts: counts), DailyPlace(surah: 1, verse: 7))
        XCTAssertEqual(DailyReading.start(saved: "200:1", ribbon: nil, verseCounts: counts), DailyPlace(surah: 1, verse: 1))
    }

    func testPlaceRoundTrips() {
        XCTAssertEqual(DailyPlace(storageKey: DailyPlace(surah: 18, verse: 10).storageKey), DailyPlace(surah: 18, verse: 10))
        XCTAssertNil(DailyPlace(storageKey: "x"))
        XCTAssertNil(DailyPlace(storageKey: "0:1"))
    }

    func testHizbFromQuarterStarts() {
        // Quarters start at keys 1001, 2026, 2044, 2060, 2075 (second hizb starts at the fifth).
        let starts = [1001, 2026, 2044, 2060, 2075]
        XCTAssertEqual(DailyReading.hizb(of: 2005, quarterStarts: starts), 1)
        XCTAssertEqual(DailyReading.hizb(of: 2075, quarterStarts: starts), 2)
    }

    func testAyatLeftInJuzStopsAtTheNextJuz() {
        // Juz 2 starts at 2:142 (Hafs).
        let starts = [DailyPlace(surah: 1, verse: 1), DailyPlace(surah: 2, verse: 142)]
        XCTAssertEqual(DailyReading.ayatLeftInJuz(after: DailyPlace(surah: 2, verse: 3), juzStarts: starts, verseCounts: counts), 138)
        XCTAssertEqual(DailyReading.ayatLeftInJuz(after: DailyPlace(surah: 1, verse: 7), juzStarts: starts, verseCounts: counts), 141)
    }

    func testAyatLeftInTheLastJuzRunsToTheEnd() {
        let starts = [DailyPlace(surah: 1, verse: 1), DailyPlace(surah: 2, verse: 142)]
        XCTAssertEqual(DailyReading.ayatLeftInJuz(after: DailyPlace(surah: 3, verse: 195), juzStarts: starts, verseCounts: counts), 5)
        XCTAssertEqual(DailyReading.ayatLeftInJuz(after: DailyPlace(surah: 3, verse: 200), juzStarts: starts, verseCounts: counts), 0)
    }
}

final class ReadingStatsTests: XCTestCase {
    private let pages = [["1:1", "1:2"], ["2:1", "2:2", "2:3"], []]

    func testOnlyFullyReadPagesCount() {
        XCTAssertEqual(ReadingStats.pagesCompleted(read: ["1:1", "1:2", "2:1"], pages: pages), 1)
        XCTAssertEqual(ReadingStats.pagesCompleted(read: ["1:1", "1:2", "2:1", "2:2", "2:3"], pages: pages), 2)
        XCTAssertEqual(ReadingStats.pagesCompleted(read: [], pages: pages), 0)
    }

    func testDurationReadsNaturally() {
        XCTAssertEqual(ReadingStats.duration(35), "35s")
        XCTAssertEqual(ReadingStats.duration(12 * 60 + 5), "12m")
        XCTAssertEqual(ReadingStats.duration(65 * 60), "1h 05m")
        XCTAssertEqual(ReadingStats.duration(-3), "0s")
    }

    func testPeriodsCoverTheRightDays() {
        XCTAssertEqual(ReadingPeriod.today.days, 1)
        XCTAssertEqual(ReadingPeriod.week.days, 7)
        XCTAssertNil(ReadingPeriod.all.days)
    }

    func testOldSavedDaysStillLoad() throws {
        let json = #"{"verses":["1:1"],"letters":19,"goal":5}"#
        let day = try JSONDecoder().decode(QuranDay.self, from: Data(json.utf8))
        XCTAssertEqual(day.seconds, 0)
        XCTAssertEqual(day.count, 1)
    }

    func testTotalsAddUpDays() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let old = calendar.date(byAdding: .day, value: -20, to: now)!
        let days = [
            QuranProgress.dayKey(for: now): QuranDay(verses: ["1:1", "1:2"], letters: 36, goal: 5, seconds: 40),
            QuranProgress.dayKey(for: yesterday): QuranDay(verses: ["1:2", "1:3"], letters: 30, goal: 5, seconds: 20),
            QuranProgress.dayKey(for: old): QuranDay(verses: ["2:1"], letters: 10, goal: 5, seconds: 5),
        ]
        let today = QuranProgress.totals(days: 1, asOf: now, from: days)
        XCTAssertEqual(today.ayat, 2)
        XCTAssertEqual(today.hasanat, 360)
        let week = QuranProgress.totals(days: 7, asOf: now, from: days)
        XCTAssertEqual(week.seconds, 60)
        XCTAssertEqual(week.verses, ["1:1", "1:2", "1:3"])
        XCTAssertEqual(QuranProgress.totals(days: nil, asOf: now, from: days).ayat, 5)
    }
}
