import XCTest
@testable import Niyat

final class HadithTests: XCTestCase {
    private static let index: HadithIndex? = {
        guard let url = Bundle.main.url(forResource: "hadith-en", withExtension: "hadith"),
              let data = try? Data(contentsOf: url) else { return nil }
        return (try? HadithFile.decode(compressed: data)).map(HadithIndex.init)
    }()

    private func bundled() throws -> HadithIndex { try XCTUnwrap(Self.index, "hadith-en.hadith is bundled") }

    // MARK: The bundled file

    func testOnlySahihAndHasanAreBundled() throws {
        let index = try bundled()
        XCTAssertGreaterThan(index.hadiths.count, 2000)
        // Decoding would fail on any other level; check nothing weak slipped in by its wording.
        XCTAssertFalse(index.hadiths.contains { $0.grade.localizedCaseInsensitiveContains("weak") })
        XCTAssertFalse(index.hadiths.contains { $0.grade.localizedCaseInsensitiveContains("da'if") })
    }

    func testEveryHadithHasTextSourceAndTopic() throws {
        for hadith in try bundled().hadiths {
            XCTAssertFalse(hadith.text.isEmpty, "\(hadith.id) has text")
            XCTAssertFalse(hadith.source.isEmpty, "\(hadith.id) has a source")
            XCTAssertFalse(hadith.topics.isEmpty, "\(hadith.id) has a topic")
        }
    }

    func testIdsAreUnique() throws {
        let ids = try bundled().hadiths.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testTopicsHaveParentsInTheFile() throws {
        let index = try bundled()
        XCTAssertFalse(index.rootTopics.isEmpty)
        for topic in index.file.topics where topic.parent != 0 {
            XCTAssertNotNil(index.topic(topic.parent), "parent of \(topic.id)")
        }
    }

    func testTopicIncludesItsSubtopicsHadiths() throws {
        let index = try bundled()
        for root in index.rootTopics {
            let all = Set(index.hadiths(in: root).map(\.id))
            for child in index.subtopics(of: root) {
                XCTAssertTrue(Set(index.hadiths(in: child).map(\.id)).isSubset(of: all))
            }
        }
    }

    // MARK: Search

    func testSearchFindsIntentions() throws {
        let results = try bundled().search("intentions")
        XCTAssertTrue(results.contains { $0.title.localizedCaseInsensitiveContains("intention") })
    }

    func testEveryScenarioFindsHadiths() throws {
        let index = try bundled()
        for scenario in HadithScenario.all {
            XCTAssertGreaterThan(index.search(scenario).count, 2, scenario.title)
        }
    }

    func testAngerScenarioPutsAngerFirst() throws {
        let first = try XCTUnwrap(try bundled().search(HadithScenario.all[0]).first)
        XCTAssertTrue((first.title + first.text).localizedCaseInsensitiveContains("ang"))
    }

    func testHadithOfTheDayIsStableForADay() throws {
        let index = try bundled()
        let morning = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(index.hadithOfTheDay(morning)?.id, index.hadithOfTheDay(morning.addingTimeInterval(60))?.id)
    }

    // MARK: Text rules

    func testFoldIgnoresAccentsAndMarks() {
        XCTAssertEqual(HadithIndex.fold("‘Abdullāh"), "abdullah")
    }

    func testWordsDropFillers() {
        XCTAssertEqual(HadithIndex.words(in: "What about the anger of my heart?"), ["anger", "heart"])
    }

    func testContainsMatchesWordStartsOnly() {
        XCTAssertTrue(HadithIndex.contains("the prayer at night", word: "pray"))
        XCTAssertFalse(HadithIndex.contains("he betrayed", word: "tray"))
    }

    func testSearchNeedsEveryWordWhenPossible() {
        let file = HadithFixture.file([("Patience in prayer", "text"), ("Patience", "text"), ("Prayer", "text")])
        let results = HadithIndex(file).search("patience prayer")
        XCTAssertEqual(results.map(\.title), ["Patience in prayer"])
    }

    func testSearchFallsBackToSomeWords() {
        let file = HadithFixture.file([("Patience", "text"), ("Other", "text")])
        XCTAssertEqual(HadithIndex(file).search("patience zebra").map(\.title), ["Patience"])
    }

    func testTitleMatchRanksAboveTextMatch() {
        let file = HadithFixture.file([("Other", "about charity"), ("Charity", "text")])
        XCTAssertEqual(HadithIndex(file).search("charity").map(\.title), ["Charity", "Other"])
    }

    // MARK: Sharing

    func testHadithShareTextNamesSourceAndGrade() throws {
        let hadith = try XCTUnwrap(try bundled().hadiths.first)
        let text = QuranShareContent.hadith(hadith).plainText(includingTranslation: false)
        XCTAssertTrue(text.hasPrefix(hadith.text))
        XCTAssertTrue(text.contains(hadith.source))
        XCTAssertTrue(text.contains(hadith.level.title))
        XCTAssertFalse(text.contains(hadith.arabic))
    }
}

private enum HadithFixture {
    static func file(_ items: [(title: String, text: String)]) -> HadithFile {
        let hadiths = items.enumerated().map { number, item in
            "{\"id\":\(number),\"title\":\"\(item.title)\",\"text\":\"\(item.text)\",\"arabic\":\"\",\"source\":\"s\",\"grade\":\"g\",\"level\":\"sahih\",\"explanation\":\"\",\"lessons\":[],\"topics\":[1]}"
        }.joined(separator: ",")
        let json = "{\"version\":\"v\",\"topics\":[[1,0,\"Topic\",1]],\"hadiths\":[\(hadiths)]}"
        return try! JSONDecoder().decode(HadithFile.self, from: Data(json.utf8))
    }
}

final class HadithReminderTests: XCTestCase {
    private let index = HadithIndex(HadithFixtureFile.make(count: 30))

