import SwiftUI
import WidgetKit

/// Medium/large Home Screen widget with the whole day's times.
struct PrayerTimesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PrayerTimesWidget", provider: PrayerProvider()) { entry in
            PrayerTimesView(entry: entry)
        }
        .configurationDisplayName("Prayer Times")
        .description("All of today's prayer times.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct PrayerTimesView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PrayerEntry

    var body: some View {
        Group {
            if let schedule = entry.schedule {
                if family == .systemLarge {
                    large(schedule)
                } else {
                    medium(schedule)
                }
            } else {
                NoLocationView().foregroundStyle(.white)
            }
        }
        .containerBackground(for: .widget) {
            WidgetBackground()
        }
    }

    private func medium(_ schedule: DaySchedule) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                if let next = entry.next {
                    Text("Next")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                    Text(next.name.displayName(on: next.date))
                        .font(.title3.bold())
                        .foregroundStyle(Palette.gold)
                    Text(next.date, style: .relative)
                        .font(.caption)
                }
                Spacer(minLength: 0)
                Text(HijriDate.string(for: entry.date))
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 3) {
                ForEach(schedule.times.filter { $0.name.isObligatory }) { time in
                    row(time)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(.white)
    }

    private func large(_ schedule: DaySchedule) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading) {
                    Text(entry.locationName ?? "")
                        .font(.headline)
                    Text(HijriDate.string(for: entry.date))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                if let next = entry.next {
                    VStack(alignment: .trailing) {
                        Text(next.name.displayName(on: next.date))
                            .font(.headline)
                            .foregroundStyle(Palette.gold)
                        Text(next.date, style: .relative).font(.caption)
                    }
                }
            }
            Divider().overlay(.white.opacity(0.3))
            ForEach(schedule.times) { time in
                row(time, showIcon: true)
                    .font(.body)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
    }

    private func row(_ time: PrayerTime, showIcon: Bool = false) -> some View {
        let isNext = time.id == entry.next?.id
        return HStack {
            if showIcon {
                Image(systemName: time.name.symbolName)
                    .frame(width: 24)
                    .foregroundStyle(Palette.gold)
            }
            Text(time.name.displayName(on: time.date))
            Spacer()
            Text(time.date.shortTime).monospacedDigit()
        }
        .font(.caption.weight(isNext ? .bold : .regular))
        .padding(.horizontal, 8)
        .padding(.vertical, showIcon ? 6 : 2)
        .background(isNext ? Palette.emerald.opacity(0.25) : .clear, in: .rect(cornerRadius: 6))
    }
}

#Preview(as: .systemMedium) {
    PrayerTimesWidget()
} timeline: {
    PrayerEntry.preview
}
