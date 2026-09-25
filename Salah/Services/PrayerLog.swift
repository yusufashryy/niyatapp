import Foundation

/// Which prayers the user has ticked off, stored as "yyyy-MM-dd|fajr" strings.
enum PrayerLog {
    private static let storageKey = "prayerLog"

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func key(_ prayer: PrayerName, on day: Date) -> String {
        "\(dayFormatter.string(from: day))|\(prayer.rawValue)"
    }

    static func load() -> Set<String> {
        Set(AppGroup.defaults.stringArray(forKey: storageKey) ?? [])
    }

    static func save(_ log: Set<String>) {
        AppGroup.defaults.set(Array(log), forKey: storageKey)
    }
}
