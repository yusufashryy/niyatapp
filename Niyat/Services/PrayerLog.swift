import Foundation

/// How a prayer went.
enum PrayerStatus: String, Codable, CaseIterable, Identifiable {
    case onTime, late, missed, excused

    var id: String { rawValue }

    var title: String {
        switch self {
        case .onTime: "On time"
        case .late: "Late"
        case .missed: "Missed"
        case .excused: "Excused"
        }
    }

    var symbolName: String {
        switch self {
        case .onTime: "checkmark.circle.fill"
        case .late: "clock.badge.checkmark.fill"
        case .missed: "xmark.circle.fill"
        case .excused: "minus.circle.fill"
        }
    }

    /// The prayer was performed (on time or late).
    var countsAsPrayed: Bool { self == .onTime || self == .late }

    /// Keeps a streak going. Excused covers menstruation, illness and the like.
    var keepsStreak: Bool { self != .missed }

    /// Late and missed prayers ask why, so the Journey tab can show patterns.
    var asksForReason: Bool { self == .late || self == .missed }
}

/// Why a prayer was late or missed.
enum MissReason: String, Codable, CaseIterable, Identifiable {
    case sleep, work, school, forgot, travel, busy, illness, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sleep: "Sleep"
        case .work: "Work"
        case .school: "School"
        case .forgot: "Forgot"
        case .travel: "Travel"
        case .busy: "Busy / lazy"
        case .illness: "Illness"
        case .other: "Other"
        }
    }

    var symbolName: String {
        switch self {
        case .sleep: "moon.zzz.fill"
        case .work: "briefcase.fill"
        case .school: "graduationcap.fill"
        case .forgot: "questionmark.circle.fill"
        case .travel: "airplane"
        case .busy: "hourglass"
        case .illness: "cross.case.fill"
        case .other: "ellipsis.circle.fill"
        }
    }
}

struct PrayerRecord: Codable, Equatable {
    var status: PrayerStatus
    var reason: MissReason?
}

/// The prayer journal, stored as ["2026-09-25|fajr": record] in the App Group.
enum PrayerLog {
    private static let storageKey = "prayerLog.v2"
    private static let legacyKey = "prayerLog"

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func key(_ prayer: PrayerName, on day: Date) -> String {
        "\(dayFormatter.string(from: day))|\(prayer.rawValue)"
    }

    static func load() -> [String: PrayerRecord] {
        let defaults = AppGroup.defaults
        if let records = defaults.decoded([String: PrayerRecord].self, forKey: storageKey) {
            return records
        }
        // Earlier versions only stored ticks; those were prayers done on time.
        let legacy = defaults.stringArray(forKey: legacyKey) ?? []
        let migrated = Dictionary(legacy.map { ($0, PrayerRecord(status: .onTime)) }, uniquingKeysWith: { a, _ in a })
        save(migrated)
        return migrated
    }

    static func save(_ records: [String: PrayerRecord]) {
        AppGroup.defaults.setEncoded(records, forKey: storageKey)
    }
}

/// Numbers for the Journey tab, worked out from the journal.
struct PrayerStats: Equatable {
    var logged = 0
    var onTime = 0
    var late = 0
    var missed = 0
    var excused = 0
    var missedOrLateByPrayer: [PrayerName: Int] = [:]
    var reasons: [MissReason: Int] = [:]

    var prayed: Int { onTime + late }
    var onTimeRate: Double { logged == excused ? 0 : Double(onTime) / Double(logged - excused) }

    /// The prayer most often late or missed, if any.
    var hardestPrayer: PrayerName? {
        missedOrLateByPrayer.filter { $0.value > 0 }.max { a, b in
            a.value == b.value ? a.key.rawValue > b.key.rawValue : a.value < b.value
        }?.key
    }

    var sortedReasons: [(reason: MissReason, count: Int)] {
        reasons.map { ($0.key, $0.value) }.sorted { $0.count == $1.count ? $0.reason.rawValue < $1.reason.rawValue : $0.count > $1.count }
    }

    init() {}

    init(records: [String: PrayerRecord], days: [Date]) {
        for day in days {
            for prayer in PrayerName.obligatory {
                guard let record = records[PrayerLog.key(prayer, on: day)] else { continue }
                logged += 1
                switch record.status {
                case .onTime: onTime += 1
                case .late: late += 1
                case .missed: missed += 1
                case .excused: excused += 1
                }
                if record.status.asksForReason {
                    missedOrLateByPrayer[prayer, default: 0] += 1
                    if let reason = record.reason { reasons[reason, default: 0] += 1 }
                }
            }
        }
    }
}
