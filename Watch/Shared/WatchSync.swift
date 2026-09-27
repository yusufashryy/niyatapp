import Foundation
import WatchConnectivity
import WidgetKit

/// Keeps the Apple Watch in step with the iPhone. Compiled into both apps.
///
/// - iPhone → watch: the location, calculation settings and the last week of
///   the prayer log (the watch works out prayer times itself, so it's right
///   even when the iPhone isn't nearby).
/// - Watch → iPhone: prayers logged on the wrist.
final class WatchSync: NSObject, WCSessionDelegate {
    static let shared = WatchSync()

    /// Posted on the watch when new data arrives from the iPhone.
    static let changed = Notification.Name("watchSyncChanged")

    private enum Key {
        static let location = "location"
        static let settings = "prayerSettings"
        static let records = "records"
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
