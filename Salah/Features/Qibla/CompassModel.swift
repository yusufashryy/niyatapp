import CoreLocation
import Foundation
import Observation

/// Streams the phone's compass heading.
@MainActor
@Observable
final class CompassModel: NSObject, CLLocationManagerDelegate {
    /// Degrees clockwise from north, or nil if the device has no compass (e.g. the simulator).
    private(set) var heading: Double?
    private(set) var needsCalibration = false

    @ObservationIgnored private let manager = CLLocationManager()

    var isAvailable: Bool { CLLocationManager.headingAvailable() }

    override init() {
        super.init()
        manager.delegate = self
        manager.headingFilter = 1
    }

    func start() {
        guard CLLocationManager.headingAvailable() else { return }
        manager.startUpdatingHeading()
    }

    func stop() {
        manager.stopUpdatingHeading()
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // True heading needs location permission; fall back to magnetic north.
        let value = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        let accuracy = newHeading.headingAccuracy
        Task { @MainActor in
            self.heading = value
            self.needsCalibration = accuracy < 0 || accuracy > 25
        }
    }

    nonisolated func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        true
    }
}