    func testOffSchedulesNothing() {
        XCTAssertTrue(HadithReminders.plan(settings: HadithReminderSettings(), index: index, now: .now).isEmpty)
    }

    func testAWeekAheadAtTheChosenTime() {
        var settings = HadithReminderSettings()
        settings.isEnabled = true
        settings.minute = 9 * 60
        let calendar = Calendar.current
        let earlyMorning = calendar.date(bySettingHour: 6, minute: 0, second: 0, of: Date(timeIntervalSince1970: 1_800_000_000))!
        let plan = HadithReminders.plan(settings: settings, index: index, now: earlyMorning)
        XCTAssertEqual(plan.count, HadithReminders.daysAhead)
        XCTAssertEqual(calendar.component(.hour, from: plan[0].date), 9)
        XCTAssertTrue(calendar.isDate(plan[0].date, inSameDayAs: earlyMorning))
    }

    func testSameClockTimeOnTheDayTheClocksChange() {
        var settings = HadithReminderSettings()
        settings.isEnabled = true
        settings.minute = 12 * 60 + 30
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        // 8 March 2026: US clocks go forward at 2 am. 1 November 2026: back at 2 am.
        for (year, month, day) in [(2026, 3, 8), (2026, 11, 1)] {
            let morning = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 0, minute: 30))!
            let plan = HadithReminders.plan(settings: settings, index: index, now: morning, calendar: calendar)
            XCTAssertEqual(calendar.component(.hour, from: plan[0].date), 12, "\(month)/\(day)")
            XCTAssertEqual(calendar.component(.minute, from: plan[0].date), 30, "\(month)/\(day)")
            XCTAssertTrue(calendar.isDate(plan[0].date, inSameDayAs: morning))
        }
    }

    func testMinuteOfAClockTime() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 18, minute: 45))!
        XCTAssertEqual(HadithReminderSettings.minute(of: date, calendar: calendar), 18 * 60 + 45)
    }

    func testTodayIsSkippedOnceItsTimeHasPassed() {
        var settings = HadithReminderSettings()
        settings.isEnabled = true
        settings.minute = 9 * 60
        let calendar = Calendar.current
        let evening = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: Date(timeIntervalSince1970: 1_800_000_000))!
        let plan = HadithReminders.plan(settings: settings, index: index, now: evening)
        XCTAssertEqual(plan.count, HadithReminders.daysAhead - 1)
        XCTAssertFalse(calendar.isDate(plan[0].date, inSameDayAs: evening))
    }

    func testSameHadithAsTheHadithTabThatDay() {
        var settings = HadithReminderSettings()
        settings.isEnabled = true
        let now = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let first = HadithReminders.plan(settings: settings, index: index, now: now)[0]
        XCTAssertEqual(first.hadith.id, index.hadithOfTheDay(first.date)?.id)
    }

    func testOldSavedSettingsStillLoad() throws {
        let settings = try JSONDecoder().decode(HadithReminderSettings.self, from: Data("{}".utf8))
        XCTAssertFalse(settings.isEnabled)
        XCTAssertEqual(settings.minute, 12 * 60)
    }
}

private enum HadithFixtureFile {
    static func make(count: Int) -> HadithFile {
        let hadiths = (0..<count).map {
            "{\"id\":\($0),\"title\":\"T\($0)\",\"text\":\"x\",\"arabic\":\"\",\"source\":\"s\",\"grade\":\"g\",\"level\":\"sahih\",\"explanation\":\"\",\"lessons\":[],\"topics\":[1]}"
        }.joined(separator: ",")
        let json = "{\"version\":\"v\",\"topics\":[[1,0,\"Topic\",1]],\"hadiths\":[\(hadiths)]}"
        return try! JSONDecoder().decode(HadithFile.self, from: Data(json.utf8))
    }
}

final class HadithLibraryRulesTests: XCTestCase {
    func testSavingPutsTheNewestFirstAndTogglesOff() {
        XCTAssertEqual(SavedHadiths.toggled(3, in: [1, 2]), [3, 1, 2])
        XCTAssertEqual(SavedHadiths.toggled(1, in: [3, 1, 2]), [3, 2])
    }

    func testTopicCountMatchesItsHadiths() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "hadith-en", withExtension: "hadith"))
        let index = HadithIndex(try HadithFile.decode(compressed: Data(contentsOf: url)))
        for topic in index.rootTopics + index.rootTopics.flatMap(index.subtopics) {
            XCTAssertEqual(index.count(in: topic), index.hadiths(in: topic).count, topic.title)
        }
    }
}
