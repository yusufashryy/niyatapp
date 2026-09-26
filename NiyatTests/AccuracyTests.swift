import XCTest
@testable import Niyat

/// Qibla direction: the app's bearing (Adhan library) must agree with an
/// independent great-circle calculation, and with the published reference values.
final class QiblaAccuracyTests: XCTestCase {
    /// City, latitude, longitude, expected bearing (degrees from true north).
    /// Expected values from the standard great-circle formula; they match
    /// published Qibla tables (e.g. New York 58.48°, London 118.99°).
    private let references: [(String, Double, Double, Double)] = [
        ("New York", 40.7128, -74.0059, 58.482),
        ("London", 51.5074, -0.1278, 118.987),
        ("Sydney", -33.8688, 151.2093, 277.500),
        ("Tokyo", 35.6762, 139.6503, 292.999),
        ("Jakarta", -6.2088, 106.8456, 295.152),
        ("Cairo", 30.0444, 31.2357, 136.137),
        ("Istanbul", 41.0082, 28.9784, 151.621),
        ("Karachi", 24.8607, 67.0011, 267.741),
        ("Cape Town", -33.9249, 18.4241, 23.353),
        ("Los Angeles", 34.0522, -118.2437, 23.857),
        ("Madinah", 24.4672, 39.6112, 176.237),
        ("Kuala Lumpur", 3.139, 101.6869, 292.538),
        ("Lagos", 6.5244, 3.3792, 63.330),
        ("Moscow", 55.7558, 37.6173, 176.356),
        ("Toronto", 43.6532, -79.3832, 54.581),
        ("Mexico City", 19.4326, -99.1332, 46.599),
        ("Reykjavik", 64.1466, -21.9426, 106.118),
        ("Auckland", -36.8485, 174.7633, 261.197),
        ("Dhaka", 23.8103, 90.4125, 277.567),
        ("Riyadh", 24.7136, 46.6753, 243.798),
    ]

    func testAppBearingMatchesReferenceValues() {
        for (city, lat, lon, expected) in references {
            let location = SavedLocation(latitude: lat, longitude: lon, name: city, timeZoneIdentifier: "UTC")
            XCTAssertEqual(PrayerCalculator.qiblaDirection(from: location), expected, accuracy: 0.05, city)
        }
    }

    func testIndependentFormulaMatchesReferenceValues() {
        for (city, lat, lon, expected) in references {
            XCTAssertEqual(QiblaMath.bearing(latitude: lat, longitude: lon), expected, accuracy: 0.01, city)
        }
    }

    func testBearingsAgreeAcrossTheGlobe() {
        // A grid of points everywhere on Earth (away from the Kaaba itself and the poles).
        for lat in stride(from: -60.0, through: 70.0, by: 10) {
            for lon in stride(from: -180.0, through: 170.0, by: 20) {
                let location = SavedLocation(latitude: lat, longitude: lon, name: "", timeZoneIdentifier: "UTC")
                let app = PrayerCalculator.qiblaDirection(from: location)
                let independent = QiblaMath.bearing(latitude: lat, longitude: lon)
                XCTAssertEqual(CompassModel.signedDelta(from: app, to: independent), 0, accuracy: 0.05, "\(lat), \(lon)")
            }
        }
    }

    func testDistanceToKaaba() {
        // London to Makkah is about 4,790 km.
        XCTAssertEqual(QiblaMath.distance(latitude: 51.5074, longitude: -0.1278) / 1000, 4790, accuracy: 25)
    }

    func testCompassMaths() {
        XCTAssertEqual(CompassModel.normalized(-10), 350, accuracy: 0.0001)
        XCTAssertEqual(CompassModel.normalized(725), 5, accuracy: 0.0001)
        XCTAssertEqual(CompassModel.signedDelta(from: 350, to: 10), 20, accuracy: 0.0001)
        XCTAssertEqual(CompassModel.signedDelta(from: 10, to: 350), -20, accuracy: 0.0001)
        XCTAssertEqual(CompassModel.signedDelta(from: 90, to: 270), -180, accuracy: 0.0001)
        // Crossing north must move a little forward, never spin all the way round.
        let next = CompassModel.smoothed(previous: 359, reading: 1)
        XCTAssertGreaterThan(next, 359)
        XCTAssertLessThan(next, 361)
    }
}

