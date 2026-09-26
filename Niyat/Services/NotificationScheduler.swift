import Foundation
import UserNotifications
import WidgetKit

/// Schedules prayer alerts (up to four per prayer) and the daily Qur'an
/// reminders. iOS keeps at most 64 pending notifications per app, so we schedule
/// the soonest ones and top them up every time the app opens or refreshes in the
/// background.
enum NotificationScheduler {
    private static let maxPending = 60

    enum Category {
        /// Prayer alerts at or after the prayer time, with a "Log Prayer" button.
        static let loggablePrayer = "PRAYER_LOGGABLE"
        static let prayer = "PRAYER"
        static let quranReminder = "QURAN_REMINDER"
    }

    enum Action {
        static let logPrayer = "LOG_PRAYER"
    }

    enum UserInfoKey {
        static let prayer = "prayer"
        static let dayKey = "dayKey"
        static let kind = "kind"
    }

    /// Registers the notification buttons. Call once at launch.
    static func registerCategories() {
        let log = UNNotificationAction(identifier: Action.logPrayer, title: "Log Prayer",
                                       options: [], icon: UNNotificationActionIcon(systemImageName: "checkmark.circle"))
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: Category.loggablePrayer, actions: [log], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.prayer, actions: [], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.quranReminder, actions: [], intentIdentifiers: []),
        ])
    }

    @discardableResult
    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func isAuthorized() async -> Bool {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional || status == .ephemeral
    }

    static func reschedule(location: SavedLocation?, prayerSettings: PrayerSettings,
                           notificationSettings: NotificationSettings,
                           quranReminders: QuranReminderSettings = SettingsStore.quranReminders) async {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        guard await isAuthorized() else { return }

        let now = Date()
        var candidates: [(date: Date, request: UNNotificationRequest)] = []

        if let location, !notificationSettings.enabledPrayers.isEmpty, !notificationSettings.timings.isEmpty {
            let records = PrayerLog.load()
            let upcoming = PrayerCalculator.upcoming(after: now.addingTimeInterval(-3600), count: 6 * 14, includeSunrise: true,
                                                     location: location, settings: prayerSettings)
            let calendar = PrayerCalculator.calendar(for: location)
            for time in upcoming where notificationSettings.enabledPrayers.contains(time.name) {
                let dayKey = PrayerLog.dayKey(for: calendar.startOfDay(for: time.date))
                let alreadyLogged = records["\(dayKey)|\(time.name.rawValue)"] != nil
                let timings: [AlertTiming] = time.name.isObligatory ? notificationSettings.timings.sorted() : [.atTime]
                for timing in timings {
                    // No point nagging about a prayer that's already logged.
                    if timing == .after30, alreadyLogged { continue }
                    let date = time.date.addingTimeInterval(TimeInterval(timing.minutes * 60))
                    guard date > now else { continue }
                    candidates.append((date, prayerRequest(for: time, timing: timing, dayKey: dayKey, location: location)))
                }
            }
        }

        if quranReminders.isEnabled {
            candidates += quranReminderRequests(settings: quranReminders, now: now)
        }

        candidates.sort { $0.date < $1.date }
        // Reserve one slot for the "open the app" nudge.
        let budget = maxPending - 1
        var requests = candidates.prefix(budget).map(\.request)
        if candidates.count > budget, let last = candidates.prefix(budget).last?.date {
            requests.append(refreshNudge(at: last.addingTimeInterval(30 * 60)))
        }
        for request in requests {
            try? await center.add(request)
        }
    }

    /// Called after a prayer is logged: removes its "30 minutes after" reminder.
    static func prayerLogged(_ prayer: PrayerName, dayKey: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [identifier(prayer: prayer, dayKey: dayKey, timing: .after30)])
    }

    private static func identifier(prayer: PrayerName, dayKey: String, timing: AlertTiming) -> String {
        "prayer.\(dayKey).\(prayer.rawValue).\(timing.rawValue)"
    }

    private static func trigger(at date: Date) -> UNCalendarNotificationTrigger {
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    }

    private static func prayerRequest(for time: PrayerTime, timing: AlertTiming, dayKey: String,
                                      location: SavedLocation) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        let name = time.name.displayName(on: time.date)
        switch (time.name, timing) {
        case (.sunrise, _):
            content.title = "Sunrise"
            content.body = "Fajr time has ended in \(location.name)."
        case (_, .before30), (_, .before10):
            content.title = "\(name) in \(-timing.minutes) minutes"
            content.body = "\(name) begins at \(time.date.shortTime). Time to get ready."
        case (_, .atTime):
            content.title = "\(name) · \(time.name.arabicName)"
            content.body = "It's time for \(name) in \(location.name)."
            content.interruptionLevel = .timeSensitive
        case (_, .after30):
            content.title = "Have you prayed \(name)?"
            content.body = "\(name) began 30 minutes ago. Tap Log Prayer once you've prayed."
        }
        content.sound = .default
        content.threadIdentifier = "prayer.\(dayKey)"
        content.userInfo = [UserInfoKey.prayer: time.name.rawValue, UserInfoKey.dayKey: dayKey, UserInfoKey.kind: "prayer"]
        content.categoryIdentifier = time.name.isObligatory && timing.offersLogging ? Category.loggablePrayer : Category.prayer
        return UNNotificationRequest(identifier: identifier(prayer: time.name, dayKey: dayKey, timing: timing),
                                     content: content, trigger: trigger(at: time.date.addingTimeInterval(TimeInterval(timing.minutes * 60))))
    }

    // MARK: Qur'an reminders

    private static func quranReminderRequests(settings: QuranReminderSettings, now: Date) -> [(date: Date, request: UNNotificationRequest)] {
        guard let goal = QuranProgress.dailyGoal else { return [] }
        let calendar = Calendar.current
        var result: [(date: Date, request: UNNotificationRequest)] = []
        for offset in 0..<3 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)) else { continue }
            let progress = offset == 0 ? QuranProgress.day(now) : QuranDay(goal: goal)
            let remaining = max(0, goal - progress.count)

            let morning = day.addingTimeInterval(TimeInterval(settings.morningMinute * 60))
            if morning > now, remaining > 0 {
                let content = UNMutableNotificationContent()
                content.title = "Your Qur'an goal is waiting"
                content.body = remaining == goal ? "\(goal) ayat today. Bismillah." : "\(remaining) ayat to go today."
                result.append((morning, quranRequest(id: "quran.morning.\(offset)", content: content, date: morning)))
            }

            let afternoon = day.addingTimeInterval(TimeInterval(settings.afternoonMinute * 60))
            if afternoon > now {
                let content = UNMutableNotificationContent()
                if remaining > 0 {
                    content.title = "Keep going"
                    content.body = remaining == goal
                        ? "There's still time for today's \(goal) ayat."
                        : "You're \(remaining) \(remaining == 1 ? "ayah" : "ayat") away from today's Qur'an goal."
                } else if settings.sendCompletionMessage {
                    content.title = "Today's Qur'an goal completed"
                    content.body = "Alhamdulillah. May Allah accept it from you."
                } else {
                    continue
                }
                result.append((afternoon, quranRequest(id: "quran.afternoon.\(offset)", content: content, date: afternoon)))
            }
        }
        return result
    }

    private static func quranRequest(id: String, content: UNMutableNotificationContent, date: Date) -> UNNotificationRequest {
        content.sound = .default
        content.threadIdentifier = "quran"
        content.categoryIdentifier = Category.quranReminder
        content.userInfo = [UserInfoKey.kind: "quran"]
        return UNNotificationRequest(identifier: id, content: content, trigger: trigger(at: date))
    }

    private static func refreshNudge(at date: Date) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "Keep your prayer alerts coming"
        content.body = "Open Niyat so it can schedule the next few days of alerts."
        content.sound = .default
        return UNNotificationRequest(identifier: "refresh-nudge", content: content, trigger: trigger(at: date))
    }

    // MARK: Testing

    /// Sends a sample alert in 5 seconds. It's for the prayer whose time is
    /// current, with the real "Log Prayer" button, so the whole flow can be tried.
    static func sendTest(location: SavedLocation?, current: PrayerTime?, next: PrayerTime?) async -> Bool {
        let allowed = await requestAuthorization()
        guard allowed else { return false }
        let content = UNMutableNotificationContent()
        if let current, current.name.isObligatory, let location {
            let name = current.name.displayName(on: current.date)
            let dayKey = PrayerLog.dayKey(for: PrayerCalculator.calendar(for: location).startOfDay(for: current.date))
            content.title = "\(name) · \(current.name.arabicName) (test)"
            content.body = "Long-press or pull down this alert and tap Log Prayer to try logging \(name) from here."
            content.categoryIdentifier = Category.loggablePrayer
            content.userInfo = [UserInfoKey.prayer: current.name.rawValue, UserInfoKey.dayKey: dayKey, UserInfoKey.kind: "prayer"]
        } else if let next {
            content.title = "Niyat test alert"
            content.body = "Adhan alerts are working. Next: \(next.name.displayName(on: next.date)) at \(next.date.shortTime)."
        } else {
            content.title = "Niyat test alert"
            content.body = "Adhan alerts are working."
        }
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        let request = UNNotificationRequest(identifier: "test.\(UUID().uuidString)", content: content,
                                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false))
        do {
            try await UNUserNotificationCenter.current().add(request)
            return true
        } catch {
            return false
        }
    }

    struct ScheduledAlert: Identifiable {
        let id: String
        let title: String
        let date: Date
    }

    /// Everything currently queued with iOS, soonest first.
    static func scheduledAlerts() async -> [ScheduledAlert] {
        await UNUserNotificationCenter.current().pendingNotificationRequests()
            .compactMap { request in
                guard let date = (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() else { return nil }
                return ScheduledAlert(id: request.identifier, title: request.content.title, date: date)
            }
            .sorted { $0.date < $1.date }
    }
}

/// Shows alerts while Niyat is open, handles the "Log Prayer" button, and opens
/// the Qur'an when a Qur'an reminder is tapped.
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationPresenter()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let kind = info[NotificationScheduler.UserInfoKey.kind] as? String

        if response.actionIdentifier == NotificationScheduler.Action.logPrayer,
           let raw = info[NotificationScheduler.UserInfoKey.prayer] as? String,
           let prayer = PrayerName(rawValue: raw),
           let dayKey = info[NotificationScheduler.UserInfoKey.dayKey] as? String {
            // logIfNeeded won't overwrite an existing log, so tapping twice (or
            // on both the adhan and the follow-up alert) never double-counts.
            if PrayerLog.logIfNeeded(prayer, dayKey: dayKey) {
                NotificationScheduler.prayerLogged(prayer, dayKey: dayKey)
                WidgetCenter.shared.reloadAllTimelines()
            }
            await MainActor.run {
                NotificationCenter.default.post(name: .prayerJournalChanged, object: nil)
            }
            return
        }

        if kind == "quran", response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            await MainActor.run { DeepLink.shared.pending = .quranContinueReading }
        }
    }
}
