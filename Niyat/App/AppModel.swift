import Foundation
import Observation
import WidgetKit

/// App-wide state. Settings are saved to the App Group so widgets see them.
@MainActor
@Observable
final class AppModel {
    private(set) var location: SavedLocation?
    var prayerSettings: PrayerSettings
    var notificationSettings: NotificationSettings
    var hijriAdjustment: Int
    private(set) var prayedLog: Set<String>

    init() {
        location = SettingsStore.location
        prayerSettings = SettingsStore.prayerSettings
        notificationSettings = SettingsStore.notificationSettings
        hijriAdjustment = SettingsStore.hijriAdjustment
        prayedLog = PrayerLog.load()
    }

    // MARK: Prayer times

    func schedule(for date: Date) -> DaySchedule? {
        guard let location else { return nil }
        return PrayerCalculator.schedule(for: date, location: location, settings: prayerSettings)
    }

    func nextPrayer(after date: Date) -> PrayerTime? {
        guard let location else { return nil }
        return PrayerCalculator.next(after: date, location: location, settings: prayerSettings)
    }

    func currentPrayer(at date: Date) -> PrayerTime? {
        guard let location else { return nil }
        return PrayerCalculator.current(at: date, location: location, settings: prayerSettings)
    }

    // MARK: Updating settings

    func setLocation(_ newLocation: SavedLocation) {
        location = newLocation
        if !prayerSettings.methodChosenManually {
            prayerSettings.method = .recommended(forCountryCode: newLocation.countryCode)
            prayerSettings.madhab = .recommended(forCountryCode: newLocation.countryCode)
        }
        settingsChanged()
    }

    /// Call after changing any setting: saves it and refreshes notifications, widgets and Prayer Lock.
    func settingsChanged() {
        SettingsStore.location = location
        SettingsStore.prayerSettings = prayerSettings
        SettingsStore.notificationSettings = notificationSettings
        SettingsStore.hijriAdjustment = hijriAdjustment
        refresh()
    }

    /// Re-schedules everything that depends on prayer times. Safe to call often.
    func refresh() {
        let location = location
        let prayerSettings = prayerSettings
        let notificationSettings = notificationSettings
        Task {
            await NotificationScheduler.reschedule(location: location, prayerSettings: prayerSettings,
                                                   notificationSettings: notificationSettings)
        }
        WidgetCenter.shared.reloadAllTimelines()
        #if SCREEN_TIME
        FocusScheduler.reschedule()
        #endif
    }

    // MARK: Prayer tracker

    func isPrayed(_ prayer: PrayerName, on day: Date) -> Bool {
        prayedLog.contains(PrayerLog.key(prayer, on: day))
    }

    func togglePrayed(_ prayer: PrayerName, on day: Date) {
        let key = PrayerLog.key(prayer, on: day)
        if prayedLog.contains(key) { prayedLog.remove(key) } else { prayedLog.insert(key) }
        PrayerLog.save(prayedLog)
    }

    /// Consecutive days (up to today) with all five prayers ticked off.
    /// Today counts once it's complete, but an unfinished today doesn't break the streak.
    func streak(asOf date: Date = .now) -> Int {
        let calendar = Calendar.current
        var day = calendar.startOfDay(for: date)
        if !isComplete(day) { day = calendar.date(byAdding: .day, value: -1, to: day) ?? day }
        var count = 0
        while isComplete(day), count < 10_000 {
            count += 1
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        }
        return count
    }

    /// How many of the five prayers were ticked off on a day (0...5).
    func prayedCount(on day: Date) -> Int {
        PrayerName.obligatory.filter { isPrayed($0, on: day) }.count
    }

    private func isComplete(_ day: Date) -> Bool {
        PrayerName.obligatory.allSatisfy { isPrayed($0, on: day) }
    }
}
