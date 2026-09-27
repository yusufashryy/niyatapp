import SwiftUI

/// Niyat on Apple Watch: the next prayer at a glance, today's times, and a tap
/// to log a prayer. Times are worked out on the watch from the location and
/// settings the iPhone sends (see WatchSync).
@main
struct NiyatWatchApp: App {
    init() {
        WatchSync.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView()
        }
    }
}

/// Watch-side state: re-read when the iPhone sends new data.
@MainActor
@Observable
final class WatchStore {
    private(set) var location = SettingsStore.location
    private(set) var settings = SettingsStore.prayerSettings
    private(set) var records = PrayerLog.load()

    init() {
        NotificationCenter.default.addObserver(forName: WatchSync.changed, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
    }

    func reload() {
        location = SettingsStore.location
        settings = SettingsStore.prayerSettings
        records = PrayerLog.load()
    }

    func schedule(at date: Date) -> DaySchedule? {
        guard let location else { return nil }
        return PrayerCalculator.schedule(for: date, location: location, settings: settings)
    }

    func next(after date: Date) -> PrayerTime? {
        guard let location else { return nil }
        return PrayerCalculator.next(after: date, location: location, settings: settings)
    }

    func record(_ prayer: PrayerName, on day: Date) -> PrayerRecord? {
        records[PrayerLog.key(prayer, on: day)]
    }

    func log(_ prayer: PrayerName, on day: Date) {
        WatchSync.shared.log(prayer, dayKey: PrayerLog.dayKey(for: day))
        reload()
    }
}

struct WatchRootView: View {
    @State private var store = WatchStore()

    var body: some View {
        // Redraws every minute so the countdown and "next prayer" stay current.
        TimelineView(.everyMinute) { context in
            if store.location != nil, let next = store.next(after: context.date) {
                TabView {
                    WatchNextPrayerPage(next: next, locationName: store.location?.name ?? "")
                    if let schedule = store.schedule(at: context.date) {
                        WatchTodayPage(schedule: schedule, now: context.date, store: store)
                    }
                }
                .tabViewStyle(.verticalPage)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "iphone")
                        .font(.title2)
                    Text("Open Niyat on your iPhone to set your location.")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
        }
    }
}

/// The next prayer, big and centred, over its sky.
struct WatchNextPrayerPage: View {
    let next: PrayerTime
    let locationName: String

    var body: some View {
        VStack(spacing: 2) {
            Text(next.name.arabicName)
                .font(.calligraphy(size: 30))
                .lineLimit(1)
            Text(next.name.displayName(on: next.date))
                .font(.system(.headline, design: .rounded))
            Text(next.date.shortTime)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(next.date, style: .relative)
                .font(.system(.footnote, design: .rounded).weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
            Text(locationName)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .tabView) { PrayerSky(prayer: next.name) }
    }
}

/// Today's times; tap a prayer whose time has come to log it.
struct WatchTodayPage: View {
    let schedule: DaySchedule
    let now: Date
    let store: WatchStore

    var body: some View {
        List {
            ForEach(schedule.times) { time in
                row(time)
            }
        }
        .navigationTitle("Today")
    }

    @ViewBuilder
    private func row(_ time: PrayerTime) -> some View {
        let record = store.record(time.name, on: schedule.day)
        let canLog = time.name.isObligatory && time.date <= now && record == nil
        Button {
            if canLog { store.log(time.name, on: schedule.day) }
        } label: {
            HStack {
                Image(systemName: record?.status.symbolName ?? time.name.symbolName)
                    .foregroundStyle(record?.status.color ?? Palette.highlight)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 0) {
                    Text(time.name.displayName(on: time.date))
                        .font(.system(.body, design: .rounded).weight(.semibold))
                    if canLog {
                        Text("Tap to log").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(time.date.shortTime)
                    .font(.system(.body, design: .rounded))
                    .monospacedDigit()
            }
        }
        .disabled(!canLog)
    }
}