/// Quran text: bundled files are byte-for-byte the published ones, the structure
/// matches the standard Hafs count, and the Bismillah is shown correctly.
@MainActor
final class QuranAccuracyTests: XCTestCase {
    /// Verses per surah in the standard (Hafs/Kufan) count, listed independently
    /// of the bundled data. Total 6,236.
    private let hafsVerseCounts = [
        7, 286, 200, 176, 120, 165, 206, 75, 129, 109, 123, 111, 43, 52, 99, 128, 111, 110, 98, 135,
        112, 78, 118, 64, 77, 227, 93, 88, 69, 60, 34, 30, 73, 54, 45, 83, 182, 88, 75, 85,
        54, 53, 89, 59, 37, 35, 38, 29, 18, 45, 60, 49, 62, 55, 78, 96, 29, 22, 24, 13,
        14, 11, 11, 18, 12, 12, 30, 52, 52, 44, 28, 28, 20, 56, 40, 31, 50, 40, 46, 42,
        29, 19, 36, 25, 22, 17, 19, 26, 30, 20, 15, 21, 11, 8, 8, 19, 5, 8, 8, 11,
        11, 8, 3, 9, 5, 4, 7, 3, 6, 3, 5, 4, 5, 6,
    ]

    private func loadedStore() async -> QuranStore {
        let store = QuranStore.shared
        await store.load()
        await store.setEdition(.uthmani)
        return store
    }

    func testEveryEditionIsCompleteAndAligned() async {
        let store = await loadedStore()
        for edition in QuranEdition.allCases {
            await store.setEdition(edition)
            XCTAssertEqual(store.edition, edition)
            let total = (1...114).reduce(0) { $0 + store.verses(for: $1).count }
            // Every Hafs verse must be covered exactly by the reading's own verses.
            var covered = Set<Int>()
            for surah in 1...114 {
                for verse in store.verses(for: surah) {
                    XCTAssertFalse(verse.arabic.isEmpty, "\(edition) \(surah):\(verse.number)")
                    for hafs in verse.hafsNumbers { covered.insert(surah * 1000 + hafs) }
                }
            }
            XCTAssertEqual(covered.count, 6236, "\(edition) must cover every Hafs verse")
            switch edition.riwayah {
            case .hafs:
                XCTAssertEqual(total, 6236, "\(edition)")
                for (index, expected) in hafsVerseCounts.enumerated() {
                    XCTAssertEqual(store.verses(for: index + 1).count, expected, "\(edition) surah \(index + 1)")
                }
                // The Bismillah is a header, never left inside verse 1.
                for surah in 2...114 where surah != 9 {
                    let first = store.verses(for: surah).first?.arabic ?? ""
                    XCTAssertNil(QuranStore.removingBismillah(from: first, bismillah: store.bismillah), "\(edition) surah \(surah)")
                }
            case .warsh, .qalun:
                XCTAssertEqual(total, 6214, "\(edition) uses the Madinan count")
                XCTAssertTrue(store.bismillah.isEmpty)
            }
        }
        await store.setEdition(.uthmani)
    }

    func testFilesMatchPublishedChecksums() {
        XCTAssertTrue(QuranStore.verifyChecksums())
    }

    func testVerseCountsMatchHafs() async {
        let store = await loadedStore()
        XCTAssertEqual(hafsVerseCounts.count, 114)
        XCTAssertEqual(hafsVerseCounts.reduce(0, +), 6236)
        XCTAssertEqual(store.surahs.count, 114)
        for (index, expected) in hafsVerseCounts.enumerated() {
            let surah = index + 1
            XCTAssertEqual(store.verses(for: surah).count, expected, "Surah \(surah)")
            XCTAssertEqual(store.surah(surah)?.totalVerses, expected, "Surah \(surah) metadata")
            XCTAssertEqual(store.verses(for: surah).map(\.number), Array(1...expected), "Surah \(surah) numbering")
            XCTAssertFalse(store.verses(for: surah).contains { $0.translation.isEmpty }, "Surah \(surah) translation")
        }
    }

