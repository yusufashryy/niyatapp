import Foundation

/// Which prayer alerts to schedule, and when. The iPhone and the Apple Watch
/// both use this, so the same alert has the same identifier on each, and iOS
/// shows it once on the wrist rather than twice.
enum PrayerAlertPlan {
    struct Alert: Equatable {
        let id: String
        /// When the alert goes off (the prayer time, or before or after it).
        let date: Date
        let time: PrayerTime
        var prayer: PrayerName { time.name }
        let timing: AlertTiming
        let dayKey: String
    }

    static func identifier(prayer: PrayerName, dayKey: String, timing: AlertTiming) -> String {
        "prayer.\(dayKey).\(prayer.rawValue).\(timing.rawValue)"
    }

    /// The alerts for `times`, soonest first and at most `limit`:
    /// - each enabled prayer gets the chosen alert times; sunrise only its own time;
    /// - no "have you prayed?" follow-up for a prayer already logged
    ///   (`logged` holds `PrayerLog` keys, "dayKey|prayer");
    /// - nothing already past.
    static func alerts(for times: [PrayerTime], settings: NotificationSettings, dayKey: (Date) -> String,
                       logged: Set<String>, now: Date, limit: Int) -> [Alert] {
        var result: [Alert] = []
        for time in times where settings.enabledPrayers.contains(time.name) {
            let day = dayKey(time.date)
            let timings: [AlertTiming] = time.name.isObligatory ? settings.timings.sorted() : [.atTime]
            for timing in timings {
                if timing == .after30, logged.contains("\(day)|\(time.name.rawValue)") { continue }
                let date = time.date.addingTimeInterval(TimeInterval(timing.minutes * 60))
                guard date > now else { continue }
                result.append(Alert(id: identifier(prayer: time.name, dayKey: day, timing: timing),
                                    date: date, time: time, timing: timing, dayKey: day))
            }
        }
        return Array(result.sorted { $0.date < $1.date }.prefix(limit))
    }
}

/// Counting dhikr with the Digital Crown: one count for each whole step the
/// crown is turned forward.
enum CrownTasbih {
    /// Counts added when the crown's value moves from `old` to `new`.
    static func counts(from old: Double, to new: Double) -> Int {
        max(0, Int(new.rounded(.down)) - Int(old.rounded(.down)))
    }
}

extension QiblaMath {
    /// Where the Qibla is relative to the way the device faces, in degrees
    /// clockwise (0..<360). `heading` is the device's compass heading.
    static func needle(bearing: Double, heading: Double) -> Double {
        ((bearing - heading).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Facing the Qibla to within a few degrees.
    static func isFacing(bearing: Double, heading: Double, within tolerance: Double = 5) -> Bool {
        let offset = needle(bearing: bearing, heading: heading)
        return offset <= tolerance || offset >= 360 - tolerance
    }
}
