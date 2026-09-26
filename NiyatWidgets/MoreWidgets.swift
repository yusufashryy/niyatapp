import AppIntents
import SwiftUI
import UserNotifications
import WidgetKit

// MARK: - Log a prayer from the widget

/// Marks a prayer as prayed on time, right from the Home Screen. Never logs twice.
struct LogPrayerIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Prayer"
    static var description = IntentDescription("Marks a prayer as prayed on time.")

    @Parameter(title: "Prayer") var prayer: String
    @Parameter(title: "Day") var dayKey: String

    init() {}

    init(prayer: PrayerName, dayKey: String) {
        self.prayer = prayer.rawValue
        self.dayKey = dayKey
    }

    func perform() async throws -> some IntentResult {
        if let name = PrayerName(rawValue: prayer), PrayerLog.logIfNeeded(name, dayKey: dayKey) {
            // The "have you prayed?" follow-up is no longer needed.
            UNUserNotificationCenter.current().removePendingNotificationRequests(
                withIdentifiers: ["prayer.\(dayKey).\(prayer).after30"])
        }
        return .result()
    }
}

// MARK: - Prayer Dial

struct PrayerDialWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PrayerDialWidget", provider: PrayerProvider()) { entry in
            PrayerDialWidgetView(entry: entry)
        }
        .configurationDisplayName("Prayer Dial")
        .description("Today's prayers around a 24-hour dial, with the next one in the middle.")
        .supportedFamilies([.systemSmall, .systemLarge])
    }
}

struct PrayerDialWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PrayerEntry

    var body: some View {
        Group {
            if let schedule = entry.schedule {
                GeometryReader { geo in
                    let side = min(geo.size.width, geo.size.height)
                    let radius = side / 2 - (family == .systemLarge ? 22 : 12)
                    let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                    ZStack {
                        Circle().stroke(.white.opacity(0.1), lineWidth: family == .systemLarge ? 12 : 7)
                            .frame(width: radius * 2, height: radius * 2)
                        if let sunrise = schedule.time(for: .sunrise), let maghrib = schedule.time(for: .maghrib) {
                            Circle()
                                .trim(from: fraction(sunrise.date, schedule), to: fraction(maghrib.date, schedule))
                                .rotation(.degrees(90))
                                .stroke(Palette.highlight.opacity(0.45),
                                        style: StrokeStyle(lineWidth: family == .systemLarge ? 12 : 7, lineCap: .round))
                                .frame(width: radius * 2, height: radius * 2)
                        }
                        ForEach(schedule.times) { time in
                            let record = entry.record(for: time.name)
                            Circle()
                                .fill(record?.status.color ?? (time.id == entry.next?.id ? Palette.highlight : Palette.base))
                                .overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 1))
                                .frame(width: dotSize(time), height: dotSize(time))
                                .position(point(fraction(time.date, schedule), radius: radius, center: center))
                        }
                        Image(systemName: "sun.max.fill")
                            .font(.system(size: family == .systemLarge ? 16 : 10, weight: .bold))
                            .foregroundStyle(.white)
                            .position(point(fraction(entry.date, schedule), radius: radius, center: center))
                            .opacity(0.9)
                        if let next = entry.next {
                            VStack(spacing: 0) {
                                Text(next.name.arabicName)
                                    .font(.calligraphy(size: family == .systemLarge ? 34 : 18))
                                    .foregroundStyle(Palette.highlight)
                                Text(next.date.shortTime)
                                    .font(.system(size: family == .systemLarge ? 34 : 17, weight: .heavy, design: .rounded))
                                    .minimumScaleFactor(0.6)
                                    .lineLimit(1)
                                Text(next.date, style: .relative)
                                    .font(.system(size: family == .systemLarge ? 14 : 9, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.7))
                                    .multilineTextAlignment(.center)
                            }
                            .frame(width: radius * 1.4)
                            .position(center)
                        }
                    }
                }
                .foregroundStyle(.white)
            } else {
                NoLocationView().foregroundStyle(.white)
            }
        }
        .containerBackground(for: .widget) { WidgetBackground() }
    }

    private func dotSize(_ time: PrayerTime) -> CGFloat {
        let base: CGFloat = family == .systemLarge ? 18 : 9
        return time.name.isObligatory ? base : base * 0.6
    }

    private func fraction(_ date: Date, _ schedule: DaySchedule) -> CGFloat {
        CGFloat(min(max(date.timeIntervalSince(schedule.day) / 86_400, 0), 1))
    }

    private func point(_ fraction: CGFloat, radius: CGFloat, center: CGPoint) -> CGPoint {
        let angle = Double(fraction) * 2 * .pi + .pi / 2
        return CGPoint(x: center.x + radius * CGFloat(cos(angle)), y: center.y + radius * CGFloat(sin(angle)))
    }
}

