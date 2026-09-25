import SwiftUI
import WidgetKit

struct PrayerEntry: TimelineEntry {
    let date: Date
    let locationName: String?
    let schedule: DaySchedule?
    let next: PrayerTime?
    let current: PrayerTime?

    var hasLocation: Bool { locationName != nil }

    static func make(at date: Date) -> PrayerEntry {
        guard let location = SettingsStore.location else {
            return PrayerEntry(date: date, locationName: nil, schedule: nil, next: nil, current: nil)
        }
        let settings = SettingsStore.prayerSettings
        return PrayerEntry(
            date: date,
            locationName: location.name,
            schedule: PrayerCalculator.schedule(for: date, location: location, settings: settings),
            next: PrayerCalculator.next(after: date, location: location, settings: settings),
            current: PrayerCalculator.current(at: date, location: location, settings: settings)
        )
    }

    /// Makkah times, for the widget gallery.
    static var preview: PrayerEntry {
        let date = Date()
        let location = SavedLocation.makkah
        let settings = PrayerSettings()
        return PrayerEntry(
            date: date,
            locationName: location.name,
            schedule: PrayerCalculator.schedule(for: date, location: location, settings: settings),
            next: PrayerCalculator.next(after: date, location: location, settings: settings),
            current: PrayerCalculator.current(at: date, location: location, settings: settings)
        )
    }
}

/// Produces one entry per prayer time, so the widget flips to the next prayer
/// exactly when the adhan time arrives, even with the app closed.
struct PrayerProvider: TimelineProvider {
    func placeholder(in context: Context) -> PrayerEntry { .preview }

    func getSnapshot(in context: Context, completion: @escaping (PrayerEntry) -> Void) {
        completion(context.isPreview && SettingsStore.location == nil ? .preview : .make(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PrayerEntry>) -> Void) {
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
        let entries = dates.sorted().map { PrayerEntry.make(at: $0) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct NoLocationView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "location.slash")
            Text("Open Salah to set your location")
                .font(.caption)
                .multilineTextAlignment(.center)
        }
    }
}
