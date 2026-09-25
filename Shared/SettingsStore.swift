import Foundation

/// Reads and writes settings in the App Group so widgets and extensions see them too.
enum SettingsStore {
    private enum Key {
        static let location = "location"
        static let prayerSettings = "prayerSettings"
        static let notificationSettings = "notificationSettings"
        static let hijriAdjustment = "hijriAdjustment"
    }

    private static var defaults: UserDefaults { AppGroup.defaults }

    static var location: SavedLocation? {
        get { defaults.decoded(SavedLocation.self, forKey: Key.location) }
        set { defaults.setEncoded(newValue, forKey: Key.location) }
    }

    static var prayerSettings: PrayerSettings {
        get { defaults.decoded(PrayerSettings.self, forKey: Key.prayerSettings) ?? PrayerSettings() }
        set { defaults.setEncoded(newValue, forKey: Key.prayerSettings) }
    }

    static var notificationSettings: NotificationSettings {
        get { defaults.decoded(NotificationSettings.self, forKey: Key.notificationSettings) ?? NotificationSettings() }
        set { defaults.setEncoded(newValue, forKey: Key.notificationSettings) }
    }

    /// Days to shift the Hijri date by, to match local moon sighting.
    static var hijriAdjustment: Int {
        get { defaults.integer(forKey: Key.hijriAdjustment) }
        set { defaults.set(newValue, forKey: Key.hijriAdjustment) }
    }
}
