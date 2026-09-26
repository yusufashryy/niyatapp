import XCTest
@testable import Niyat

final class PrayerCalculatorTests: XCTestCase {
    private let london = SavedLocation(latitude: 51.5074, longitude: -0.1278, name: "London",
                                       timeZoneIdentifier: "Europe/London", countryCode: "GB")

    private func date(_ string: String, in timeZone: TimeZone) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: string)!
    }

    func testScheduleHasSixTimesInOrder() throws {
        let schedule = try XCTUnwrap(PrayerCalculator.schedule(for: date("2026-03-15 12:00", in: SavedLocation.makkah.timeZone),
                                                               location: .makkah, settings: PrayerSettings()))
        XCTAssertEqual(schedule.times.map(\.name), PrayerName.allCases)
        XCTAssertEqual(schedule.times.map(\.date), schedule.times.map(\.date).sorted())
    }

    func testMakkahDhuhrIsAroundMidday() throws {
        let tz = SavedLocation.makkah.timeZone
        let schedule = try XCTUnwrap(PrayerCalculator.schedule(for: date("2026-03-15 12:00", in: tz),
                                                               location: .makkah, settings: PrayerSettings()))
        let dhuhr = try XCTUnwrap(schedule.time(for: .dhuhr)).date
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz
        XCTAssertEqual(calendar.component(.hour, from: dhuhr), 12)
    }

    func testUpcomingCrossesMidnight() {
        let lateNight = date("2026-06-01 23:30", in: london.timeZone)
        let upcoming = PrayerCalculator.upcoming(after: lateNight, count: 5, location: london, settings: PrayerSettings())
        XCTAssertEqual(upcoming.map(\.name), PrayerName.obligatory)
        XCTAssertTrue(upcoming.allSatisfy { $0.date > lateNight })
    }

    func testCurrentPrayerAfterIshaIsIsha() {
        let lateNight = date("2026-06-01 23:59", in: london.timeZone)
        XCTAssertEqual(PrayerCalculator.current(at: lateNight, location: london, settings: PrayerSettings())?.name, .isha)
    }

    func testHanafiAsrIsLater() throws {
        let day = date("2026-03-15 12:00", in: london.timeZone)
        var hanafi = PrayerSettings()
        hanafi.madhab = .recommended(forCountryCode: "PK")
        let standardAsr = try XCTUnwrap(PrayerCalculator.schedule(for: day, location: london, settings: PrayerSettings())?.time(for: .asr)).date
        let hanafiAsr = try XCTUnwrap(PrayerCalculator.schedule(for: day, location: london, settings: hanafi)?.time(for: .asr)).date
        XCTAssertGreaterThan(hanafiAsr, standardAsr)
    }

    func testAdjustmentShiftsTime() throws {
        let day = date("2026-03-15 12:00", in: london.timeZone)
        var adjusted = PrayerSettings()
        adjusted.setAdjustment(5, for: .maghrib)
        let base = try XCTUnwrap(PrayerCalculator.schedule(for: day, location: london, settings: PrayerSettings())?.time(for: .maghrib)).date
        let shifted = try XCTUnwrap(PrayerCalculator.schedule(for: day, location: london, settings: adjusted)?.time(for: .maghrib)).date
        XCTAssertEqual(shifted.timeIntervalSince(base), 5 * 60, accuracy: 1)
    }

    func testQiblaFromNewYork() {
        let newYork = SavedLocation(latitude: 40.7128, longitude: -74.0059, name: "New York",
                                    timeZoneIdentifier: "America/New_York", countryCode: "US")
        XCTAssertEqual(PrayerCalculator.qiblaDirection(from: newYork), 58.48, accuracy: 0.5)
    }

    // Compares titles rather than Adhan's enum values so the tests don't have to link Adhan themselves.
    func testRecommendedMethods() {
        var settings = PrayerSettings()
        settings.method = .recommended(forCountryCode: "US")
        XCTAssertEqual(settings.method.title, "ISNA (North America)")
        settings.method = .recommended(forCountryCode: "sa")
        XCTAssertEqual(settings.method.title, "Umm al-Qura, Makkah")
        settings.method = .recommended(forCountryCode: nil)
        XCTAssertEqual(settings.method.title, "Muslim World League")
        settings.madhab = .recommended(forCountryCode: "PK")
        XCTAssertEqual(settings.madhab.title, "Hanafi")
    }

    func testOldSettingsStillDecode() throws {
        let json = #"{"method":"egyptian"}"#.data(using: .utf8)!
        let settings = try JSONDecoder().decode(PrayerSettings.self, from: json)
        XCTAssertEqual(settings.method.title, "Egyptian General Authority")
        XCTAssertEqual(settings.madhab.title, "Standard")
        XCTAssertEqual(settings.highLatitude, .automatic)
    }

    func testJumuahOnFriday() {
        let friday = date("2026-09-25 12:00", in: .current)
        XCTAssertEqual(PrayerName.dhuhr.displayName(on: friday), "Jumu'ah")
        XCTAssertEqual(PrayerName.asr.displayName(on: friday), "Asr")
    }
}

@MainActor
final class QuranStoreTests: XCTestCase {
    func testBundledQuranIsComplete() async {
        let store = QuranStore.shared
        await store.load()
        await store.setEdition(.uthmani)
        XCTAssertNil(store.loadError)
        XCTAssertEqual(store.surahs.count, 114)
        let total = store.surahs.reduce(0) { $0 + store.verses(for: $1.id).count }
        XCTAssertEqual(total, 6236)
        for surah in store.surahs {
            XCTAssertEqual(store.verses(for: surah.id).count, surah.totalVerses, "Surah \(surah.id)")
            XCTAssertFalse(store.verses(for: surah.id).contains { $0.translation.isEmpty }, "Surah \(surah.id)")
        }
    }

    func testDailyVersesAreVerbatim() async {
        let store = QuranStore.shared
        await store.load()
        await store.setEdition(.uthmani)
        for daily in DailyVerse.all {
            let verse = store.verse(VerseReference(surah: daily.surah, verse: daily.ayah))
            XCTAssertEqual(verse?.arabic, daily.arabic)
            XCTAssertEqual(verse?.translation, daily.english)
        }
    }
}
