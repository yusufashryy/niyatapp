import CoreGraphics
import Foundation

/// Line spacing for Qur'an text in the verse-by-verse reader, as line height
/// ÷ text size. Amiri Quran's own line is 2.45× (room for stacked marks);
/// printed mushafs are close to 1.6×. The default leaves a little more, so
/// stacked marks never touch the line above. (Mushaf pages always have the 15
/// lines of the printed page.)
enum QuranLineSpacing {
    static let key = "quran.lineHeight"
    static let standard = 1.85
    static let range = 1.5...2.5
}

/// How thick the Arabic is drawn, for readers who find the thin strokes hard
/// to see. Shared by the verse cards and the mushaf.
enum QuranTextWeight: Int, CaseIterable, Identifiable {
    case regular, bold, heavy

    static let key = "quran.textWeight"

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .regular: "Normal"
        case .bold: "Bold"
        case .heavy: "Heavy"
        }
    }

    /// Outline width as a percentage of the text size.
    var stroke: CGFloat {
        switch self {
        case .regular: 0
        case .bold: 2.5
        case .heavy: 5
        }
    }
}
