import UIKit

/// Qur'an data that's kept in memory to be quick the second time (split
/// words, laid-out mushaf pages, the finder's search). It only grows while
/// reading, so it's let go when iOS says memory is low, and rebuilt as needed.
@MainActor
enum QuranMemory {
    static func releaseCaches() {
        QuranWords.shared.removeAll()
        MushafPageText.removeAll()
        RecitationFinder.removeCachedSearch()
    }
}
