import SwiftUI
import WidgetKit

struct VerseEntry: TimelineEntry {
    let date: Date
    let verse: DailyVerse
}

struct VerseProvider: TimelineProvider {
    func placeholder(in context: Context) -> VerseEntry {
        VerseEntry(date: .now, verse: DailyVerse.all[0])
    }

    func getSnapshot(in context: Context, completion: @escaping (VerseEntry) -> Void) {
        completion(VerseEntry(date: .now, verse: .forDay(.now)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<VerseEntry>) -> Void) {
        let now = Date()
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(86_400)
        let entries = [
            VerseEntry(date: now, verse: .forDay(now)),
            VerseEntry(date: tomorrow, verse: .forDay(tomorrow)),
        ]
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct DailyVerseWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DailyVerseWidget", provider: VerseProvider()) { entry in
            DailyVerseView(entry: entry)
        }
        .configurationDisplayName("Verse of the Day")
        .description("A new verse from the Quran every day.")
        .supportedFamilies([.systemMedium, .systemLarge, .accessoryRectangular])
    }
}

struct DailyVerseView: View {
    @Environment(\.widgetFamily) private var family
    let entry: VerseEntry

    var body: some View {
        Group {
            if family == .accessoryRectangular {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.verse.english)
                        .font(.caption)
                        .lineLimit(3)
                    Text(entry.verse.reference)
                        .font(.caption2)
                        .widgetAccentable()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(entry.verse.arabic)
                        .font(.quran(size: family == .systemLarge ? 26 : 19))
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .minimumScaleFactor(0.5)
                        .lineLimit(family == .systemLarge ? 6 : 2)
                    Text(entry.verse.english)
                        .font(family == .systemLarge ? .body : .caption)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                    Text(entry.verse.reference)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.niyatiGold)
                }
                .foregroundStyle(.white)
            }
        }
        .containerBackground(for: .widget) {
            if family == .accessoryRectangular {
                Color.clear
            } else {
                LinearGradient(colors: [.niyatiGreen, .niyatiDeepGreen], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
    }
}

#Preview(as: .systemMedium) {
    DailyVerseWidget()
} timeline: {
    VerseEntry(date: .now, verse: DailyVerse.all[0])
}