    func testBismillahIsAHeaderNotPartOfVerseOne() async {
        let store = await loadedStore()
        XCTAssertEqual(store.bismillah, "\u{628}\u{650}\u{633}\u{652}\u{645}\u{650} \u{671}\u{644}\u{644}\u{651}\u{64E}\u{647}\u{650} \u{671}\u{644}\u{631}\u{651}\u{64E}\u{62D}\u{652}\u{645}\u{64E}\u{670}\u{646}\u{650} \u{671}\u{644}\u{631}\u{651}\u{64E}\u{62D}\u{650}\u{64A}\u{645}\u{650}")
        // Al-Fatiha: the Bismillah IS verse 1.
        XCTAssertEqual(store.verses(for: 1).first?.arabic, store.bismillah)
        // At-Tawbah: no Bismillah at all.
        XCTAssertEqual(store.surah(9)?.hasBismillahHeader, false)
        XCTAssertTrue(store.verses(for: 9).first?.arabic.hasPrefix("\u{628}\u{64E}\u{631}\u{64E}\u{627}\u{653}\u{621}\u{64E}\u{629}\u{64C}") ?? false)
        // Every other surah: verse 1 no longer starts with it.
        for surah in 2...114 where surah != 9 {
            let first = store.verses(for: surah).first?.arabic ?? ""
            XCTAssertNil(QuranStore.removingBismillah(from: first, bismillah: store.bismillah), "Surah \(surah)")
            XCTAssertFalse(first.isEmpty, "Surah \(surah)")
        }
        // Well-known verses (written as exact Unicode so diacritic order can't differ).
        XCTAssertEqual(store.verses(for: 112).first?.arabic, "\u{642}\u{64F}\u{644}\u{652} \u{647}\u{64F}\u{648}\u{64E} \u{671}\u{644}\u{644}\u{651}\u{64E}\u{647}\u{64F} \u{623}\u{64E}\u{62D}\u{64E}\u{62F}\u{64C}")
        XCTAssertEqual(store.verses(for: 2).first?.arabic, "\u{627}\u{644}\u{653}\u{645}\u{653}")
        XCTAssertEqual(store.verses(for: 95).first?.arabic, "\u{648}\u{64E}\u{671}\u{644}\u{62A}\u{651}\u{650}\u{64A}\u{646}\u{650} \u{648}\u{64E}\u{671}\u{644}\u{632}\u{651}\u{64E}\u{64A}\u{652}\u{62A}\u{64F}\u{648}\u{646}\u{650}")
        XCTAssertEqual(store.verses(for: 114).last?.arabic, "\u{645}\u{650}\u{646}\u{64E} \u{671}\u{644}\u{652}\u{62C}\u{650}\u{646}\u{651}\u{64E}\u{629}\u{650} \u{648}\u{64E}\u{671}\u{644}\u{646}\u{651}\u{64E}\u{627}\u{633}\u{650}")
        XCTAssertTrue(store.verses(for: 2)[254].arabic.hasPrefix("\u{671}\u{644}\u{644}\u{651}\u{64E}\u{647}\u{64F} \u{644}\u{64E}\u{627}\u{653} \u{625}\u{650}\u{644}\u{64E}\u{670}\u{647}\u{64E} \u{625}\u{650}\u{644}\u{651}\u{64E}\u{627} \u{647}\u{64F}\u{648}\u{64E}"))
    }
}

/// Letter counting for the reward estimate (Tirmidhi 2910).
final class LetterCountTests: XCTestCase {
    func testAlifLamMimIsThreeLetters() {
        // The hadith's own example: Alif is a letter, Lam is a letter and Mim is a letter.
        XCTAssertEqual(ArabicLetters.count(in: "\u{627}\u{644}\u{653}\u{645}\u{653}"), 3) // الٓمٓ as in Tanzil 2:1
    }

    func testDiacriticsAreNotLetters() {
        // بِسْمِ = ba, sin, mim (kasra and sukun are marks)
        XCTAssertEqual(ArabicLetters.count(in: "\u{628}\u{650}\u{633}\u{652}\u{645}\u{650}"), 3)
        // Dagger alif, small waw and tatweel are not counted; alif wasla is.
        XCTAssertEqual(ArabicLetters.count(in: "\u{670}\u{6E5}\u{640}"), 0)
        XCTAssertEqual(ArabicLetters.count(in: "\u{671}"), 1)
    }
}

/// Qur'an goal and streak rules.
final class QuranProgressTests: XCTestCase {
    private var savedDays: Data?
    private var savedGoal: Int = 0

    override func setUp() {
        savedDays = AppGroup.defaults.data(forKey: "quran.days")
        savedGoal = AppGroup.defaults.integer(forKey: "quran.dailyGoal")
        AppGroup.defaults.removeObject(forKey: "quran.days")
    }

    override func tearDown() {
        AppGroup.defaults.set(savedDays, forKey: "quran.days")
        AppGroup.defaults.set(savedGoal, forKey: "quran.dailyGoal")
    }

