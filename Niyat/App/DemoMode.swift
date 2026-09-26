#if DEBUG
import Adhan
import Foundation

/// Sample data for the automated demo tour (NiyatUITests). Debug builds only.
///
/// - `-demo`: London, a few days of ticked-off prayers, some tasbih counts.
/// - `-demoOnboarding`: wipes everything so the welcome screens show.
enum DemoMode {
    static func prepareIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        // The walkthrough would cover the screens the tour photographs.
        if arguments.contains("-demo") || arguments.contains("-demoOnboarding") {
            UserDefaults.standard.set(true, forKey: TutorialView.seenKey)
        }
        if arguments.contains("-demoOnboarding") {
            UserDefaults.standard.set(false, forKey: "hasOnboarded")
            SettingsStore.location = nil
        } else if arguments.contains("-demo") {
            seed()
        }
    }

    private static func seed() {
        let london = SavedLocation(latitude: 51.5074, longitude: -0.1278, name: "London, United Kingdom",
                                   timeZoneIdentifier: "Europe/London", countryCode: "GB")
        SettingsStore.location = london
        var settings = PrayerSettings()
        settings.method = .recommended(forCountryCode: "GB")
        SettingsStore.prayerSettings = settings
        SettingsStore.notificationSettings = NotificationSettings()
        UserDefaults.standard.set(true, forKey: "hasOnboarded")

        // Five weeks of check-ins so the Stats calendar has something to show:
        // mostly on time, a few late or missed Fajrs, and a six-day streak.
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        var records: [String: PrayerRecord] = [:]
        for offset in 1...35 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            for prayer in PrayerName.obligatory {
                var record = PrayerRecord(status: .onTime)
                if offset > 6 {
                    switch (prayer, offset % 5) {
                    case (.fajr, 0): record = PrayerRecord(status: .missed, reason: .sleep)
                    case (.fajr, 2): record = PrayerRecord(status: .late, reason: .sleep)
                    case (.asr, 3): record = PrayerRecord(status: .late, reason: .work)
                    case (.isha, 4) where offset % 3 == 0: record = PrayerRecord(status: .missed, reason: .forgot)
                    case (.dhuhr, 1) where offset % 2 == 0: record = PrayerRecord(status: .late, reason: .school)
                    default: break
                    }
                }
                records[PrayerLog.key(prayer, on: day)] = record
            }
        }
        records[PrayerLog.key(.fajr, on: today)] = PrayerRecord(status: .onTime)
        records[PrayerLog.key(.dhuhr, on: today)] = PrayerRecord(status: .late, reason: .work)
        PrayerLog.save(records)

        // A Qur'an habit: 10 ayat a day for the last 9 days, 6 so far today.
        var quranDays: [String: QuranDay] = [:]
        for offset in 0...9 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let read = offset == 0 ? 6 : 10 + (offset % 3) * 4
            var entry = QuranDay(goal: 10)
            entry.verses = Set((1...read).map { "2:\($0 + offset * 20)" })
            entry.letters = read * 38
            if read >= 10 { entry.completedAt = day.addingTimeInterval(20 * 3600) }
            quranDays[QuranProgress.dayKey(for: day.addingTimeInterval(12 * 3600))] = entry
        }
        AppGroup.defaults.setEncoded(quranDays, forKey: "quran.days")
        QuranProgress.dailyGoal = 10
        ThemeManager.shared.select(AppTheme.onyx.id)

        TasbihCounter.count = 21
        TasbihCounter.lifetimeCount = 1_254
        TasbihCounter.target = 33
        TasbihCounter.dhikr = .subhanAllah
    }
}
#endif
