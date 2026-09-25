import Foundation

/// An independent Qibla calculation, used to double-check the Adhan library in
/// the unit tests, and to measure the distance to the Kaaba.
enum QiblaMath {
    /// The Kaaba, Masjid al-Haram, Makkah.
    static let kaabaLatitude = 21.4225
    static let kaabaLongitude = 39.8262

    /// Initial great-circle bearing from a point to the Kaaba, in degrees clockwise
    /// from true north (0..<360). This is the standard way the Qibla is calculated.
    static func bearing(latitude: Double, longitude: Double) -> Double {
        let phi1 = latitude * .pi / 180
        let phi2 = kaabaLatitude * .pi / 180
        let deltaLambda = (kaabaLongitude - longitude) * .pi / 180
        let x = sin(deltaLambda)
        let y = cos(phi1) * tan(phi2) - sin(phi1) * cos(deltaLambda)
        let degrees = atan2(x, y) * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Great-circle distance to the Kaaba in metres (haversine, mean Earth radius).
    static func distance(latitude: Double, longitude: Double) -> Double {
        let r = 6_371_008.8
        let phi1 = latitude * .pi / 180, phi2 = kaabaLatitude * .pi / 180
        let dPhi = phi2 - phi1
        let dLambda = (kaabaLongitude - longitude) * .pi / 180
        let a = sin(dPhi / 2) * sin(dPhi / 2) + cos(phi1) * cos(phi2) * sin(dLambda / 2) * sin(dLambda / 2)
        return 2 * r * atan2(sqrt(a), sqrt(1 - a))
    }
}