    func testGoalCompletesOnceAndNeverDoubleCounts() {
        let now = Date()
        QuranProgress.setGoal(2, at: now)
        XCTAssertFalse(QuranProgress.recordRead(surah: 1, verse: 1, letters: 19, at: now))
        XCTAssertFalse(QuranProgress.recordRead(surah: 1, verse: 1, letters: 19, at: now), "same verse twice")
        XCTAssertEqual(QuranProgress.day(now).count, 1)
        XCTAssertTrue(QuranProgress.recordRead(surah: 1, verse: 2, letters: 17, at: now), "goal reached")
        XCTAssertFalse(QuranProgress.recordRead(surah: 1, verse: 3, letters: 12, at: now), "celebrate only once")
        XCTAssertEqual(QuranProgress.day(now).letters, 19 + 17 + 12)
        XCTAssertEqual(QuranProgress.currentStreak(asOf: now), 1)
    }

    func testChangingGoalDoesNotRewriteHistory() {
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date())!
        QuranProgress.setGoal(1, at: yesterday)
        QuranProgress.recordRead(surah: 2, verse: 1, letters: 3, at: yesterday)
        QuranProgress.setGoal(50)
        XCTAssertTrue(QuranProgress.day(yesterday).isComplete)
        XCTAssertEqual(QuranProgress.day(yesterday).goal, 1)
        XCTAssertEqual(QuranProgress.currentStreak(), 1, "yesterday still counts while today is in progress")
    }
}

/// Settings from older versions keep working.
final class SettingsMigrationTests: XCTestCase {
    func testOldReminderSettingBecomesAlertTimings() throws {
        let json = #"{"enabledPrayers":["fajr","isha"],"reminderMinutesBefore":10}"#.data(using: .utf8)!
        let settings = try JSONDecoder().decode(NotificationSettings.self, from: json)
        XCTAssertEqual(settings.enabledPrayers, [.fajr, .isha])
        XCTAssertEqual(settings.timings, [.before10, .atTime, .after30])
    }
}

/// The prayer journal's statistics.
final class PrayerStatsTests: XCTestCase {
    func testCountsRatesAndReasons() {
        let day = Date(timeIntervalSince1970: 1_790_000_000)
        let records: [String: PrayerRecord] = [
            PrayerLog.key(.fajr, on: day): PrayerRecord(status: .missed, reason: .sleep),
            PrayerLog.key(.dhuhr, on: day): PrayerRecord(status: .onTime),
            PrayerLog.key(.asr, on: day): PrayerRecord(status: .late, reason: .work),
            PrayerLog.key(.maghrib, on: day): PrayerRecord(status: .onTime),
            PrayerLog.key(.isha, on: day): PrayerRecord(status: .excused),
        ]
        let stats = PrayerStats(records: records, days: [day])
        XCTAssertEqual(stats.logged, 5)
        XCTAssertEqual(stats.prayed, 3)
        XCTAssertEqual(stats.missed, 1)
        XCTAssertEqual(stats.onTimeRate, 0.5, accuracy: 0.0001) // 2 on time of 4 non-excused
        XCTAssertEqual(stats.reasons[.sleep], 1)
        XCTAssertEqual(stats.reasons[.work], 1)
        XCTAssertNotNil(stats.hardestPrayer)
    }

    func testStatusRules() {
        XCTAssertTrue(PrayerStatus.late.countsAsPrayed)
        XCTAssertFalse(PrayerStatus.missed.countsAsPrayed)
        XCTAssertTrue(PrayerStatus.excused.keepsStreak)
        XCTAssertFalse(PrayerStatus.missed.keepsStreak)
    }
}

final class QuranReminderSettingsTests: XCTestCase {
    /// Settings saved by an older version (fewer fields) must still load.
    func testOlderSavedSettingsDecode() throws {
        let old = #"{"isEnabled":true,"morningMinute":420,"afternoonMinute":900,"sendCompletionMessage":true}"#
        let settings = try JSONDecoder().decode(QuranReminderSettings.self, from: Data(old.utf8))
        XCTAssertTrue(settings.isEnabled)
        XCTAssertEqual(settings.morningMinute, 420)
        XCTAssertEqual(settings.afternoonMinute, 900)
        XCTAssertTrue(settings.sendCompletionMessage)
        XCTAssertTrue(settings.morningEnabled)
        XCTAssertTrue(settings.afternoonEnabled)
        XCTAssertFalse(settings.verseOfDayEnabled)
        XCTAssertFalse(settings.kahfEnabled)
        XCTAssertEqual(settings.eveningMinute, 21 * 60)
    }

