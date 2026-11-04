import SwiftUI
import WidgetKit

// Watch face complications. Times are worked out on the watch from the
// location and settings the iPhone sent (see WatchSync).

struct WatchPrayerEntry: TimelineEntry {
    let date: Date
    let schedule: DaySchedule?
    let next: PrayerTime?
    let previous: Date?
    /// Raised in the Smart Stack shortly before a prayer.
    var relevance: TimelineEntryRelevance?

    static func make(at date: Date) -> WatchPrayerEntry {
        guard let location = SettingsStore.location else {
            return WatchPrayerEntry(date: date, schedule: nil, next: nil, previous: nil)
        }
        let settings = SettingsStore.prayerSettings
        return WatchPrayerEntry(
            date: date,
            schedule: PrayerCalculator.schedule(for: date, location: location, settings: settings),
            next: PrayerCalculator.next(after: date, location: location, settings: settings),
            previous: PrayerCalculator.current(at: date, location: location, settings: settings)?.date
        )
    }

    /// Makkah, for the watch face gallery.
    static var preview: WatchPrayerEntry {
        let date = Date()
        let location = SavedLocation.makkah
        let settings = PrayerSettings()
        return WatchPrayerEntry(
            date: date,
            schedule: PrayerCalculator.schedule(for: date, location: location, settings: settings),
            next: PrayerCalculator.next(after: date, location: location, settings: settings),
            previous: PrayerCalculator.current(at: date, location: location, settings: settings)?.date
        )
    }
}

/// One entry per prayer time, so the complication flips exactly at the adhan.
struct WatchPrayerProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchPrayerEntry { .preview }

    func getSnapshot(in context: Context, completion: @escaping (WatchPrayerEntry) -> Void) {
        completion(context.isPreview ? .preview : .make(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchPrayerEntry>) -> Void) {
        let now = Date()
        guard let location = SettingsStore.location else {
            completion(Timeline(entries: [.make(at: now)], policy: .after(now.addingTimeInterval(3600))))
            return
        }
        let upcoming = PrayerCalculator.upcoming(after: now, count: 12, includeSunrise: true,
                                                 location: location, settings: SettingsStore.prayerSettings)
        // An entry at each prayer, so the complication flips at the adhan, and one
        // 20 minutes before, when the Smart Stack moves Niyat to the top.
        let lead: TimeInterval = 20 * 60
        var entries = [WatchPrayerEntry.make(at: now)]
        for time in upcoming {
            if time.name.isObligatory, time.date.addingTimeInterval(-lead) > now {
                var soon = WatchPrayerEntry.make(at: time.date.addingTimeInterval(-lead))
                soon.relevance = TimelineEntryRelevance(score: 1, duration: lead + 10 * 60)
                entries.append(soon)
            }
            var at = WatchPrayerEntry.make(at: time.date)
            at.relevance = TimelineEntryRelevance(score: 0.1)
            entries.append(at)
        }
        completion(Timeline(entries: entries.sorted { $0.date < $1.date }, policy: .atEnd))
    }
}

@main
struct NiyatWatchWidgets: WidgetBundle {
    var body: some Widget {
        WatchNextPrayerWidget()
        WatchPrayerTimesWidget()
        WatchHijriDateWidget()
        WatchQuranGoalWidget()
    }
}

// MARK: - Next prayer

struct WatchNextPrayerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchNextPrayer", provider: WatchPrayerProvider()) { entry in
            WatchNextPrayerView(entry: entry)
        }
        .configurationDisplayName("Next Prayer")
        .description("The next prayer and the time until it.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

struct WatchNextPrayerView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WatchPrayerEntry

    var body: some View {
        Group {
            if let next = entry.next {
                switch family {
                case .accessoryCircular: circular(next)
                case .accessoryInline:
                    Label("\(next.name.displayName(on: next.date)) \(next.date.shortTime)", systemImage: next.name.symbolName)
                case .accessoryCorner:
                    Image(systemName: next.name.symbolName)
                        .font(.title3)
                        .widgetLabel { Text("\(next.name.displayName(on: next.date)) \(next.date.shortTime)") }
                default: rectangular(next)
                }
            } else {
                Image(systemName: "location.slash")
            }
        }
        .fontDesign(.rounded)
        .containerBackground(for: .widget) { Color.clear }
    }

    /// A ring that fills up until the next prayer, with its time inside.
    private func circular(_ next: PrayerTime) -> some View {
        let start = min(entry.previous ?? entry.date.addingTimeInterval(-3600), next.date)
        return ProgressView(timerInterval: start...next.date, countsDown: false) {
            Text(next.name.englishName)
        } currentValueLabel: {
            VStack(spacing: 0) {
                Image(systemName: next.name.symbolName).font(.system(size: 10))
                Text(next.date, format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
                    .font(.system(size: 12, weight: .semibold))
                    .minimumScaleFactor(0.6)
            }
        }
        .progressViewStyle(.circular)
        .widgetAccentable()
    }

    private func rectangular(_ next: PrayerTime) -> some View {
        VStack(spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: next.name.symbolName)
                Text(next.name.displayName(on: next.date))
                Text(next.name.arabicName)
            }
            .font(.headline)
            .widgetAccentable()
            Text(next.date.shortTime)
                .font(.system(size: 20, weight: .bold))
            Text(next.date, style: .relative)
                .font(.caption)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - All of today's times

struct WatchPrayerTimesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchPrayerTimes", provider: WatchPrayerProvider()) { entry in
            WatchPrayerTimesView(entry: entry)
        }
        .configurationDisplayName("Prayer Times")
        .description("All six of today's times.")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct WatchPrayerTimesView: View {
    let entry: WatchPrayerEntry

    var body: some View {
        Group {
            if let times = entry.schedule?.times {
                HStack(alignment: .top, spacing: 8) {
                    column(Array(times.prefix(3)))
                    column(Array(times.dropFirst(3).prefix(3)))
                }
                .frame(maxWidth: .infinity)
            } else {
                Image(systemName: "location.slash")
            }
        }
        .fontDesign(.rounded)
        .containerBackground(for: .widget) { Color.clear }
    }

    private func column(_ times: [PrayerTime]) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            ForEach(times) { time in
                let isNext = time.id == entry.next?.id
                HStack(spacing: 3) {
                    Text(time.date, format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
                        .monospacedDigit()
                    Text(time.name.arabicName).lineLimit(1).minimumScaleFactor(0.7)
                    Image(systemName: isNext ? "circle.fill" : "circle").font(.system(size: 5, weight: .bold))
                }
                .font(.system(size: 12, weight: isNext ? .bold : .medium))
                .widgetAccentable(isNext)
            }
        }
    }
}

