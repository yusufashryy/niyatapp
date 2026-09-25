#if DEBUG
import Adhan
import Foundation

/// Sample data for the automated demo tour (NiyatiUITests). Debug builds only.
///
/// - `-demo`: London, a few days of ticked-off prayers, some tasbih counts.
/// - `-demoOnboarding`: wipes everything so the welcome screens show.
enum DemoMode {
    static func prepareIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
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

        // Six full days plus this morning's prayers, for a streak.
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        var log: Set<String> = []
        for offset in 1...6 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            for prayer in PrayerName.obligatory { log.insert(PrayerLog.key(prayer, on: day)) }
        }
        log.insert(PrayerLog.key(.fajr, on: today))
        log.insert(PrayerLog.key(.dhuhr, on: today))
        PrayerLog.save(log)

        TasbihCounter.count = 21
        TasbihCounter.lifetimeCount = 1_254
        TasbihCounter.target = 33
        TasbihCounter.dhikr = .subhanAllah
    }
}
#endif
