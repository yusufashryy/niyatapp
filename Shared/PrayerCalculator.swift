import Adhan
import Foundation

struct PrayerTime: Identifiable, Hashable {
    let name: PrayerName
    let date: Date

    var id: String { "\(name.rawValue)-\(Int(date.timeIntervalSince1970))" }
}

struct DaySchedule: Hashable {
    /// Midnight at the start of this day, in the location's time zone.
    let day: Date
    /// All six times in order: Fajr, Sunrise, Dhuhr, Asr, Maghrib, Isha.
    let times: [PrayerTime]

    func time(for name: PrayerName) -> PrayerTime? { times.first { $0.name == name } }
}

/// Prayer times are calculated on-device from the sun's position (via the Adhan
/// library), so they work offline and anywhere in the world.
enum PrayerCalculator {
    static func calendar(for location: SavedLocation) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = location.timeZone
        return calendar
    }

    static func schedule(for date: Date, location: SavedLocation, settings: PrayerSettings) -> DaySchedule? {
        let calendar = calendar(for: location)
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let times = PrayerTimes(coordinates: location.coordinates, date: components,
                                      calculationParameters: settings.parameters) else { return nil }
        return DaySchedule(
            day: calendar.startOfDay(for: date),
            times: PrayerName.allCases.map { PrayerTime(name: $0, date: times.time(for: $0.adhanPrayer)) }
        )
    }

    /// The next `count` prayer times strictly after `date`, crossing into following days as needed.
    static func upcoming(after date: Date, count: Int, includeSunrise: Bool = false,
                         location: SavedLocation, settings: PrayerSettings) -> [PrayerTime] {
        let calendar = calendar(for: location)
        var result: [PrayerTime] = []
        // Start from yesterday so a window that began before midnight is never missed.
        var dayOffset = -1
        while result.count < count, dayOffset < 60 {
            if let day = calendar.date(byAdding: .day, value: dayOffset, to: date),
               let schedule = schedule(for: day, location: location, settings: settings) {
                for time in schedule.times where time.date > date && (includeSunrise || time.name.isObligatory) {
                    result.append(time)
                    if result.count == count { break }
                }
            }
            dayOffset += 1
        }
        return result
    }

    static func next(after date: Date, location: SavedLocation, settings: PrayerSettings) -> PrayerTime? {
        upcoming(after: date, count: 1, location: location, settings: settings).first
    }

    /// The most recent time (including sunrise) at or before `date`. If it's sunrise,
    /// Fajr time has ended and Dhuhr hasn't started.
    static func current(at date: Date, location: SavedLocation, settings: PrayerSettings) -> PrayerTime? {
        let calendar = calendar(for: location)
        for offset in [0, -1] {
            guard let day = calendar.date(byAdding: .day, value: offset, to: date),
                  let schedule = schedule(for: day, location: location, settings: settings) else { continue }
            if let time = schedule.times.last(where: { $0.date <= date }) { return time }
        }
        return nil
    }

    /// Compass bearing to the Kaaba, in degrees clockwise from true north.
    static func qiblaDirection(from location: SavedLocation) -> Double {
        Qibla(coordinates: location.coordinates).direction
    }
}