// MARK: - Hijri date

struct WatchDayEntry: TimelineEntry {
    let date: Date
    let quranDay: QuranDay
    let quranGoal: Int?
}

/// One entry now and one at each midnight for two days, re-reading the
/// Qur'an goal the iPhone last sent.
struct WatchDayProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchDayEntry {
        WatchDayEntry(date: .now, quranDay: QuranDay(verses: ["1:1", "1:2", "1:3", "1:4"], goal: 10), quranGoal: 10)
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchDayEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchDayEntry>) -> Void) {
        let calendar = Calendar.current
        let midnights = (1...2).compactMap { calendar.date(byAdding: .day, value: $0, to: calendar.startOfDay(for: .now)) }
        completion(Timeline(entries: [entry(at: .now)] + midnights.map(entry(at:)), policy: .atEnd))
    }

    private func entry(at date: Date) -> WatchDayEntry {
        WatchDayEntry(date: date, quranDay: QuranProgress.day(date), quranGoal: QuranProgress.dailyGoal)
    }
}

struct WatchHijriDateWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchHijriDate", provider: WatchDayProvider()) { entry in
            WatchHijriDateView(date: entry.date)
        }
        .configurationDisplayName("Hijri Date")
        .description("Today's date in the Islamic calendar.")
        .supportedFamilies([.accessoryInline, .accessoryRectangular, .accessoryCircular])
    }
}

struct WatchHijriDateView: View {
    @Environment(\.widgetFamily) private var family
    let date: Date

    var body: some View {
        let hijri = HijriDate.string(for: date)
        Group {
            switch family {
            case .accessoryInline:
                Text(hijri)
            case .accessoryCircular:
                let day = HijriDate.day(for: date)
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 0) {
                        EightPointStar().frame(width: 10, height: 10).widgetAccentable()
                        Text("\(day)").font(.system(size: 20, weight: .bold, design: .rounded))
                    }
                }
            default:
                VStack(alignment: .leading, spacing: 1) {
                    Text("Hijri").font(.caption2.weight(.semibold)).widgetAccentable()
                    Text(hijri).font(.headline).minimumScaleFactor(0.7).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }
}

// MARK: - Qur'an goal

struct WatchQuranGoalWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchQuranGoal", provider: WatchDayProvider()) { entry in
            WatchQuranGoalView(entry: entry)
        }
        .configurationDisplayName("Qur'an Goal")
        .description("Today's ayat towards your daily goal.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline])
    }
}

struct WatchQuranGoalView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WatchDayEntry

    var body: some View {
        let goal = max(entry.quranGoal ?? 0, 1)
        let count = entry.quranDay.count
        Group {
            switch family {
            case .accessoryInline:
                Text(entry.quranGoal == nil ? "Qur'an goal" : "Qur'an \(count)/\(goal)")
            case .accessoryCorner:
                Image(systemName: "book.closed.fill")
                    .font(.title3)
                    .widgetAccentable()
                    .widgetLabel {
                        Gauge(value: Double(min(count, goal)), in: 0...Double(goal)) { Text("Qur'an") }
                    }
            default:
                Gauge(value: Double(min(count, goal)), in: 0...Double(goal)) {
                    Image(systemName: "book.closed.fill")
                } currentValueLabel: {
                    Text("\(count)").font(.system(size: 14, weight: .bold, design: .rounded))
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .widgetAccentable()
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }
}