    func testRoundTrip() throws {
        var settings = QuranReminderSettings()
        settings.kahfEnabled = true
        settings.verseOfDayMinute = 6 * 60 + 30
        let decoded = try JSONDecoder().decode(QuranReminderSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded, settings)
    }
}

final class RecitationMatcherTests: XCTestCase {
    private func states(_ expected: String, _ heard: String) -> [RecitationMatcher.WordState] {
        RecitationMatcher.align(expected: RecitationMatcher.words(expected).map(RecitationMatcher.normalize),
                                heard: RecitationMatcher.words(heard).map(RecitationMatcher.normalize))
    }

    private let verse = "الْحَمْدُ لِلَّهِ رَبِّ الْعَالَمِينَ"

    func testNormalizeIgnoresHarakatAndSpellingVariants() {
        XCTAssertEqual(RecitationMatcher.normalize("الرَّحْمَٰنِ"), RecitationMatcher.normalize("الرحمن"))
        XCTAssertEqual(RecitationMatcher.normalize("إِيَّاكَ"), RecitationMatcher.normalize("اياك"))
        XCTAssertEqual(RecitationMatcher.normalize("رَحْمَةً"), RecitationMatcher.normalize("رحمه"))
    }

    func testFollowsAlong() {
        XCTAssertEqual(states(verse, ""), [.pending, .pending, .pending, .pending])
        XCTAssertEqual(states(verse, "الحمد لله"), [.matched, .matched, .pending, .pending])
        XCTAssertEqual(states(verse, "الحمد لله رب العالمين"), [.matched, .matched, .matched, .matched])
    }

    func testExtraAndRepeatedWordsAreNotMistakes() {
        XCTAssertEqual(states(verse, "اعوذ بالله الحمد لله رب العالمين"), [.matched, .matched, .matched, .matched])
        XCTAssertEqual(states(verse, "الحمد لله الحمد لله رب العالمين"), [.matched, .matched, .matched, .matched])
    }

    func testSmallRecognitionDifferencesAreForgiven() {
        XCTAssertEqual(states(verse, "الحمد لله رب العلمين"), [.matched, .matched, .matched, .matched])
    }

    func testSkippedAndDifferentWords() {
        XCTAssertEqual(states(verse, "الحمد لله العالمين"), [.matched, .matched, .skipped, .matched])
        XCTAssertEqual(states(verse, "الحمد لله رب الناس"), [.matched, .matched, .matched, .different])
    }

    func testUnrelatedSpeechIsIgnored() {
        XCTAssertEqual(states(verse, "كلام اخر تماما"), [.pending, .pending, .pending, .pending])
    }
}

final class QuranicDuaTests: XCTestCase {
    /// Every dua points at real verses, and the text there is a supplication.
    @MainActor
    func testDuaReferencesExist() async {
        let store = QuranStore.shared
        await store.load()
        await store.setEdition(.uthmani)
        for group in QuranicDua.all {
            for dua in group.duas {
                let count = store.surah(dua.surah)?.totalVerses ?? 0
                XCTAssertTrue(dua.verses.lowerBound >= 1 && dua.verses.upperBound <= count, dua.reference)
                let text = dua.verses.compactMap { store.verse(VerseReference(surah: dua.surah, verse: $0))?.arabic }
                    .joined(separator: " ")
                let letters = RecitationMatcher.normalize(text)
                // "Rabb" (Lord) or "a'udhu" (I seek refuge) or Yunus's "la ilaha illa anta".
                XCTAssertTrue(letters.contains("رب") || letters.contains("اعوذ") || letters.contains("لاالهالاانت"),
                              "\(dua.reference) doesn't look like a dua")
            }
        }
    }

    func testEveryAyahURL() {
        let dosari = Reciter.all.first { $0.name == "Yasser Al-Dosari" }
        XCTAssertEqual(dosari?.url(globalAyah: 8, surah: 2, verse: 1).absoluteString,
                       "https://everyayah.com/data/Yasser_Ad-Dussary_128kbps/002001.mp3")
        XCTAssertEqual(Reciter.default.url(globalAyah: 8, surah: 2, verse: 1).absoluteString,
                       "https://cdn.islamic.network/quran/audio/128/ar.alafasy/8.mp3")
    }
}
