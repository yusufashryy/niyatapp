import SwiftUI
import WidgetKit

/// Small Home Screen widget + all three Lock Screen styles.
struct NextPrayerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextPrayerWidget", provider: PrayerProvider()) { entry in
            NextPrayerView(entry: entry)
        }
        .configurationDisplayName("Next Prayer")
        .description("The next prayer and a countdown to it.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct NextPrayerView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PrayerEntry

    var body: some View {
        Group {
            if let next = entry.next {
                switch family {
                case .accessoryCircular: circular(next)
                case .accessoryRectangular: rectangular(next)
                case .accessoryInline: inline(next)
                default: small(next)
                }
            } else {
                NoLocationView()
            }
        }
        .fontDesign(.rounded)
        .containerBackground(for: .widget) {
            if family == .systemSmall {
                if let next = entry.next {
                    PrayerSky(prayer: next.name)
                } else {
                    WidgetBackground()
                }
            } else {
                Color.clear
            }
        }
    }

    private func small(_ next: PrayerTime) -> some View {
        VStack(spacing: 2) {
            Image(systemName: next.name.symbolName)
                .font(.system(size: 15, weight: .semibold))
            Text(next.name.arabicName)
                .font(.calligraphy(size: 22))
                .lineLimit(1)
            Text(next.date.shortTime)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(next.date, style: .relative)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
            if let name = entry.locationName {
                Text(name)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .lineLimit(1)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func circular(_ next: PrayerTime) -> some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 1) {
                Image(systemName: next.name.symbolName).font(.caption)
                Text(next.date, format: .dateTime.hour().minute())
                    .font(.system(size: 11, weight: .semibold))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            .padding(2)
        }
        .widgetAccentable()
    }

    private func rectangular(_ next: PrayerTime) -> some View {
        VStack(alignment: .center, spacing: 1) {
            Label(next.name.displayName(on: next.date), systemImage: next.name.symbolName)
                .font(.headline)
                .widgetAccentable()
            Text(next.date.shortTime)
                .font(.body.weight(.semibold))
            Text(next.date, style: .relative)
                .font(.caption)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private func inline(_ next: PrayerTime) -> some View {
        Label("\(next.name.displayName(on: next.date)) \(next.date.shortTime)", systemImage: next.name.symbolName)
    }
}

#Preview(as: .systemSmall) {
    NextPrayerWidget()
} timeline: {
    PrayerEntry.preview
}
