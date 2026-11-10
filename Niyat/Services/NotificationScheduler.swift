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
        static let surah = "surah"
        static let verse = "verse"
        /// The muezzin whose athan the alert plays (`Muezzin.rawValue`).
        static let athan = "athan"
    }

    /// An athan alert's sound: the muezzin's opening, bundled with the app.
    static func sound(for muezzin: Muezzin?) -> UNNotificationSound {
        muezzin.map { UNNotificationSound(named: UNNotificationSoundName($0.alertSoundName)) } ?? .default
    }

    /// Registers the notification buttons. Call once at launch.
    static func registerCategories() {
        let log = UNNotificationAction(identifier: Action.logPrayer, title: "Log Prayer",
                                       options: [], icon: UNNotificationActionIcon(systemImageName: "checkmark.circle"))
        UNUserNotificationCenter.current().setNotificationCategories([
            // Dismissing a prayer alert is reported, to stop the rest of a whole athan.
            UNNotificationCategory(identifier: Category.loggablePrayer, actions: [log], intentIdentifiers: [],
                                   options: [.customDismissAction]),
            UNNotificationCategory(identifier: Category.prayer, actions: [], intentIdentifiers: [],
                                   options: [.customDismissAction]),
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

    /// The reschedule in progress, so a new one waits for it instead of both
    /// clearing and adding alerts at the same time.
    @MainActor private static var lastReschedule: Task<Void, Never>?

    @MainActor
    static func reschedule(location: SavedLocation?, prayerSettings: PrayerSettings,
                           notificationSettings: NotificationSettings,
                           quranReminders: QuranReminderSettings = SettingsStore.quranReminders,
                           athan: AthanSettings = SettingsStore.athan) async {
        let previous = lastReschedule
        let task = Task { @MainActor in
            await previous?.value
            await performReschedule(location: location, prayerSettings: prayerSettings,
                                    notificationSettings: notificationSettings, quranReminders: quranReminders,
                                    athan: athan)
        }
        lastReschedule = task
        await task.value
    }

    /// Test alerts are never cleared by a reschedule.
    private static func isTest(_ identifier: String) -> Bool {
        identifier.hasPrefix("test.") || identifier == "quran.test"
    }

    private static func performReschedule(location: SavedLocation?, prayerSettings: PrayerSettings,
                                           notificationSettings: NotificationSettings,
                                           quranReminders: QuranReminderSettings, athan: AthanSettings) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { !isTest($0) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        guard await isAuthorized() else { return }

        let now = Date()
        var candidates: [(date: Date, request: UNNotificationRequest)] = []

        if let location, !notificationSettings.enabledPrayers.isEmpty, !notificationSettings.timings.isEmpty {
            let upcoming = PrayerCalculator.upcoming(after: now.addingTimeInterval(-3600), count: 6 * 14, includeSunrise: true,
                                                     location: location, settings: prayerSettings)
            let calendar = PrayerCalculator.calendar(for: location)
            // The same plan as the Apple Watch's, so the two sets of alerts match.
            let plan = PrayerAlertPlan.alerts(for: upcoming, settings: notificationSettings,
                                              dayKey: { PrayerLog.dayKey(for: calendar.startOfDay(for: $0)) },
                                              logged: Set(PrayerLog.load().keys), now: now, limit: maxPending)
            // The whole athan from the alert, for the next few prayers (each
            // takes several of the 64 alerts iOS allows).
            var fullAthans = 0
            for alert in plan {
                let muezzin = athan.muezzin(for: alert.prayer, timing: alert.timing)
                var parts: [TimeInterval]?
                if athan.fullAthanFromAlert, let muezzin, fullAthans < AthanSegments.prayersAhead {
                    parts = FullAthanStore.parts(for: muezzin)
                    if parts != nil { fullAthans += 1 }
                }
                candidates.append((alert.date, prayerRequest(for: alert.time, timing: alert.timing, dayKey: alert.dayKey,
                                                             location: location, muezzin: muezzin, fullAthan: parts != nil)))
                if let muezzin, let parts {
                    for part in AthanSegments.followUps(start: alert.date, parts: parts) {
                        candidates.append((part.date, athanPartRequest(muezzin: muezzin, part: part.index, date: part.date,
                                                                       prayer: alert.prayer, dayKey: alert.dayKey)))
                    }
                }
            }
        }

        if quranReminders.isEnabled {
            candidates += quranReminderRequests(settings: quranReminders, now: now)
        }

        // The hadiths are only read (off the main thread, once) if the daily hadith is on.
        let hadithSettings = HadithReminderSettings.saved
        if hadithSettings.isEnabled, let index = await HadithLibrary.shared.load() {
            for (index, item) in HadithReminders.plan(settings: hadithSettings, index: index, now: now).enumerated() {
                candidates.append((item.date, UNNotificationRequest(identifier: "hadith.\(index)",
                                                                   content: HadithReminders.content(for: item.hadith),
                                                                   trigger: trigger(at: item.date))))
            }
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
        let identifiers = [identifier(prayer: prayer, dayKey: dayKey, timing: .after30)]
        // This call waits for iOS's notification service; off the main thread
        // so a slow service can never freeze the app (it did, in testing).
        DispatchQueue.global(qos: .utility).async {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
        }
    }

    private static func identifier(prayer: PrayerName, dayKey: String, timing: AlertTiming) -> String {
        PrayerAlertPlan.identifier(prayer: prayer, dayKey: dayKey, timing: timing)
    }

    private static func trigger(at date: Date) -> UNCalendarNotificationTrigger {
        UNCalendarNotificationTrigger(dateMatching: date.fixedDateComponents(), repeats: false)
    }

    /// A later part of the whole athan: sound only, so it continues the
    /// alert without another banner.
    private static func athanPartRequest(muezzin: Muezzin, part: Int, date: Date,
                                         prayer: PrayerName, dayKey: String) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.sound = UNNotificationSound(named: UNNotificationSoundName(AthanSegments.fileName(muezzin, part: part)))
        content.interruptionLevel = .timeSensitive
        content.threadIdentifier = "prayer.\(dayKey)"
        content.userInfo = [UserInfoKey.kind: "athanPart", UserInfoKey.prayer: prayer.rawValue, UserInfoKey.dayKey: dayKey]
        // To the second, so the parts follow one another without a gap, and in
        // a fixed time zone, so they stay with the alert when you travel.
        return UNNotificationRequest(identifier: AthanSegments.followUpIdentifier(prayer: prayer, dayKey: dayKey, part: part),
                                     content: content,
                                     trigger: trigger(at: date))
    }

    /// Stops the rest of a whole athan: the alert was opened, dismissed or
    /// answered, or Niyat is playing the athan itself.
    static func cancelAthanParts(prayer: PrayerName, dayKey: String) {
        // Every part of this prayer's athan, however many it was cut into.
        let prefix = AthanSegments.followUpPrefix(prayer: prayer, dayKey: dayKey)
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            let identifiers = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
        }
        center.getDeliveredNotifications { delivered in
            let identifiers = delivered.map(\.request.identifier).filter { $0.hasPrefix(prefix) }
            center.removeDeliveredNotifications(withIdentifiers: identifiers)
        }
    }

    private static func prayerRequest(for time: PrayerTime, timing: AlertTiming, dayKey: String,
                                      location: SavedLocation, muezzin: Muezzin?, fullAthan: Bool = false) -> UNNotificationRequest {
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
        if fullAthan, let muezzin {
            content.sound = UNNotificationSound(named: UNNotificationSoundName(AthanSegments.fileName(muezzin, part: 0)))
        } else {
            content.sound = sound(for: muezzin)
        }
        content.threadIdentifier = "prayer.\(dayKey)"
        content.userInfo = [UserInfoKey.prayer: time.name.rawValue, UserInfoKey.dayKey: dayKey, UserInfoKey.kind: "prayer"]
        if let muezzin { content.userInfo[UserInfoKey.athan] = muezzin.rawValue }
        content.categoryIdentifier = time.name.isObligatory && timing.offersLogging ? Category.loggablePrayer : Category.prayer
        return UNNotificationRequest(identifier: identifier(prayer: time.name, dayKey: dayKey, timing: timing),
                                     content: content, trigger: trigger(at: time.date.addingTimeInterval(TimeInterval(timing.minutes * 60))))
    }

    // MARK: Qur'an reminders

    private static func quranReminderRequests(settings: QuranReminderSettings, now: Date) -> [(date: Date, request: UNNotificationRequest)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        var result: [(date: Date, request: UNNotificationRequest)] = []
        func at(_ day: Date, _ minute: Int) -> Date { day.addingTimeInterval(TimeInterval(minute * 60)) }

        // Goal reminders: a few days ahead. Future days assume nothing is read
        // yet; reading reschedules them, so finished days go quiet.
        if let goal = QuranProgress.dailyGoal {
            let streak = QuranProgress.currentStreak(asOf: now)
            for offset in 0..<3 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
                let progress = offset == 0 ? QuranProgress.day(now) : QuranDay(goal: goal)
                let remaining = max(0, goal - progress.count)

                let morning = at(day, settings.morningMinute)
                if settings.morningEnabled, morning > now, remaining > 0 {
                    let content = UNMutableNotificationContent()
                    content.title = "Your Qur'an goal is waiting"
                    content.body = remaining == goal ? "\(goal) ayat today. Bismillah." : "\(remaining) ayat to go today."
                    result.append((morning, quranRequest(id: "quran.morning.\(offset)", content: content, date: morning)))
                }

                let afternoon = at(day, settings.afternoonMinute)
                if settings.afternoonEnabled, afternoon > now {
                    let content = UNMutableNotificationContent()
                    if remaining > 0 {
                        content.title = "Keep going"
                        content.body = remaining == goal
                            ? "There's still time for today's \(goal) ayat."
                            : "You're \(remaining) \(remaining == 1 ? "ayah" : "ayat") away from today's Qur'an goal."
                        result.append((afternoon, quranRequest(id: "quran.afternoon.\(offset)", content: content, date: afternoon)))
                    } else if settings.sendCompletionMessage {
                        content.title = "Today's Qur'an goal completed"
                        content.body = "Alhamdulillah. May Allah accept it from you."
                        result.append((afternoon, quranRequest(id: "quran.afternoon.\(offset)", content: content, date: afternoon)))
                    }
                }

                let evening = at(day, settings.eveningMinute)
                if settings.eveningEnabled, evening > now, remaining > 0 {
                    let content = UNMutableNotificationContent()
                    // Tomorrow's streak is today's +1 if today gets done.
                    let atRisk = offset == 0 ? streak : streak + offset - 1
                    content.title = atRisk > 0 ? "Keep your \(atRisk)-day streak" : "A few ayat before bed?"
                    content.body = "\(remaining) \(remaining == 1 ? "ayah" : "ayat") left today. Even a little counts."
                    result.append((evening, quranRequest(id: "quran.evening.\(offset)", content: content, date: evening)))
                }
            }
        }

        // Verse of the day: a week ahead, each opening at that verse.
        if settings.verseOfDayEnabled {
            for offset in 0..<7 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
                let date = at(day, settings.verseOfDayMinute)
                guard date > now else { continue }
                let verse = DailyVerse.forDay(day)
                let content = UNMutableNotificationContent()
                content.title = "Verse of the day · \(verse.reference)"
                content.body = verse.english
                result.append((date, quranRequest(id: "quran.verse.\(offset)", content: content, date: date,
                                                  opening: VerseReference(surah: verse.surah, verse: verse.ayah))))
            }
        }

        // Surah Al-Kahf on the next two Fridays.
        if settings.kahfEnabled {
            var fridays = 0
            for offset in 0..<14 where fridays < 2 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                      calendar.component(.weekday, from: day) == 6 else { continue }
                fridays += 1
                let date = at(day, settings.kahfMinute)
                guard date > now else { continue }
                let content = UNMutableNotificationContent()
                content.title = "Jumu'ah Mubarak"
                content.body = "It's Friday. Tap to read Surah Al-Kahf."
                result.append((date, quranRequest(id: "quran.kahf.\(offset)", content: content, date: date,
                                                  opening: VerseReference(surah: 18, verse: 1))))
            }
        }
        return result
    }

    private static func quranRequest(id: String, content: UNMutableNotificationContent, date: Date,
                                     opening verse: VerseReference? = nil) -> UNNotificationRequest {
        content.sound = .default
        content.threadIdentifier = "quran"
        content.categoryIdentifier = Category.quranReminder
        var info: [String: Any] = [UserInfoKey.kind: "quran"]
        if let verse {
            info[UserInfoKey.surah] = verse.surah
            info[UserInfoKey.verse] = verse.verse
        }
        content.userInfo = info
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

    /// Seconds before a test alert arrives: long enough to lock the phone.
    static let testDelay: TimeInterval = 8

    /// Sends a sample alert in a few seconds. It's for the prayer whose time is
    /// current, with the real "Log Prayer" button, so the whole flow can be tried.
    static func sendTest(location: SavedLocation?, current: PrayerTime?, next: PrayerTime?) async -> Bool {
        let allowed = await requestAuthorization()
        guard allowed else { return false }
        let content = UNMutableNotificationContent()
        let muezzin = SettingsStore.athan.muezzin(for: current?.name ?? .dhuhr, timing: .atTime)
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
        content.sound = sound(for: muezzin)
        if let muezzin { content.userInfo[UserInfoKey.athan] = muezzin.rawValue }
        content.interruptionLevel = .timeSensitive
        let request = UNNotificationRequest(identifier: "test.\(UUID().uuidString)", content: content,
                                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: testDelay, repeats: false))
        do {
            try await UNUserNotificationCenter.current().add(request)
            return true
        } catch {
            return false
        }
    }

    /// iPhone settings that would stop alerts from being seen, in plain words.
    static func problems() async -> [String] {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        var result: [String] = []
        switch settings.authorizationStatus {
        case .denied:
            return ["Notifications are turned off for Niyat. Turn on Allow Notifications in the Settings app › Notifications › Niyat."]
        case .notDetermined:
            return ["Niyat hasn't been allowed to send notifications yet."]
        default:
            break
        }
        if settings.lockScreenSetting == .disabled {
            result.append("Lock Screen alerts are off. Turn on Lock Screen in Settings › Notifications › Niyat.")
        }
        if settings.alertSetting == .disabled, settings.notificationCenterSetting == .disabled {
            result.append("Alerts are hidden. Turn on Banners and Notification Centre in Settings › Notifications › Niyat.")
        }
        if settings.scheduledDeliverySetting == .enabled {
            result.append("Niyat is in your Scheduled Summary, so alerts are held back. Set it to Immediate Delivery in Settings › Notifications › Niyat.")
        }
        if settings.soundSetting == .disabled {
            result.append("Sounds are off for Niyat's notifications.")
        }
        return result
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

/// Shows alerts while Niyat is open, handles the "Log Prayer" button, opens
/// the Qur'an when a Qur'an reminder is tapped, and plays the full athan when
/// a prayer alert is opened (or comes while Niyat is open).
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationPresenter()

    // Completion-handler versions, answered on the main thread: the async
    // versions can finish off the main thread, which crashed or froze the app
    // (a black screen) when it was opened from a notification.

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let athan = Self.fullAthan(for: notification)
        let info = notification.request.content.userInfo
        let isAthanPart = info[NotificationScheduler.UserInfoKey.kind] as? String == "athanPart"
        let prayer = (info[NotificationScheduler.UserInfoKey.prayer] as? String).flatMap(PrayerName.init(rawValue:))
        let dayKey = info[NotificationScheduler.UserInfoKey.dayKey] as? String
        DispatchQueue.main.async {
            if isAthanPart {
                // A later part of the whole athan: heard, never shown; silent
                // if Niyat is already playing the athan itself.
                let playing = MainActor.assumeIsolated { AthanPlayer.shared.playing != nil }
                completionHandler(playing ? [] : [.sound])
            } else if let athan {
                // The full athan instead of its opening, so they don't play over each other.
                MainActor.assumeIsolated { AthanPlayer.shared.play(athan) }
                if let prayer, let dayKey { NotificationScheduler.cancelAthanParts(prayer: prayer, dayKey: dayKey) }
                completionHandler([.banner, .list])
            } else {
                completionHandler([.banner, .list, .sound])
            }
        }
    }

    /// The athan to play in full for an alert, if it has one and that's turned on.
    private static func fullAthan(for notification: UNNotification) -> Muezzin? {
        let info = notification.request.content.userInfo
        guard SettingsStore.athan.playsFullAthan,
              let id = info[NotificationScheduler.UserInfoKey.athan] as? String else { return nil }
        return Muezzin(rawValue: id)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let kind = info[NotificationScheduler.UserInfoKey.kind] as? String
        let action = response.actionIdentifier
        let prayer = (info[NotificationScheduler.UserInfoKey.prayer] as? String).flatMap(PrayerName.init(rawValue:))
        let dayKey = info[NotificationScheduler.UserInfoKey.dayKey] as? String
        let surah = info[NotificationScheduler.UserInfoKey.surah] as? Int
        let verse = info[NotificationScheduler.UserInfoKey.verse] as? Int
        let hadithID = info["hadith"] as? Int
        let athan = action == UNNotificationDefaultActionIdentifier ? Self.fullAthan(for: response.notification) : nil

        DispatchQueue.main.async {
            defer { completionHandler() }
            // Opened, dismissed or answered: the rest of a whole athan stops.
            if kind == "prayer" || kind == "athanPart", let prayer, let dayKey {
                NotificationScheduler.cancelAthanParts(prayer: prayer, dayKey: dayKey)
            }
            if action == UNNotificationDismissActionIdentifier { return }
            if action == NotificationScheduler.Action.logPrayer, let prayer, let dayKey {
                // logIfNeeded won't overwrite an existing log, so tapping twice (or
                // on both the adhan and the follow-up alert) never double-counts.
                if PrayerLog.logIfNeeded(prayer, dayKey: dayKey) {
                    NotificationScheduler.prayerLogged(prayer, dayKey: dayKey)
                    WidgetCenter.shared.reloadAllTimelines()
                }
                NotificationCenter.default.post(name: .prayerJournalChanged, object: nil)
                return
            }
            if let athan {
                MainActor.assumeIsolated { AthanPlayer.shared.play(athan) }
                return
            }
            if kind == "hadith", action == UNNotificationDefaultActionIdentifier, let id = hadithID {
                MainActor.assumeIsolated { DeepLink.shared.pending = .hadith(id: id) }
                return
            }
            if kind == "quran", action == UNNotificationDefaultActionIdentifier {
                MainActor.assumeIsolated {
                    if let surah, let verse {
                        DeepLink.shared.pending = .quranVerse(surah: surah, verse: verse)
                    } else {
                        DeepLink.shared.pending = .quranContinueReading
                    }
                }
            }
        }
    }
}
