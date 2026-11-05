import XCTest
@testable import Niyat

final class SurahFrameTests: XCTestCase {
    private let size = CGSize(width: 360, height: 44)

    func testCartoucheIsCentredInsideTheField() {
        let g = SurahFrameGeometry(size: size)
        XCTAssertTrue(g.field.contains(g.cartouche.insetBy(dx: -g.tip, dy: 0)))
        XCTAssertEqual(g.cartouche.midX, g.bounds.midX, accuracy: 0.001)
        XCTAssertEqual(g.cartouche.midY, g.bounds.midY, accuracy: 0.001)
    }

    func testNameBoxIsCentredInTheCartouche() {
        let g = SurahFrameGeometry(size: size)
        XCTAssertTrue(g.cartouche.contains(g.nameBox))
        XCTAssertEqual(g.nameBox.midX, g.cartouche.midX, accuracy: 0.001)
        XCTAssertEqual(g.nameBox.midY, g.cartouche.midY, accuracy: 0.001)
    }

    func testMedallionsMirrorAndClearTheCartoucheAndEdges() {
        let g = SurahFrameGeometry(size: size)
        let r = g.medallionRadius
        XCTAssertGreaterThan(r, 6)
        let (right, left) = (g.medallions[0], g.medallions[1])
        XCTAssertGreaterThan(right.x, left.x, "the right medallion comes first, in reading order")
        XCTAssertEqual(right.x - g.bounds.midX, g.bounds.midX - left.x, accuracy: 0.001)
        // Clear of the cartouche's point and inside the field, with room for its lugs.
        XCTAssertGreaterThan(right.x - r * 1.45, g.cartouche.maxX + g.tip)
        XCTAssertLessThan(right.x + r * 1.45, g.field.maxX)
    }

    func testNarrowHeadingsShrinkTheMedallions() {
        let narrow = SurahFrameGeometry(size: CGSize(width: 200, height: 44))
        let wide = SurahFrameGeometry(size: size)
        XCTAssertLessThan(narrow.medallionRadius, wide.medallionRadius)
        XCTAssertLessThan(narrow.medallions[0].x + narrow.medallionRadius, narrow.field.maxX)
    }

    func testScallopedCircleStaysNearItsRadius() {
        let bounds = SurahFrameArt.scallopedCircle(centre: CGPoint(x: 50, y: 50), radius: 20, lobes: 18).boundingRect
        XCTAssertEqual(bounds.midX, 50, accuracy: 0.5)
        XCTAssertEqual(bounds.width, 40, accuracy: 4)
    }

    /// The bug this replaced: the name sat high because it was centred on its
    /// line box. Centring on the ink puts the ink's middle on the box's middle.
    func testCentredOriginPutsTheInkInTheMiddle() {
        let box = CGRect(x: 40, y: 10, width: 200, height: 30)
        // Ink drawn mostly above the baseline, like Arabic with marks: y up from the baseline.
        let ink = CGRect(x: -2, y: -4, width: 120, height: 26)
        let origin = SurahFrameGeometry.centredOrigin(ink: ink, in: box)
        // In y-down coordinates the ink spans origin.y - ink.maxY ... origin.y - ink.minY.
        XCTAssertEqual(((origin.y - ink.maxY) + (origin.y - ink.minY)) / 2, box.midY, accuracy: 0.001)
        XCTAssertEqual(origin.x + ink.midX, box.midX, accuracy: 0.001)
    }

    func testFittingSizeShrinksOnlyWhenNeeded() {
        let box = CGRect(x: 0, y: 0, width: 100, height: 30)
        XCTAssertEqual(SurahFrameGeometry.fittingSize(20, ink: CGRect(x: 0, y: 0, width: 80, height: 20), in: box), 20)
        XCTAssertEqual(SurahFrameGeometry.fittingSize(20, ink: CGRect(x: 0, y: 0, width: 200, height: 20), in: box), 10, accuracy: 0.001)
        XCTAssertEqual(SurahFrameGeometry.fittingSize(20, ink: .zero, in: box), 20)
    }
}

final class SurahTitlesTests: XCTestCase {
    func testEverySurahHasAVocalisedTitle() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "surah-titles", withExtension: "json")
            ?? Bundle.main.url(forResource: "surah-titles", withExtension: "json"))
        let titles = try JSONDecoder().decode([String].self, from: Data(contentsOf: url))
        XCTAssertEqual(titles.count, 114)
        XCTAssertTrue(titles.allSatisfy { $0.hasPrefix("سُورَةُ ") })
        XCTAssertEqual(titles[113], "سُورَةُ النَّاسِ")
    }
}
