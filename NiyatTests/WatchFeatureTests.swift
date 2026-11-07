import XCTest
@testable import Niyat

final class WatchFeatureTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_780_000_000)

    private func time(_ prayer: PrayerName, minutes: Double) -> PrayerTime {
        PrayerTime(name: prayer, date: start.addingTimeInterval(minutes * 60))
    }

    private func plan(_ times: [PrayerTime], settings: NotificationSettings = NotificationSettings(),
                      logged: Set<String> = [], limit: Int = 60) -> [PrayerAlertPlan.Alert] {
        PrayerAlertPlan.alerts(for: times, settings: settings, dayKey: { _ in "2026-05-28" },
                               logged: logged, now: start, limit: limit)
    }

    // MARK: Alert plan (shared by the iPhone and the watch, so their alerts match)

    func testEachPrayerGetsTheChosenAlertTimes() {
        let alerts = plan([time(.dhuhr, minutes: 60)])
        XCTAssertEqual(alerts.map(\.timing), [.before10, .atTime, .after30])
    }

    func testIdentifiersMatchBetweenPhoneAndWatch() {
        let alert = plan([time(.asr, minutes: 60)]).first { $0.timing == .atTime }
        XCTAssertEqual(alert?.id, "prayer.2026-05-28.asr.atTime")
    }

    func testSunriseOnlyAtItsTime() {
        var settings = NotificationSettings()
        settings.enabledPrayers.insert(.sunrise)
        XCTAssertEqual(plan([time(.sunrise, minutes: 60)], settings: settings).map(\.timing), [.atTime])
    }

    func testPrayersTurnedOffGetNoAlerts() {
        var settings = NotificationSettings()
        settings.enabledPrayers.remove(.maghrib)
        XCTAssertTrue(plan([time(.maghrib, minutes: 60)], settings: settings).isEmpty)
    }

    func testNoFollowUpOnceLogged() {
        let alerts = plan([time(.isha, minutes: 60)], logged: ["2026-05-28|isha"])
        XCTAssertFalse(alerts.contains { $0.timing == .after30 })
    }

    func testPastAlertsAreSkipped() {
        // Dhuhr began 20 minutes ago: only the 30-minute follow-up is still ahead.
        XCTAssertEqual(plan([time(.dhuhr, minutes: -20)]).map(\.timing), [.after30])
    }

    func testSoonestFirstWithinTheLimit() {
        let alerts = plan([time(.asr, minutes: 300), time(.dhuhr, minutes: 60)], limit: 2)
        XCTAssertEqual(alerts.map(\.prayer), [.dhuhr, .dhuhr])
        XCTAssertEqual(alerts.map(\.timing), [.before10, .atTime])
    }

    // MARK: Tasbih on the Digital Crown

    func testEachWholeTurnStepCounts() {
        XCTAssertEqual(CrownTasbih.counts(from: 0, to: 2.4), 2)
        XCTAssertEqual(CrownTasbih.counts(from: 2.4, to: 3.1), 1)
    }

    func testSmallTurnsDoNotCount() {
        XCTAssertEqual(CrownTasbih.counts(from: 0.1, to: 0.8), 0)
    }

    func testTurningBackDoesNotCount() {
        XCTAssertEqual(CrownTasbih.counts(from: 5, to: 2), 0)
    }

    // MARK: Qibla

    func testNeedlePointsToTheQiblaRelativeToTheWatch() {
        // Qibla at 119°, watch facing 90° (east): the needle points 29° right.
        XCTAssertEqual(QiblaMath.needle(bearing: 119, heading: 90), 29, accuracy: 0.001)
        XCTAssertEqual(QiblaMath.needle(bearing: 10, heading: 350), 20, accuracy: 0.001)
    }

    func testFacingTheQibla() {
        XCTAssertTrue(QiblaMath.isFacing(bearing: 119, heading: 116))
        XCTAssertTrue(QiblaMath.isFacing(bearing: 2, heading: 358))
        XCTAssertFalse(QiblaMath.isFacing(bearing: 119, heading: 100))
    }
}
