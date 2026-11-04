import CoreLocation
import Foundation

/// How the saved location keeps up with the user.
enum LocationMode: String, Codable {
    /// Follows the device: re-checked each time the app opens.
    case automatic
    /// A city the user picked. Niyat only asks when the clock's time zone changes.
    case manual
}

/// A location change Niyat made by itself, kept so it can be undone.
struct LocationChange: Equatable {
    let previous: SavedLocation
    let current: SavedLocation
}

/// Decides when travelling should move prayer times to a new place.
enum LocationTracking {
    /// Moving less than this barely shifts prayer times (about a minute per 15 km).
    static let minimumDistance: CLLocationDistance = 10_000
    /// How often opening the app asks for a fresh location.
    static let minimumCheckInterval: TimeInterval = 15 * 60

    static func distance(from saved: SavedLocation, toLatitude latitude: Double, longitude: Double) -> CLLocationDistance {
        CLLocation(latitude: saved.latitude, longitude: saved.longitude)
            .distance(from: CLLocation(latitude: latitude, longitude: longitude))
    }

    /// True when the device is far enough from the saved place, or on another
    /// time zone's clock, that prayer times should follow it.
    static func shouldUpdate(saved: SavedLocation, latitude: Double, longitude: Double,
                             deviceTimeZone: TimeZone, at date: Date) -> Bool {
        distance(from: saved, toLatitude: latitude, longitude: longitude) > minimumDistance
            || timeZoneDiffers(saved: saved, device: deviceTimeZone, at: date)
    }

    /// Compares UTC offsets rather than names: "America/Detroit" and
    /// "America/New_York" show the same clock and shouldn't count as a change.
    static func timeZoneDiffers(saved: SavedLocation, device: TimeZone, at date: Date) -> Bool {
        saved.timeZone.secondsFromGMT(for: date) != device.secondsFromGMT(for: date)
    }

    /// Whether to fetch a fresh location now.
    static func isCheckDue(lastCheck: Date?, now: Date, timeZoneChanged: Bool) -> Bool {
        guard let lastCheck, !timeZoneChanged else { return true }
        return now.timeIntervalSince(lastCheck) >= minimumCheckInterval
    }
}

extension Date {
    /// This moment as calendar components pinned to the current time zone, for
    /// notification and Screen Time triggers. Without the time zone, iOS reads
    /// "13:05" as 13:05 on whatever clock the device shows later, so after a
    /// flight an alert would fire at the old city's clock time.
    func fixedDateComponents(in calendar: Calendar = .current) -> DateComponents {
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: self)
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        return components
    }
}
