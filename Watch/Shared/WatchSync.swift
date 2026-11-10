import Foundation
import WatchConnectivity
import WidgetKit

/// Keeps the Apple Watch in step with the iPhone. Compiled into both apps.
///
/// - iPhone → watch: the location, calculation and alert settings, the last
///   week of the prayer log and the Qur'an goal's recent days (the watch works
///   out prayer times and schedules its alerts itself, so it's right even when
///   the iPhone isn't nearby).
/// - Watch → iPhone: prayers logged on the wrist.
final class WatchSync: NSObject, WCSessionDelegate {
    static let shared = WatchSync()

    /// Posted on the watch when new data arrives from the iPhone.
    static let changed = Notification.Name("watchSyncChanged")

    private enum Key {
        static let location = "location"
        static let settings = "prayerSettings"
        static let records = "records"
        static let notifications = "notificationSettings"
        static let quranDays = "quranDays"
        static let quranGoal = "quranGoal"
        static let hijriAdjustment = "hijriAdjustment"
        static let theme = "theme"
        static let themeAccent = "themeAccent"
        static let themeHighlight = "themeHighlight"
        static let log = "log"
        static let day = "day"
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    #if os(iOS)
    /// Sends what the watch needs. Cheap to call often: iOS only keeps the latest.
    func push() {
        let session = WCSession.default
        guard WCSession.isSupported(), session.activationState == .activated,
              session.isPaired, session.isWatchAppInstalled else { return }
        let encoder = JSONEncoder()
        var context: [String: Any] = [:]
        if let location = SettingsStore.location, let data = try? encoder.encode(location) {
            context[Key.location] = data
        }
        if let data = try? encoder.encode(SettingsStore.prayerSettings) { context[Key.settings] = data }
        // The last week is plenty for the watch's "today" and streaks.
        let calendar = Calendar.current
        let recentDays = Set((0..<7).compactMap { calendar.date(byAdding: .day, value: -$0, to: .now) }
            .map(PrayerLog.dayKey(for:)))
        let recent = PrayerLog.load().filter { key, _ in
            recentDays.contains(String(key.prefix { $0 != "|" }))
        }
        if let data = try? encoder.encode(recent) { context[Key.records] = data }
        // Which alerts to show on the wrist, and the Qur'an goal (60 days covers the streak).
        if let data = try? encoder.encode(SettingsStore.notificationSettings) { context[Key.notifications] = data }
        if let data = try? encoder.encode(QuranProgress.recent(days: 60)) { context[Key.quranDays] = data }
        context[Key.quranGoal] = QuranProgress.dailyGoal ?? 0
        context[Key.hijriAdjustment] = SettingsStore.hijriAdjustment
        // The watch draws in the same theme as the iPhone.
        let theme = ThemeManager.shared
        context[Key.theme] = theme.selectedID
        if let data = try? encoder.encode(theme.customAccent) { context[Key.themeAccent] = data }
        if let data = try? encoder.encode(theme.customHighlight) { context[Key.themeHighlight] = data }
        try? session.updateApplicationContext(context)
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        // Switched to another watch: start again with it.
        WCSession.default.activate()
    }

    /// A prayer logged on the watch.
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let raw = userInfo[Key.log] as? String, let prayer = PrayerName(rawValue: raw),
              let day = userInfo[Key.day] as? String else { return }
        DispatchQueue.main.async {
            if PrayerLog.logIfNeeded(prayer, dayKey: day) {
                NotificationScheduler.prayerLogged(prayer, dayKey: day)
                WidgetCenter.shared.reloadAllTimelines()
            }
            NotificationCenter.default.post(name: .prayerJournalChanged, object: nil)
        }
    }
    #endif

    #if os(watchOS)
    /// Logs a prayer on the watch and tells the iPhone.
    func log(_ prayer: PrayerName, dayKey: String) {
        guard PrayerLog.logIfNeeded(prayer, dayKey: dayKey) else { return }
        WidgetCenter.shared.reloadAllTimelines()
        if WCSession.isSupported() {
            WCSession.default.transferUserInfo([Key.log: prayer.rawValue, Key.day: dayKey])
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        apply(context)
    }

    private func apply(_ context: [String: Any]) {
        let decoder = JSONDecoder()
        if let data = context[Key.location] as? Data, let location = try? decoder.decode(SavedLocation.self, from: data) {
            SettingsStore.location = location
        }
        if let data = context[Key.settings] as? Data, let settings = try? decoder.decode(PrayerSettings.self, from: data) {
            SettingsStore.prayerSettings = settings
        }
        if let data = context[Key.records] as? Data,
           let recent = try? decoder.decode([String: PrayerRecord].self, from: data) {
            // The iPhone is the record keeper; keep anything logged here meanwhile.
            PrayerLog.save(PrayerLog.load().merging(recent) { _, phone in phone })
        }
        if let data = context[Key.notifications] as? Data,
           let settings = try? decoder.decode(NotificationSettings.self, from: data) {
            SettingsStore.notificationSettings = settings
        }
        if let data = context[Key.quranDays] as? Data, let days = try? decoder.decode([String: QuranDay].self, from: data) {
            let goal = context[Key.quranGoal] as? Int ?? 0
            QuranProgress.merge(days, goal: goal > 0 ? goal : nil)
        }
        if let days = context[Key.hijriAdjustment] as? Int { SettingsStore.hijriAdjustment = days }
        if let id = context[Key.theme] as? String {
            let accent = (context[Key.themeAccent] as? Data).flatMap { try? decoder.decode(ThemeColor.self, from: $0) }
            let highlight = (context[Key.themeHighlight] as? Data).flatMap { try? decoder.decode(ThemeColor.self, from: $0) }
            DispatchQueue.main.async {
                let theme = ThemeManager.shared
                if id == "custom", let accent, let highlight {
                    theme.setCustom(accent: accent, highlight: highlight)
                } else if theme.selectedID != id {
                    theme.select(id)
                }
            }
        }
        WidgetCenter.shared.reloadAllTimelines()
        DispatchQueue.main.async { NotificationCenter.default.post(name: WatchSync.changed, object: nil) }
    }
    #endif

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        #if os(iOS)
        DispatchQueue.main.async { self.push() }
        #else
        if !session.receivedApplicationContext.isEmpty { apply(session.receivedApplicationContext) }
        #endif
    }
}
