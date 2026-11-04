import CoreGraphics

/// How the mushaf behaves like a printed book: pages turned right to left,
/// two facing pages on a wide screen, hizb marks and the thickness of the
/// pages on each side.
enum MushafBook {
    /// Pages in the Madinah mushaf (as `MushafLayout.pageCount`, which is main-actor bound).
    static let pageCount = 604

    /// Where a page sits: on its own (bound on its right edge), or as the
    /// right or left of two facing pages.
    enum Placement {
        case single, right, left
    }

    /// Two facing pages: the odd page on the right, as in a printed mushaf.
    struct Spread: Equatable {
        let right: Int
        let left: Int?
    }

    /// The shortest a page may be in a spread; any smaller and one page reads better.
    static let minimumSpreadHeight: CGFloat = 480

    /// Whether two pages fit side by side at a readable size (iPad in
    /// landscape, iPhone Duo open). Each page keeps its printed shape, so it
    /// may shrink a little to make room, but not much.
    static func spreadFits(width: CGFloat, height: CGFloat) -> Bool {
        height >= minimumSpreadHeight && width >= 2 * height * MushafMetrics.pageShape * 0.9
    }

    static func spread(containing page: Int) -> Spread {
        let right = page.isMultiple(of: 2) ? page - 1 : page
        return Spread(right: right, left: right < pageCount ? right + 1 : nil)
    }

    static func page(after page: Int) -> Int? { page < pageCount ? page + 1 : nil }
    static func page(before page: Int) -> Int? { page > 1 ? page - 1 : nil }

    /// Page curl unless Reduce Motion is on: then pages slide.
    static func turn(chosen: MushafOptions.PageTurn, reduceMotion: Bool) -> MushafOptions.PageTurn {
        reduceMotion ? .slide : chosen
    }

    /// The mark for the n-th hizb quarter (1...240): "Hizb 3", "¼ Hizb 3", "½ Hizb 3"…
    static func hizbLabel(quarter: Int) -> String {
        let hizb = (quarter - 1) / 4 + 1
        let fraction = ["", "¼ ", "½ ", "¾ "][(quarter - 1) % 4]
        return "\(fraction)Hizb \(hizb)"
    }

    /// How much of the book lies on each side of a page, 0...1: pages already
    /// read (on the right in a mushaf) and those still to come (on the left).
    static func edges(page: Int) -> (read: CGFloat, unread: CGFloat) {
        let read = CGFloat(page - 1) / CGFloat(pageCount - 1)
        return (read, 1 - read)
    }
}
