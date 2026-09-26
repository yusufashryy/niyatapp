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
    }

    var pending: Destination?

    private init() {}
}
