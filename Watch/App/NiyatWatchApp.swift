import SwiftUI
import UserNotifications
import WatchKit

/// Niyat on Apple Watch: the next prayer at a glance, today's times with a
/// tap to log, the Qibla, a tasbih on the Digital Crown and the Qur'an goal.
/// Times are worked out on the watch from the location and settings the
/// iPhone sends (see WatchSync), and its own alerts come without the iPhone.
@main
struct NiyatWatchApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        WatchSync.shared.activate()
        UNUserNotificationCenter.current().delegate = WatchAlertPresenter.shared
        WatchAlerts.registerCategory()
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .task {
                    await WatchAlerts.reschedule()
                    Self.scheduleRefresh()
                }
                .task {
                    // New settings or times from the iPhone: redo the alerts.
                    for await _ in NotificationCenter.default.notifications(named: WatchSync.changed) {
                        await WatchAlerts.reschedule()
                    }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await WatchAlerts.reschedule() } }
        }
        // Tops the alerts up about twice a day, even if the app isn't opened.
        .backgroundTask(.appRefresh(Self.refreshTask)) {
            await WatchAlerts.reschedule()
            await MainActor.run { Self.scheduleRefresh() }
        }
    }

    private static let refreshTask = "niyat.alerts"

    // BGTaskScheduler isn't available to watch apps in this SDK, so this uses WatchKit's.
    @MainActor
    private static func scheduleRefresh() {
        WKApplication.shared().scheduleBackgroundRefresh(withPreferredDate: .now.addingTimeInterval(12 * 3600),
                                                         userInfo: refreshTask as NSString) { _ in }
    }
}

/// Watch-side state: re-read when the iPhone sends new data.
@MainActor
@Observable
final class WatchStore {
    private(set) var location = SettingsStore.location
    private(set) var settings = SettingsStore.prayerSettings
    private(set) var records = PrayerLog.load()
    private(set) var quranDay = QuranProgress.day()
    private(set) var quranGoal = QuranProgress.dailyGoal
    private(set) var quranStreak = QuranProgress.currentStreak()

    init() {
        NotificationCenter.default.addObserver(forName: WatchSync.changed, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
    }

    func reload() {
        location = SettingsStore.location
        settings = SettingsStore.prayerSettings
        records = PrayerLog.load()
        quranDay = QuranProgress.day()
        quranGoal = QuranProgress.dailyGoal
        quranStreak = QuranProgress.currentStreak()
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
    @State private var showsAlertsIntro = false

    var body: some View {
        // Redraws every minute so the countdown and "next prayer" stay current.
        TimelineView(.everyMinute) { context in
            if let location = store.location, let next = store.next(after: context.date) {
                TabView {
                    WatchNextPrayerPage(next: next, now: context.date, locationName: location.name)
                    if let schedule = store.schedule(at: context.date) {
                        WatchTodayPage(schedule: schedule, now: context.date, store: store)
                    }
                    WatchQiblaPage(location: location)
                    WatchTasbihPage()
                    WatchQuranPage(day: store.quranDay, goal: store.quranGoal, streak: store.quranStreak)
                }
                .tabViewStyle(.verticalPage)
                .task { showsAlertsIntro = await WatchAlerts.needsAsking() }
                .sheet(isPresented: $showsAlertsIntro) { WatchAlertsIntro { showsAlertsIntro = false } }
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
    /// The minute it was drawn (the page redraws every minute).
    let now: Date
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
            // Counted down by the minute: a live `Text(_:style: .relative)` here kept
            // the watch redrawing nonstop (100% CPU in the simulator).
            Text(Self.countdown(from: now, to: next.date))
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
        .containerBackground(for: .tabView) { WatchBackground() }
    }

    /// "in 6 hr 54 min", to the minute.
    static func countdown(from now: Date, to date: Date) -> String {
        let minutes = max(Int((date.timeIntervalSince(now) / 60).rounded(.up)), 0)
        let duration = Duration.seconds(minutes * 60)
        return "in " + duration.formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
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
        .containerBackground(for: .tabView) { WatchBackground() }
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
