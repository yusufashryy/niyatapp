import AppIntents
import SwiftUI
import WidgetKit

/// Tapping the widget's button counts without opening the app (iOS 17 interactive widgets).
struct IncrementTasbihIntent: AppIntent {
    static var title: LocalizedStringResource = "Count Tasbih"
    static var description = IntentDescription("Adds one to your tasbih count.")

    func perform() async throws -> some IntentResult {
        TasbihCounter.increment()
        return .result()
    }
}

struct ResetTasbihIntent: AppIntent {
    static var title: LocalizedStringResource = "Reset Tasbih"

    func perform() async throws -> some IntentResult {
        TasbihCounter.reset()
        return .result()
    }
}

struct TasbihEntry: TimelineEntry {
    let date: Date
    let count: Int
    let target: Int
    let dhikr: Dhikr

    static var current: TasbihEntry {
        TasbihEntry(date: .now, count: TasbihCounter.count, target: TasbihCounter.target, dhikr: TasbihCounter.dhikr)
    }
}

struct TasbihProvider: TimelineProvider {
    func placeholder(in context: Context) -> TasbihEntry {
        TasbihEntry(date: .now, count: 12, target: 33, dhikr: .subhanAllah)
    }

    func getSnapshot(in context: Context, completion: @escaping (TasbihEntry) -> Void) {
        completion(.current)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TasbihEntry>) -> Void) {
        completion(Timeline(entries: [.current], policy: .never))
    }
}

struct TasbihWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TasbihWidget", provider: TasbihProvider()) { entry in
            TasbihWidgetView(entry: entry)
        }
        .configurationDisplayName("Tasbih")
        .description("Count your dhikr right from the Home Screen.")
        .supportedFamilies([.systemSmall])
    }
}

struct TasbihWidgetView: View {
    let entry: TasbihEntry

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(entry.dhikr.transliteration)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer()
                Button(intent: ResetTasbihIntent()) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(.white.opacity(0.85))

            Button(intent: IncrementTasbihIntent()) {
                ZStack {
                    Circle().fill(Color.white.opacity(0.12))
                    VStack(spacing: 0) {
                        Text("\(entry.count)")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .contentTransition(.numericText())
                            .minimumScaleFactor(0.5)
                        if entry.target > 0 {
                            Text("of \(entry.target)")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
        }
        .containerBackground(for: .widget) {
            LinearGradient(colors: [.niyatiGreen, .niyatiDeepGreen], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}
