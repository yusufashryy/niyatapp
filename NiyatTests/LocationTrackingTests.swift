import XCTest
@testable import Niyat

final class LocationTrackingTests: XCTestCase {
    private let london = SavedLocation(latitude: 51.5074, longitude: -0.1278, name: "London",
                                       timeZoneIdentifier: "Europe/London", countryCode: "GB")
    private let detroit = SavedLocation(latitude: 42.3314, longitude: -83.0458, name: "Detroit",
                                        timeZoneIdentifier: "America/Detroit", countryCode: "US")
    private let june = Date(timeIntervalSince1970: 1_780_000_000) // 2026-05-28

    func testSmallMoveDoesNotUpdate() {
        // About 5 km east, same clock.
        XCTAssertFalse(LocationTracking.shouldUpdate(saved: london, latitude: 51.5074, longitude: -0.055,
                                                     deviceTimeZone: london.timeZone, at: june))
    }

    func testMoveAcrossTownUpdates() {
        // Heathrow is about 23 km from central London.
        XCTAssertTrue(LocationTracking.shouldUpdate(saved: london, latitude: 51.4700, longitude: -0.4543,
                                                    deviceTimeZone: london.timeZone, at: june))
    }

    func testFlightToChicagoUpdates() throws {
        let chicago = try XCTUnwrap(TimeZone(identifier: "America/Chicago"))
        XCTAssertTrue(LocationTracking.shouldUpdate(saved: london, latitude: 41.8781, longitude: -87.6298,
                                                    deviceTimeZone: chicago, at: june))
    }

    func testDifferentTimeZoneNameWithSameClockIsNotAChange() throws {
        let newYork = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        XCTAssertFalse(LocationTracking.timeZoneDiffers(saved: detroit, device: newYork, at: june))
    }

    func testOtherClockIsAChange() throws {
        let chicago = try XCTUnwrap(TimeZone(identifier: "America/Chicago"))
        XCTAssertTrue(LocationTracking.timeZoneDiffers(saved: detroit, device: chicago, at: june))
    }

    func testCheckIsDueTheFirstTime() {
        XCTAssertTrue(LocationTracking.isCheckDue(lastCheck: nil, now: june, timeZoneChanged: false))
    }

    func testCheckWaitsBetweenOpens() {
        let fiveMinutesAgo = june.addingTimeInterval(-5 * 60)
        let anHourAgo = june.addingTimeInterval(-60 * 60)
        XCTAssertFalse(LocationTracking.isCheckDue(lastCheck: fiveMinutesAgo, now: june, timeZoneChanged: false))
        XCTAssertTrue(LocationTracking.isCheckDue(lastCheck: anHourAgo, now: june, timeZoneChanged: false))
    }

    func testTimeZoneChangeSkipsTheWait() {
        let aMinuteAgo = june.addingTimeInterval(-60)
        XCTAssertTrue(LocationTracking.isCheckDue(lastCheck: aMinuteAgo, now: june, timeZoneChanged: true))
    }

    func testFixedComponentsPointAtTheSameMoment() {
        let components = june.fixedDateComponents()
        XCTAssertNotNil(components.timeZone)
        XCTAssertEqual(components.date, june)
    }

    func testFixedComponentsSurviveAClockChange() throws {
        // Scheduled in London, read after landing in Chicago: still the same moment.
        var londonCalendar = Calendar(identifier: .gregorian)
        londonCalendar.timeZone = london.timeZone
        var chicagoCalendar = Calendar(identifier: .gregorian)
        chicagoCalendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Chicago"))
        XCTAssertEqual(chicagoCalendar.date(from: june.fixedDateComponents(in: londonCalendar)), june)
    }
}

final class SavedLocationNameTests: XCTestCase {
    func testShortNameDropsTheRegion() {
        let place = SavedLocation(latitude: 0, longitude: 0, name: "London, United Kingdom",
                                  timeZoneIdentifier: "Europe/London", countryCode: "GB")
        XCTAssertEqual(place.shortName, "London")
    }

    func testShortNameKeepsASingleName() {
        XCTAssertEqual(SavedLocation.makkah.shortName, "Makkah")
    }
}
