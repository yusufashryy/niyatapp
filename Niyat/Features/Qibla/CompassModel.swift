import CoreLocation
import Foundation
import Observation

/// Streams the phone's compass heading, smoothed and "unwrapped" so rotations
/// never spin the long way round when passing north (359° → 1°).
@MainActor
@Observable
final class CompassModel: NSObject, CLLocationManagerDelegate {
    /// Continuous heading in degrees (can go past 360 or below 0). Use for rotations.
    private(set) var continuousHeading: Double?
    /// Heading in 0..<360, clockwise from north. Use for maths and text.
    var heading: Double? { continuousHeading.map(Self.normalized) }
    /// Estimated error in degrees, or nil if unknown.
    private(set) var accuracy: Double?
    /// True when the heading is relative to true (geographic) north. Qibla bearings
    /// are true bearings, so magnetic north would be off by the local declination.
    private(set) var usesTrueNorth = false
    /// Where the phone is now, if location is allowed.
    private(set) var liveLocation: CLLocation?

    @ObservationIgnored private let manager = CLLocationManager()

    var isAvailable: Bool { CLLocationManager.headingAvailable() }
    var needsCalibration: Bool { accuracy.map { $0 < 0 || $0 > 20 } ?? false }

    override init() {
        super.init()
        manager.delegate = self
        manager.headingFilter = 0.5
        manager.headingOrientation = .portrait
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func start() {
        // Location updates are what make trueHeading available.
        let status = manager.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.startUpdatingLocation()
        } else if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        if CLLocationManager.headingAvailable() {
            manager.startUpdatingHeading()
        }
    }

    func stop() {
        manager.stopUpdatingHeading()
        manager.stopUpdatingLocation()
    }

    // MARK: Maths (static so it can be unit tested)

    nonisolated static func normalized(_ angle: Double) -> Double {
        let value = angle.truncatingRemainder(dividingBy: 360)
        return value < 0 ? value + 360 : value
    }

    /// Shortest signed turn from `from` to `to`, in -180..<180.
    nonisolated static func signedDelta(from: Double, to: Double) -> Double {
        var delta = normalized(to) - normalized(from)
        if delta >= 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        return delta
    }

    /// Moves a continuous angle part of the way towards a new reading, taking the
    /// short way round. Smoothing removes jitter without feeling laggy.
    nonisolated static func smoothed(previous: Double?, reading: Double, factor: Double = 0.3) -> Double {
        guard let previous else { return reading }
        let delta = signedDelta(from: previous, to: reading)
        // Big jumps (e.g. after calibration) snap instead of easing slowly.
        let step = abs(delta) > 60 ? delta : delta * factor
        return previous + step
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let trueHeading = newHeading.trueHeading
        let reading = trueHeading >= 0 ? trueHeading : newHeading.magneticHeading
        let accuracy = newHeading.headingAccuracy
        Task { @MainActor in
            self.usesTrueNorth = trueHeading >= 0
            self.accuracy = accuracy
            self.continuousHeading = Self.smoothed(previous: self.continuousHeading, reading: reading)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in self.liveLocation = location }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            let status = self.manager.authorizationStatus
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                self.manager.startUpdatingLocation()
            }
        }
    }

    nonisolated func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        true
    }
}
