import Foundation

enum HijriDate {
    static func calendar() -> Calendar {
        Calendar(identifier: .islamicUmmAlQura)
    }

    /// e.g. "12 Rabiʻ I 1448 AH"
    static func string(for date: Date, adjustmentDays: Int = SettingsStore.hijriAdjustment,
                       locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("dMMMMyG")
        let shifted = Calendar.current.date(byAdding: .day, value: adjustmentDays, to: date) ?? date
        return formatter.string(from: shifted)
    }

    static func month(for date: Date, adjustmentDays: Int = SettingsStore.hijriAdjustment) -> Int {
        let shifted = Calendar.current.date(byAdding: .day, value: adjustmentDays, to: date) ?? date
        return calendar().component(.month, from: shifted)
    }

    static func isRamadan(_ date: Date) -> Bool { month(for: date) == 9 }
}
