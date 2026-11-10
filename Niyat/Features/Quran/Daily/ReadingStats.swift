import Foundation

/// Today / This week / All time, as the Done sheet shows them.
enum ReadingPeriod: String, CaseIterable, Identifiable {
    case today, week, all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .week: "Week"
        case .all: "All"
        }
    }

    /// Days covered, including today; nil for all time.
    var days: Int? {
        switch self {
        case .today: 1
        case .week: 7
        case .all: nil
        }
    }
}

/// Rules for the reading stats. Pure, so they're tested.
enum ReadingStats {
    /// Mushaf pages whose every ayah has been read. `pages` lists each page's
    /// ayat as "surah:verse" (Hafs numbering), in page order.
    static func pagesCompleted(read: Set<String>, pages: [[String]]) -> Int {
        guard !read.isEmpty else { return 0 }
        return pages.count { !$0.isEmpty && $0.allSatisfy(read.contains) }
    }

    /// "35s", "12m", "1h 05m".
    static func duration(_ seconds: Int) -> String {
        let seconds = max(seconds, 0)
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h \(String(format: "%02d", minutes % 60))m"
    }

    /// "980", "1.1K", "2.4M": short enough for a tile.
    static func compact(_ value: Int) -> String {
        value.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
    }

    /// Longest stretch counted as reading at once, so a phone left open on
    /// the table doesn't add hours.
    static let longestSitting = 30 * 60
}
