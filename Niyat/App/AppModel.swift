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
    private(set) var records: [String: PrayerRecord]

    init() {
        location = SettingsStore.location
        prayerSettings = SettingsStore.prayerSettings
        notificationSettings = SettingsStore.notificationSettings
        hijriAdjustment = SettingsStore.hijriAdjustment
        records = PrayerLog.load()
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

    // MARK: Prayer journal

    func record(for prayer: PrayerName, on day: Date) -> PrayerRecord? {
        records[PrayerLog.key(prayer, on: day)]
    }

    /// Saves how a prayer went. Pass nil to clear it.
    func setRecord(_ record: PrayerRecord?, for prayer: PrayerName, on day: Date) {
        records[PrayerLog.key(prayer, on: day)] = record
        PrayerLog.save(records)
    }

    func isPrayed(_ prayer: PrayerName, on day: Date) -> Bool {
        record(for: prayer, on: day)?.status.countsAsPrayed ?? false
    }

    /// How many of the five prayers were performed on a day (0...5).
    func prayedCount(on day: Date) -> Int {
        PrayerName.obligatory.filter { isPrayed($0, on: day) }.count
    }

    /// The earliest prayer today whose time has come but that hasn't been logged yet.
    func pendingCheckIn(at now: Date) -> PrayerTime? {
        guard let schedule = schedule(for: now) else { return nil }
        return schedule.times.first { time in
            time.name.isObligatory && time.date <= now && record(for: time.name, on: schedule.day) == nil
        }
    }

    /// Consecutive days (up to today) where every prayer was logged and none missed.
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

    func isComplete(_ day: Date) -> Bool {
        PrayerName.obligatory.allSatisfy { record(for: $0, on: day)?.status.keepsStreak ?? false }
    }

    func stats(for days: [Date]) -> PrayerStats {
        PrayerStats(records: records, days: days)
    }
}
