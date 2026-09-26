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

        var isQuran: Bool { true }
    }

    var pending: Destination?

    private init() {}
}
