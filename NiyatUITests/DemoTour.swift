import XCTest

/// Taps through the app like a person would, saving a screenshot of each screen.
/// CI records the simulator screen while this runs, which makes the demo video.
/// Tests run in alphabetical order, so test1 runs before test2.
final class DemoTour: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = true
        // Show London times in London time, whatever the Mac's clock is set to.
        app.launchEnvironment["TZ"] = "Europe/London"
    }

    func test1Onboarding() {
        app.launchArguments = ["-demoOnboarding"]
        app.launch()
        pause(2.5)
        snapshot("01 Welcome")
        app.buttons["Get started"].tap()
        pause(2)
        snapshot("02 Choose location")
    }

    func test2Tour() {
        app.launchArguments = ["-demo"]
        app.launch()
        pause(2.5)
        snapshot("03 Today")

        // Check in the earliest prayer through the full sheet (late, with a reason).
        let checkIn = app.buttons["Check in Fajr"]
        if checkIn.waitForExistence(timeout: 2), checkIn.isEnabled {
            checkIn.tap()
            pause(1.5)
            snapshot("04a Check-in")
            let late = app.staticTexts["Late"].firstMatch
            if late.exists {
                late.tap()
                pause()
                snapshot("04b Check-in - reason")
                app.staticTexts["Sleep"].firstMatch.tap()
                pause()
            }
        }
        // And the one-tap prompt for the next pending prayer.
        let onTime = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Prayed' AND label ENDSWITH 'on time'")).firstMatch
        if onTime.waitForExistence(timeout: 2) {
            onTime.tap()
            pause()
        }
        app.swipeUp()
        pause()
        snapshot("04 Today - times and streak")
        app.swipeDown()

        // Quran
        openTab("Quran")
        XCTAssertTrue(app.staticTexts["Al-Faatiha"].firstMatch.waitForExistence(timeout: 10))
        pause()
        snapshot("05 Quran - surahs")
        app.staticTexts["Al-Faatiha"].firstMatch.tap()
        pause(2)
        snapshot("06 Quran - Al-Fatiha")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        pause()

        // Qibla
        openTab("Qibla")
        pause(2)
        snapshot("08 Qibla")

        // Journey
        openTab("Journey")
        pause(2)
        snapshot("09 Journey")
        app.swipeUp()
        pause()
        snapshot("09b Journey - stats")
        app.swipeDown()

        // Tasbih
        openTab("More")
        pause()
        snapshot("10 More")
        app.staticTexts["Prayer Lock"].firstMatch.tap()
        pause(1.5)
        snapshot("10b Prayer Lock")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        pause()
        app.staticTexts["Tasbih"].firstMatch.tap()
        pause()
        let counter = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Count'")).firstMatch
        if counter.waitForExistence(timeout: 2) {
            for _ in 0..<12 {
                counter.tap()
                pause(0.25)
            }
        }
        pause()
        snapshot("11 Tasbih")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        pause()

        // Settings
        app.staticTexts["Settings"].firstMatch.tap()
        pause(1.5)
        snapshot("12 Settings")
        app.staticTexts["Theme"].firstMatch.tap()
        pause(1.5)
        snapshot("15 Theme")
        let desert = app.buttons["Desert theme"]
        if desert.waitForExistence(timeout: 2) {
            desert.tap()
            pause(1.5)
            snapshot("16 Theme - Desert")
        }
        app.navigationBars.buttons.element(boundBy: 0).tap()
        pause()
        app.swipeUp()
        pause()
        snapshot("13 Settings - notifications")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        pause()

        app.staticTexts["About & credits"].firstMatch.tap()
        pause(1.5)
        snapshot("14 About")
    }

    /// The Liquid Glass tab bar shrinks while scrolling; scroll back first if needed.
    private func openTab(_ name: String) {
        let button = app.tabBars.buttons[name]
        if !button.isHittable {
            app.swipeDown()
            pause(0.5)
        }
        button.tap()
    }

    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Slows the tour down so the recording is watchable.
    private func pause(_ seconds: TimeInterval = 1.2) {
        Thread.sleep(forTimeInterval: seconds)
    }
}
