import Foundation
import UserNotifications

/// Schedules the adhan alerts. iOS only keeps 64 pending notifications per app, so
/// we schedule as many days ahead as fit and top them up every time the app opens
/// (and in background refreshes).
enum NotificationScheduler {
    private static let maxPending = 60

    @discardableResult
    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func isAuthorized() async -> Bool {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional || status == .ephemeral
    }

    static func reschedule(location: SavedLocation?, prayerSettings: PrayerSettings,
                           notificationSettings: NotificationSettings) async {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        guard let location, !notificationSettings.enabledPrayers.isEmpty, await isAuthorized() else { return }

        let now = Date()
        let reminder = notificationSettings.reminderMinutesBefore
        // Reserve one slot for the "open the app" nudge.
        let budget = maxPending - 1
        var requests: [UNNotificationRequest] = []

        var lastScheduled: Date?
        var ranOutOfSlots = false

        // Up to 3 weeks of times; usually the 60-slot budget runs out first.
        let upcoming = PrayerCalculator.upcoming(after: now, count: 6 * 21, includeSunrise: true,
                                                 location: location, settings: prayerSettings)
        for time in upcoming where notificationSettings.enabledPrayers.contains(time.name) {
            var batch = [prayerRequest(for: time, location: location)]
            if reminder > 0, time.name.isObligatory {
                let reminderDate = time.date.addingTimeInterval(TimeInterval(-reminder * 60))
                if reminderDate > now { batch.append(reminderRequest(for: time, at: reminderDate, minutes: reminder)) }
            }
            guard requests.count + batch.count <= budget else {
                ranOutOfSlots = true
                break
            }
            requests.append(contentsOf: batch)
            lastScheduled = time.date
        }

        if ranOutOfSlots, let lastScheduled {
            requests.append(refreshNudge(at: lastScheduled.addingTimeInterval(30 * 60)))
        }

        for request in requests {
            try? await center.add(request)
        }
    }

    /// Sends a sample adhan alert in a few seconds, to check notifications work.
    /// Lock the phone after tapping to see it as you would at prayer time.
    static func sendTest(location: SavedLocation?, next: PrayerTime?) async -> Bool {
        let allowed = await requestAuthorization()
        guard allowed else { return false }
        let content = UNMutableNotificationContent()
        if let next {
            let name = next.name.displayName(on: next.date)
            content.title = "\(name) · \(next.name.arabicName)"
            content.body = "Test alert. The real one will say: It's time for \(name) in \(location?.name ?? "your city")."
        } else {
            content.title = "Niyat test alert"
            content.body = "Adhan notifications are working."
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

    private static func trigger(at date: Date) -> UNCalendarNotificationTrigger {
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    }

    private static func prayerRequest(for time: PrayerTime, location: SavedLocation) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        let name = time.name.displayName(on: time.date)
        if time.name == .sunrise {
            content.title = "Sunrise"
            content.body = "Fajr time has ended in \(location.name)."
        } else {
            content.title = "\(name) · \(time.name.arabicName)"
            content.body = "It's time for \(name) in \(location.name)."
        }
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.threadIdentifier = "prayer"
        return UNNotificationRequest(identifier: "prayer.\(time.id)", content: content, trigger: trigger(at: time.date))
    }

    private static func reminderRequest(for time: PrayerTime, at date: Date, minutes: Int) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        let name = time.name.displayName(on: time.date)
        content.title = "\(name) in \(minutes) minutes"
        content.body = "Get ready for \(name) at \(time.date.shortTime)."
        content.sound = .default
        content.threadIdentifier = "reminder"
        return UNNotificationRequest(identifier: "reminder.\(time.id)", content: content, trigger: trigger(at: date))
    }

    private static func refreshNudge(at date: Date) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "Keep your prayer alerts coming"
        content.body = "Open Niyat so it can schedule the next few days of adhan notifications."
        content.sound = .default
        return UNNotificationRequest(identifier: "refresh-nudge", content: content, trigger: trigger(at: date))
    }
}

/// Shows adhan alerts even while Niyat is open (iOS hides them by default).
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationPresenter()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
