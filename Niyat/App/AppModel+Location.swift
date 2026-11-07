import CoreLocation
import Foundation
import os

/// Keeps prayer times following the user when they travel.
extension AppModel {
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Niyat", category: "Location")

    /// Automatic mode: called whenever the app opens. Fetches a fresh location
    /// (never asks for permission here) and moves prayer times if the user has
    /// gone more than 10 km or the clock is on another time zone.
    func followCurrentLocation(now: Date = .now) async {
        guard locationMode == .automatic, let saved = location, !isCheckingLocation,
              LocationService.shared.isAuthorized else { return }
        let deviceTimeZone = TimeZone.current
        let timeZoneChanged = lastCheckedTimeZone.map { $0.identifier != deviceTimeZone.identifier } ?? false
        guard LocationTracking.isCheckDue(lastCheck: lastLocationCheck, now: now,
                                          timeZoneChanged: timeZoneChanged) else { return }
        isCheckingLocation = true
        defer { isCheckingLocation = false }
        lastLocationCheck = now
        lastCheckedTimeZone = deviceTimeZone

        let fix: CLLocation
        do {
            fix = try await LocationService.shared.currentLocation()
        } catch {
            // Indoors, airplane mode and so on: keep the saved place and try next time.
            Self.log.notice("Couldn't refresh location: \(error.localizedDescription, privacy: .public)")
            lastLocationCheck = nil
            return
        }
        guard LocationTracking.shouldUpdate(saved: saved, latitude: fix.coordinate.latitude,
                                            longitude: fix.coordinate.longitude,
                                            deviceTimeZone: deviceTimeZone, at: now) else { return }
        let fresh = await LocationService.savedLocation(for: fix)
        // Clock changed by hand but still in the same place: nothing to move.
        let moved = LocationTracking.distance(from: saved, toLatitude: fresh.latitude, longitude: fresh.longitude)
            > LocationTracking.minimumDistance
        guard moved || LocationTracking.timeZoneDiffers(saved: saved, device: fresh.timeZone, at: now) else { return }
        // The user may have picked another place while we were waiting.
        guard location == saved, locationMode == .automatic else { return }
        setLocation(fresh)
        recentLocationChange = LocationChange(previous: saved, current: fresh)
    }

    /// "Undo" on the banner: back to the old place, and stop following the
    /// device so the next open doesn't move it straight back.
    func undoLocationChange() {
        guard let change = recentLocationChange else { return }
        setLocation(change.previous, mode: .manual)
        dismissTimeZonePrompt()
    }

    /// Manual mode: the device's clock is on another time zone than the saved
    /// city and the user hasn't said to keep it.
    func shouldOfferTimeZoneUpdate(now: Date = .now) -> Bool {
        guard locationMode == .manual, let location else { return false }
        let device = TimeZone.current
        return timeZonePromptDismissed != device.identifier
            && LocationTracking.timeZoneDiffers(saved: location, device: device, at: now)
    }

    /// "Keep London": don't ask again while the device stays on this time zone.
    func dismissTimeZonePrompt() {
        timeZonePromptDismissed = TimeZone.current.identifier
        SettingsStore.timeZonePromptDismissed = timeZonePromptDismissed
    }

    /// The Settings switch. Turning it on checks straight away.
    func setFollowsDevice(_ follows: Bool) async throws {
        guard follows else {
            locationMode = .manual
            SettingsStore.locationMode = .manual
            return
        }
        // May show the system permission prompt; throws if it's refused.
        let current = try await LocationService.shared.currentSavedLocation()
        setLocation(current, mode: .automatic)
        lastLocationCheck = .now
        lastCheckedTimeZone = .current
    }
}
