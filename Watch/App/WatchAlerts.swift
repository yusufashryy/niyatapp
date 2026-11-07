import Foundation
import SwiftUI
import UserNotifications
import WatchKit

/// Prayer alerts scheduled on the watch itself, so they come even when the
/// iPhone is out of reach. They follow the same plan, with the same
/// identifiers, as the iPhone's (`PrayerAlertPlan`), which is what lets
/// watchOS show each one once when both have it.
enum WatchAlerts {
    /// The watch keeps fewer pending alerts than the iPhone; two days or so is plenty
    /// between refreshes.
    private static let limit = 24

    static let category = "PRAYER_LOGGABLE"
    static let logAction = "LOG_PRAYER"

    static func registerCategory() {
        let log = UNNotificationAction(identifier: logAction, title: "Log Prayer", options: [],
                                       icon: UNNotificationActionIcon(systemImageName: "checkmark.circle"))
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: category, actions: [log], intentIdentifiers: []),
        ])
    }

    static func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    /// Not asked yet: the intro explains the alerts before iOS asks.
    static func needsAsking() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .notDetermined
    }

    /// Replaces the scheduled alerts with the next ones.
    static func reschedule() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("prayer.") }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        guard let location = SettingsStore.location else { return }

        let now = Date()
        let settings = SettingsStore.notificationSettings
        let upcoming = PrayerCalculator.upcoming(after: now.addingTimeInterval(-3600), count: 6 * 3, includeSunrise: true,
                                                 location: location, settings: SettingsStore.prayerSettings)
        let calendar = PrayerCalculator.calendar(for: location)
        let plan = PrayerAlertPlan.alerts(for: upcoming, settings: settings,
                                          dayKey: { PrayerLog.dayKey(for: calendar.startOfDay(for: $0)) },
                                          logged: Set(PrayerLog.load().keys), now: now, limit: limit)
        for alert in plan {
            try? await center.add(request(for: alert))
        }
    }

    private static func request(for alert: PrayerAlertPlan.Alert) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        let name = alert.prayer.displayName(on: alert.time.date)
        switch (alert.prayer, alert.timing) {
        case (.sunrise, _):
            content.title = "Sunrise"
            content.body = "Fajr time has ended."
        case (_, .before30), (_, .before10):
            content.title = "\(name) in \(-alert.timing.minutes) minutes"
            content.body = "\(name) begins at \(alert.time.date.shortTime)."
        case (_, .atTime):
            content.title = "\(name) · \(alert.prayer.arabicName)"
            content.body = "It's time for \(name)."
            content.interruptionLevel = .timeSensitive
        case (_, .after30):
            content.title = "Have you prayed \(name)?"
            content.body = "\(name) began 30 minutes ago."
        }
        content.sound = .default
        content.threadIdentifier = "prayer.\(alert.dayKey)"
        content.userInfo = ["prayer": alert.prayer.rawValue, "dayKey": alert.dayKey]
        if alert.prayer.isObligatory, alert.timing.offersLogging { content.categoryIdentifier = category }
        // Pinned to its time zone, so it fires at the right moment after a flight (see 7.1).
        return UNNotificationRequest(identifier: alert.id, content: content,
                                     trigger: UNCalendarNotificationTrigger(dateMatching: alert.date.fixedDateComponents(),
                                                                            repeats: false))
    }
}

/// Handles "Log Prayer" on the wrist, and shows alerts while the app is open.
final class WatchAlertPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = WatchAlertPresenter()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        DispatchQueue.main.async { completionHandler([.banner, .list, .sound]) }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let action = response.actionIdentifier
        DispatchQueue.main.async {
            defer { completionHandler() }
            guard action == WatchAlerts.logAction,
                  let prayer = (info["prayer"] as? String).flatMap(PrayerName.init(rawValue:)),
                  let dayKey = info["dayKey"] as? String else { return }
            WatchSync.shared.log(prayer, dayKey: dayKey)
            // Drop its "have you prayed?" follow-up.
            UNUserNotificationCenter.current().removePendingNotificationRequests(
                withIdentifiers: [PrayerAlertPlan.identifier(prayer: prayer, dayKey: dayKey, timing: .after30)])
            NotificationCenter.default.post(name: WatchSync.changed, object: nil)
        }
    }
}

/// Shown once, before iOS asks to allow notifications on the watch.
struct WatchAlertsIntro: View {
    let onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Image(systemName: "bell.badge.fill")
                    .font(.title2)
                    .foregroundStyle(Palette.highlight)
                Text("Prayer alerts on your wrist")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text("They come even when your iPhone isn't with you, and you can log a prayer from the alert.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Continue") {
                    Task {
                        await WatchAlerts.requestAuthorization()
                        await WatchAlerts.reschedule()
                        onDone()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.control)
            }
            .padding(.horizontal, 4)
        }
    }
}
