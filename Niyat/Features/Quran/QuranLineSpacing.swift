import Foundation

/// Line spacing for Qur'an text in the verse-by-verse reader, as line height
/// ÷ text size. Amiri Quran's own line is 2.45× (room for stacked marks);
/// printed mushafs are close to 1.6×, the default. (Mushaf pages always have
/// the 15 lines of the printed page.)
enum QuranLineSpacing {
    static let key = "quran.lineHeight"
    static let standard = 1.6
    static let range = 1.5...2.5
}