// MARK: - Countdown ring (Lock Screen)

struct CountdownRingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CountdownRingWidget", provider: PrayerProvider()) { entry in
            CountdownRingView(entry: entry)
        }
        .configurationDisplayName("Prayer Countdown")
        .description("A ring that fills up until the next prayer.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct CountdownRingView: View {
    let entry: PrayerEntry

    var body: some View {
        Group {
            if let next = entry.next {
                let start = entry.current?.date ?? entry.date.addingTimeInterval(-3600)
                ProgressView(timerInterval: min(start, next.date)...next.date, countsDown: false) {
                    Text(next.name.englishName)
                } currentValueLabel: {
                    VStack(spacing: 0) {
                        Image(systemName: next.name.symbolName).font(.caption2)
                        Text(next.date, format: .dateTime.hour().minute())
                            .font(.system(size: 10, weight: .semibold))
                            .minimumScaleFactor(0.6)
                    }
                }
                .progressViewStyle(.circular)
                .widgetAccentable()
            } else {
                Image(systemName: "location.slash")
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }
}

// MARK: - Prayer Log (interactive)

struct PrayerLogWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PrayerLogWidget", provider: PrayerProvider()) { entry in
            PrayerLogWidgetView(entry: entry)
        }
        .configurationDisplayName("Prayer Log")
        .description("Tap a prayer to log it, right from your Home Screen.")
        .supportedFamilies([.systemMedium])
    }
}

struct PrayerLogWidgetView: View {
    let entry: PrayerEntry

