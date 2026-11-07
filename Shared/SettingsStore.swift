import Foundation

/// Reads and writes settings in the App Group so widgets and extensions see them too.
enum SettingsStore {
    private enum Key {
        static let location = "location"
        static let prayerSettings = "prayerSettings"
        static let notificationSettings = "notificationSettings"
        static let hijriAdjustment = "hijriAdjustment"
        static let quranReminders = "quranReminders"
        static let athan = "athan"
        static let locationMode = "locationMode"
        static let timeZonePromptDismissed = "timeZonePromptDismissed"
    }

    private static var defaults: UserDefaults { AppGroup.defaults }

    static var location: SavedLocation? {
        get { defaults.decoded(SavedLocation.self, forKey: Key.location) }
        set { defaults.setEncoded(newValue, forKey: Key.location) }
    }

    /// Manual unless the user chose "current location". Older installs didn't
    /// record which, so they start manual and are asked when they travel.
    static var locationMode: LocationMode {
        get { defaults.string(forKey: Key.locationMode).flatMap(LocationMode.init(rawValue:)) ?? .manual }
        set { defaults.set(newValue.rawValue, forKey: Key.locationMode) }
    }

    /// The device time zone the user said "keep my city" for, so the question
    /// isn't asked again until they travel somewhere else.
    static var timeZonePromptDismissed: String? {
        get { defaults.string(forKey: Key.timeZonePromptDismissed) }
        set { defaults.set(newValue, forKey: Key.timeZonePromptDismissed) }
    }

    static var prayerSettings: PrayerSettings {
        get { defaults.decoded(PrayerSettings.self, forKey: Key.prayerSettings) ?? PrayerSettings() }
        set { defaults.setEncoded(newValue, forKey: Key.prayerSettings) }
    }

    static var notificationSettings: NotificationSettings {
        get { defaults.decoded(NotificationSettings.self, forKey: Key.notificationSettings) ?? NotificationSettings() }
        set { defaults.setEncoded(newValue, forKey: Key.notificationSettings) }
    }

    static var athan: AthanSettings {
        get { defaults.decoded(AthanSettings.self, forKey: Key.athan) ?? AthanSettings() }
        set { defaults.setEncoded(newValue, forKey: Key.athan) }
    }

    static var quranReminders: QuranReminderSettings {
        get { defaults.decoded(QuranReminderSettings.self, forKey: Key.quranReminders) ?? QuranReminderSettings() }
        set { defaults.setEncoded(newValue, forKey: Key.quranReminders) }
    }

    /// Days to shift the Hijri date by, to match local moon sighting.
    static var hijriAdjustment: Int {
        get { defaults.integer(forKey: Key.hijriAdjustment) }
        set { defaults.set(newValue, forKey: Key.hijriAdjustment) }
    }
}
