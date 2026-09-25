import CoreLocation
import Foundation

enum LocationError: LocalizedError {
    case denied
    case unavailable

    var errorDescription: String? {
        switch self {
        case .denied: "Location access is off. You can turn it on in Settings, or search for your city instead."
        case .unavailable: "Couldn't find your location. Try again, or search for your city instead."
        }
    }
}

/// Wraps CLLocationManager in async/await.
@MainActor
final class LocationService: NSObject, CLLocationManagerDelegate {
    static let shared = LocationService()

    private let manager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?
    private var authorizationContinuation: CheckedContinuation<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    var isAuthorized: Bool {
        manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways
    }

    func currentLocation() async throws -> CLLocation {
        if manager.authorizationStatus == .notDetermined {
            await withCheckedContinuation { continuation in
                authorizationContinuation = continuation
                manager.requestWhenInUseAuthorization()
            }
        }
        guard isAuthorized else { throw LocationError.denied }
        locationContinuation?.resume(throwing: CancellationError())
        return try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation
            manager.requestLocation()
        }
    }

    /// Current location, named (e.g. "London") with its time zone.
    func currentSavedLocation() async throws -> SavedLocation {
        let location = try await currentLocation()
        return await Self.savedLocation(for: location)
    }

    static func savedLocation(for location: CLLocation) async -> SavedLocation {
        let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first
        return SavedLocation(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            name: placemark.map(displayName) ?? String(format: "%.2f°, %.2f°", location.coordinate.latitude,
                                                      location.coordinate.longitude),
            timeZoneIdentifier: placemark?.timeZone?.identifier ?? TimeZone.current.identifier,
            countryCode: placemark?.isoCountryCode
        )
    }

    /// Finds places matching a city name, e.g. "Cairo".
    static func search(_ query: String) async throws -> [SavedLocation] {
        let placemarks = try await CLGeocoder().geocodeAddressString(query)
        return placemarks.compactMap { placemark in
            guard let coordinate = placemark.location?.coordinate else { return nil }
            return SavedLocation(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                name: displayName(placemark),
                timeZoneIdentifier: placemark.timeZone?.identifier ?? TimeZone.current.identifier,
                countryCode: placemark.isoCountryCode
            )
        }
    }

    private static func displayName(_ placemark: CLPlacemark) -> String {
        let city = placemark.locality ?? placemark.subAdministrativeArea ?? placemark.administrativeArea ?? placemark.name
        return [city, placemark.country].compactMap { $0 }.joined(separator: ", ")
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.locationContinuation?.resume(returning: location)
            self.locationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.locationContinuation?.resume(throwing: LocationError.unavailable)
            self.locationContinuation = nil
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard self.manager.authorizationStatus != .notDetermined else { return }
            self.authorizationContinuation?.resume()
            self.authorizationContinuation = nil
        }
    }
}
