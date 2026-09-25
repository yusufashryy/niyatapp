import SwiftUI

extension Color {
    static let niyatiGreen = Color(red: 0.047, green: 0.353, blue: 0.294)
    static let niyatiDeepGreen = Color(red: 0.020, green: 0.184, blue: 0.157)
    static let niyatiGold = Color(red: 0.851, green: 0.690, blue: 0.345)
}

extension ShapeStyle where Self == LinearGradient {
    static var niyatiBackground: LinearGradient {
        LinearGradient(colors: [.niyatiGreen, .niyatiDeepGreen], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension Font {
    /// Amiri Quran (SIL Open Font License), bundled with the app and widgets.
    static func quran(size: CGFloat) -> Font { .custom("AmiriQuran-Regular", size: size) }
}

extension Date {
    var shortTime: String { formatted(date: .omitted, time: .shortened) }
}
