import XCTest
@testable import Niyat

final class MushafBookTests: XCTestCase {

    // MARK: Two-page spreads

    func testPhoneInPortraitShowsOnePage() {
        XCTAssertFalse(MushafBook.spreadFits(width: 402, height: 760))
    }

    func testPhoneInLandscapeShowsOnePage() {
        // Wide, but each page would be tiny next to the other.
        XCTAssertFalse(MushafBook.spreadFits(width: 874, height: 330))
    }

    func testIPadInLandscapeShowsTwoPages() {
        XCTAssertTrue(MushafBook.spreadFits(width: 1194, height: 760))
    }

    func testIPadInPortraitShowsOnePage() {
        XCTAssertFalse(MushafBook.spreadFits(width: 834, height: 1100))
    }

    // iPhone Duo windows (Duology's measurements): open held wide 951 × 669 pt,
    // open held tall 669 × 951, closed 466 × 678. The pages get the window less
    // the status bar, the control bar and the mic button: measured on the
    // simulator, about 470 pt tall when open and held wide.

    func testDuoOpenHeldWideShowsTwoPages() {
        XCTAssertTrue(MushafBook.spreadFits(width: 951, height: 589))
        XCTAssertTrue(MushafBook.spreadFits(width: 891, height: 468))
    }

    func testDuoOpenHeldTallShowsOnePage() {
        XCTAssertFalse(MushafBook.spreadFits(width: 669, height: 871))
    }

    func testDuoClosedShowsOnePage() {
        XCTAssertFalse(MushafBook.spreadFits(width: 382, height: 562))
    }

    func testOddPageIsOnTheRight() {
        XCTAssertEqual(MushafBook.spread(containing: 1), MushafBook.Spread(right: 1, left: 2))
        XCTAssertEqual(MushafBook.spread(containing: 2), MushafBook.Spread(right: 1, left: 2))
        XCTAssertEqual(MushafBook.spread(containing: 245), MushafBook.Spread(right: 245, left: 246))
        XCTAssertEqual(MushafBook.spread(containing: 246), MushafBook.Spread(right: 245, left: 246))
    }

    func testLastPageHasNoFacingPagePastTheEnd() {
        // 604 is even, so it faces 603; nothing comes after it.
        XCTAssertEqual(MushafBook.spread(containing: 604), MushafBook.Spread(right: 603, left: 604))
        XCTAssertEqual(MushafBook.spread(containing: 603).left, 604)
    }

    // MARK: Turning pages

    func testCurlByDefault() {
        XCTAssertEqual(MushafBook.turn(chosen: .curl, reduceMotion: false), .curl)
    }

    func testReduceMotionSlides() {
        XCTAssertEqual(MushafBook.turn(chosen: .curl, reduceMotion: true), .slide)
    }

    func testSlideStaysSlide() {
        XCTAssertEqual(MushafBook.turn(chosen: .slide, reduceMotion: false), .slide)
    }

    func testNeighbouringPagesStopAtTheCovers() {
        XCTAssertEqual(MushafBook.page(after: 1), 2)
        XCTAssertNil(MushafBook.page(after: 604))
        XCTAssertEqual(MushafBook.page(before: 2), 1)
        XCTAssertNil(MushafBook.page(before: 1))
    }

    // MARK: Hizb marks

    func testHizbQuarters() {
        XCTAssertEqual(MushafBook.hizbLabel(quarter: 1), "Hizb 1")
        XCTAssertEqual(MushafBook.hizbLabel(quarter: 2), "¼ Hizb 1")
        XCTAssertEqual(MushafBook.hizbLabel(quarter: 3), "½ Hizb 1")
        XCTAssertEqual(MushafBook.hizbLabel(quarter: 4), "¾ Hizb 1")
        XCTAssertEqual(MushafBook.hizbLabel(quarter: 5), "Hizb 2")
        XCTAssertEqual(MushafBook.hizbLabel(quarter: 240), "¾ Hizb 60")
    }

    // MARK: Page edges

    func testEdgesAtTheStart() {
        let edges = MushafBook.edges(page: 1)
        XCTAssertEqual(edges.read, 0, accuracy: 0.001)
        XCTAssertEqual(edges.unread, 1, accuracy: 0.001)
    }

    func testEdgesHalfway() {
        let edges = MushafBook.edges(page: 302)
        XCTAssertEqual(edges.read, 0.5, accuracy: 0.01)
        XCTAssertEqual(edges.unread, 0.5, accuracy: 0.01)
    }

    func testEdgesAtTheEnd() {
        let edges = MushafBook.edges(page: 604)
        XCTAssertEqual(edges.read, 1, accuracy: 0.001)
        XCTAssertEqual(edges.unread, 0, accuracy: 0.001)
    }
}
