import SwiftUI
import WidgetKit

struct PrayerEntry: TimelineEntry {
    let date: Date
    let locationName: String?
    let schedule: DaySchedule?
    let next: PrayerTime?
    let current: PrayerTime?
    var records: [String: PrayerRecord] = [:]
    var quranToday = QuranDay(goal: 0)
    var quranGoal: Int?
    var quranStreak = 0

    /// What every entry shows besides the times: read from storage once per
    /// timeline, not once per entry (widgets have little time and memory).
    struct Progress {
        var records: [String: PrayerRecord] = [:]
        var quranToday = QuranDay(goal: 0)
        var quranGoal: Int?
        var quranStreak = 0

        static func load() -> Progress {
            Progress(records: PrayerLog.load(), quranToday: QuranProgress.day(),
                     quranGoal: QuranProgress.dailyGoal, quranStreak: QuranProgress.currentStreak())
        }
    }

    func record(for prayer: PrayerName) -> PrayerRecord? {
        guard let day = schedule?.day else { return nil }
        return records[PrayerLog.key(prayer, on: day)]
    }

    /// Consecutive days with every prayer logged and none missed.
    var prayerStreak: Int {
        let calendar = Calendar.current
        func complete(_ day: Date) -> Bool {
            PrayerName.obligatory.allSatisfy { records[PrayerLog.key($0, on: day)]?.status.keepsStreak ?? false }
        }
        var day = calendar.startOfDay(for: date)
        if !complete(day) { day = calendar.date(byAdding: .day, value: -1, to: day) ?? day }
        var count = 0
        while complete(day), count < 10_000 {
            count += 1
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        }
        return count
    }

    var hasLocation: Bool { locationName != nil }

    static func make(at date: Date, progress: Progress = .load()) -> PrayerEntry {
        guard let location = SettingsStore.location else {
            return PrayerEntry(date: date, locationName: nil, schedule: nil, next: nil, current: nil)
        }
        let settings = SettingsStore.prayerSettings
        return PrayerEntry(
            date: date,
            locationName: location.name,
            schedule: PrayerCalculator.schedule(for: date, location: location, settings: settings),
            next: PrayerCalculator.next(after: date, location: location, settings: settings),
            current: PrayerCalculator.current(at: date, location: location, settings: settings),
            records: progress.records, quranToday: progress.quranToday,
            quranGoal: progress.quranGoal, quranStreak: progress.quranStreak
        )
    }

    /// Makkah times and sample progress, for the widget gallery: quick to
    /// draw, and never empty.
    static var preview: PrayerEntry {
        let date = Date()
        let location = SavedLocation.makkah
        let settings = PrayerSettings()
        var today = QuranDay(goal: 10)
        today.verses = Set((1...7).map { "2:\($0)" })
        return PrayerEntry(
            date: date,
            locationName: location.name,
            schedule: PrayerCalculator.schedule(for: date, location: location, settings: settings),
            next: PrayerCalculator.next(after: date, location: location, settings: settings),
            current: PrayerCalculator.current(at: date, location: location, settings: settings),
            quranToday: today, quranGoal: 10, quranStreak: 12
        )
    }
}

/// Produces one entry per prayer time, so the widget flips to the next prayer
/// exactly when the adhan time arrives, even with the app closed.
struct PrayerProvider: TimelineProvider {
    func placeholder(in context: Context) -> PrayerEntry { .preview }

    func getSnapshot(in context: Context, completion: @escaping (PrayerEntry) -> Void) {
        ThemeManager.shared.reload()
        // The gallery ("Add widget", Lock Screen editing) gets the sample at once.
        completion(context.isPreview ? .preview : .make(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PrayerEntry>) -> Void) {
        ThemeManager.shared.reload()
        let now = Date()
        guard let location = SettingsStore.location else {
            completion(Timeline(entries: [.make(at: now)], policy: .after(now.addingTimeInterval(3600))))
            return
        }
        let calendar = PrayerCalculator.calendar(for: location)
        let upcoming = PrayerCalculator.upcoming(after: now, count: 12, includeSunrise: true,
                                                 location: location, settings: SettingsStore.prayerSettings)
        var dates = [now] + upcoming.map(\.date)
        // Also refresh at midnight so the date and day's times roll over.
        if let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) {
            dates.append(midnight)
        }
        let progress = PrayerEntry.Progress.load()
        let entries = dates.sorted().map { PrayerEntry.make(at: $0, progress: progress) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct NoLocationView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "location.slash")
            Text("Open Niyat to set your location")
                .font(.caption)
                .multilineTextAlignment(.center)
        }
    }
}
