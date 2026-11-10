import Foundation
import Observation

/// Somewhere the app should jump to, e.g. after tapping a notification or widget.
@MainActor
@Observable
final class DeepLink {
    static let shared = DeepLink()

    enum Destination: Equatable {
        /// Open the Qur'an at the last reading position.
        case quranContinueReading
        /// Open the Qur'an at a specific (Hafs) verse, e.g. verse of the day.
        case quranVerse(surah: Int, verse: Int)
        /// Open one hadith in the Hadith tab (the daily hadith notification).
        case hadith(id: Int)

        var isQuran: Bool {
            if case .hadith = self { return false }
            return true
        }
    }

    var pending: Destination?

    private init() {}
}
