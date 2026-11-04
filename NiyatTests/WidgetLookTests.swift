import XCTest
@testable import Niyat

final class WidgetLookTests: XCTestCase {
    func testMinimalIsTheDefault() {
        XCTAssertEqual(WidgetLook.Style.default, .minimal)
    }

    func testMinimalAsksForNoBackground() {
        let look = WidgetLook(style: .minimal, isFullColor: true)
        XCTAssertFalse(look.showsArtwork)
        XCTAssertTrue(look.isTransparent)
        XCTAssertNil(look.colorScheme, "iOS fills it white or black, so text follows the phone")
    }

    func testThemeShowsTheArtworkInFullColour() {
        let look = WidgetLook(style: .theme, isFullColor: true)
        XCTAssertTrue(look.showsArtwork)
        XCTAssertFalse(look.isTransparent)
        XCTAssertEqual(look.colorScheme, .dark, "the theme's backgrounds are dark, so text stays light")
    }

    func testTintedAndClearLooksAreLeftToIOS() {
        // iOS removes the background and tints the content itself.
        for style in WidgetLook.Style.allCases {
            let look = WidgetLook(style: style, isFullColor: false)
            XCTAssertFalse(look.showsArtwork)
            XCTAssertTrue(look.isTransparent)
            XCTAssertNil(look.colorScheme)
        }
    }
}