    var body: some View {
        Group {
            if let schedule = entry.schedule {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Today's prayers").font(.caption.weight(.bold)).textCase(.uppercase).foregroundStyle(.secondary)
                        Spacer()
                        let count = PrayerName.obligatory.filter { entry.record(for: $0)?.status.countsAsPrayed ?? false }.count
                        Text("\(count)/5").font(.caption.weight(.heavy)).foregroundStyle(Palette.highlight)
                    }
                    HStack(spacing: 6) {
                        ForEach(PrayerName.obligatory) { prayer in
                            if let time = schedule.time(for: prayer) {
                                cell(time: time, day: schedule.day)
                            }
                        }
                    }
                }
                .foregroundStyle(.white)
            } else {
                NoLocationView().foregroundStyle(.white)
            }
        }
        .containerBackground(for: .widget) { WidgetBackground() }
    }

    @ViewBuilder
    private func cell(time: PrayerTime, day: Date) -> some View {
        let record = entry.record(for: time.name)
        let started = time.date <= entry.date
        let content = VStack(spacing: 4) {
            Image(systemName: record?.status.symbolName ?? (started ? "circle" : time.name.symbolName))
                .font(.title3)
                .foregroundStyle(record?.status.color ?? (started ? .white : .white.opacity(0.4)))
            Text(time.name.displayName(on: time.date))
                .font(.caption2.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(time.date.shortTime)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(.white.opacity(started && record == nil ? 0.12 : 0.05), in: .rect(cornerRadius: 12))

        if started, record == nil {
            Button(intent: LogPrayerIntent(prayer: time.name, dayKey: PrayerLog.dayKey(for: day))) { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }
}

// MARK: - Streaks

struct StreakWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "StreakWidget", provider: PrayerProvider()) { entry in
            StreakWidgetView(entry: entry)
        }
        .configurationDisplayName("Streaks")
        .description("Your prayer and Qur'an streaks.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct StreakWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PrayerEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Label("\(entry.prayerStreak)-day prayer streak", systemImage: "flame.fill")
                        .widgetAccentable()
                    Label("\(entry.quranStreak)-day Qur'an streak", systemImage: "book.fill")
                }
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
            case .systemMedium:
                HStack(spacing: 16) {
                    streaks
                    week
                }
            default:
                streaks
            }
        }
        .foregroundStyle(.white)
        .containerBackground(for: .widget) {
            if family == .accessoryRectangular { Color.clear } else { WidgetBackground() }
        }
    }

    private var streaks: some View {
        VStack(alignment: .leading, spacing: 10) {
            streakRow(value: entry.prayerStreak, label: "Prayer", symbol: "sun.horizon.fill")
            streakRow(value: entry.quranStreak, label: "Qur'an", symbol: "book.fill")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func streakRow(value: Int, label: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: "flame.fill").foregroundStyle(Palette.highlight).font(.caption)
                Text("\(value)").font(.system(size: 30, weight: .heavy, design: .rounded))
                Text(value == 1 ? "day" : "days").font(.caption).foregroundStyle(.secondary)
            }
            Label(label, systemImage: symbol).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
        }
    }

    private var week: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: entry.date)
        let days = (0..<7).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
        return HStack(spacing: 4) {
            ForEach(days, id: \.self) { day in
                let count = PrayerName.obligatory.filter { entry.records[PrayerLog.key($0, on: day)]?.status.countsAsPrayed ?? false }.count
                VStack(spacing: 4) {
                    ZStack {
                        EightPointStar().fill(count == 5 ? Palette.highlight : Color.white.opacity(0.08))
                        EightPointStar().trim(from: 0, to: CGFloat(count) / 5)
                            .stroke(Palette.accent, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    }
                    .frame(width: 18, height: 18)
                    Text(day.formatted(.dateTime.weekday(.narrow))).font(.system(size: 9)).foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Qur'an goal

struct QuranGoalWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "QuranGoalWidget", provider: PrayerProvider()) { entry in
            QuranGoalWidgetView(entry: entry)
        }
        .configurationDisplayName("Qur'an Goal")
        .description("Today's ayat towards your daily Qur'an goal. Tap to keep reading.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

struct QuranGoalWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PrayerEntry

    private var progress: Double {
        guard let goal = entry.quranGoal, goal > 0 else { return 0 }
        return min(Double(entry.quranToday.count) / Double(goal), 1)
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                Gauge(value: progress) {
                    Image(systemName: "book.fill")
                } currentValueLabel: {
                    Text("\(entry.quranToday.count)")
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .widgetAccentable()
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Label("Qur'an today", systemImage: "book.fill").font(.caption.weight(.bold)).widgetAccentable()
                    Text(entry.quranGoal.map { "\(entry.quranToday.count) / \($0) ayat" } ?? "\(entry.quranToday.count) ayat")
                        .font(.body.weight(.semibold))
                    Text("\(entry.quranStreak)-day streak").font(.caption2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            default:
                VStack(spacing: 8) {
                    ZStack {
                        Circle().stroke(.white.opacity(0.1), lineWidth: 8)
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(entry.quranToday.isComplete ? Palette.highlight : Palette.accent,
                                    style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 0) {
                            Text("\(entry.quranToday.count)").font(.system(size: 26, weight: .heavy, design: .rounded))
                            Text(entry.quranGoal.map { "of \($0)" } ?? "ayat").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 86, height: 86)
                    Text(entry.quranToday.isComplete ? "Goal complete ✓" : "Qur'an today")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(entry.quranToday.isComplete ? Palette.highlight : .white)
                }
                .foregroundStyle(.white)
            }
        }
        .widgetURL(URL(string: "niyat://quran"))
        .containerBackground(for: .widget) {
            if family == .systemSmall { WidgetBackground() } else { Color.clear }
        }
    }
}

// MARK: - Hijri date

struct HijriDateWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HijriDateWidget", provider: VerseProvider()) { entry in
            HijriDateWidgetView(date: entry.date)
        }
        .configurationDisplayName("Hijri Date")
        .description("Today's Islamic date.")
        .supportedFamilies([.systemSmall, .accessoryInline, .accessoryRectangular])
    }
}

struct HijriDateWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let date: Date

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                Text(HijriDate.string(for: date))
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Text(HijriDate.string(for: date, locale: Locale(identifier: "ar")))
                        .font(.headline)
                        .widgetAccentable()
                    Text(HijriDate.string(for: date)).font(.caption)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            default:
                VStack(spacing: 6) {
                    EightPointStar().fill(Palette.highlight).frame(width: 18, height: 18)
                    Text(HijriDate.string(for: date, locale: Locale(identifier: "ar")))
                        .font(.calligraphy(size: 22))
                        .foregroundStyle(Palette.highlight)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.6)
                    Text(HijriDate.string(for: date))
                        .font(.caption.weight(.semibold))
                        .multilineTextAlignment(.center)
                    Text(date.formatted(.dateTime.weekday(.wide).day().month()))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.white)
            }
        }
        .containerBackground(for: .widget) {
            if family == .systemSmall { WidgetBackground() } else { Color.clear }
        }
    }
}
