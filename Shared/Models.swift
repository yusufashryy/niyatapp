import Adhan
import Foundation

/// The five daily prayers, plus sunrise (the end of Fajr time).
enum PrayerName: String, Codable, CaseIterable, Identifiable, Hashable {
    case fajr, sunrise, dhuhr, asr, maghrib, isha

    var id: String { rawValue }

    static let obligatory: [PrayerName] = [.fajr, .dhuhr, .asr, .maghrib, .isha]

    var isObligatory: Bool { self != .sunrise }

    var englishName: String {
        switch self {
        case .fajr: "Fajr"
        case .sunrise: "Sunrise"
        case .dhuhr: "Dhuhr"
        case .asr: "Asr"
        case .maghrib: "Maghrib"
        case .isha: "Isha"
        }
    }

    var arabicName: String {
        switch self {
        case .fajr: "الفجر"
        case .sunrise: "الشروق"
        case .dhuhr: "الظهر"
        case .asr: "العصر"
        case .maghrib: "المغرب"
        case .isha: "العشاء"
        }
    }

    var symbolName: String {
        switch self {
        case .fajr: "sun.haze.fill"
        case .sunrise: "sunrise.fill"
        case .dhuhr: "sun.max.fill"
        case .asr: "sun.min.fill"
        case .maghrib: "sunset.fill"
        case .isha: "moon.stars.fill"
        }
    }

    /// "Jumu'ah" instead of "Dhuhr" on Fridays.
    func displayName(on date: Date, calendar: Calendar = .current) -> String {
        if self == .dhuhr, calendar.component(.weekday, from: date) == 6 { return "Jumu'ah" }
        return englishName
    }

    init(_ prayer: Prayer) {
        switch prayer {
        case .fajr: self = .fajr
        case .sunrise: self = .sunrise
        case .dhuhr: self = .dhuhr
        case .asr: self = .asr
        case .maghrib: self = .maghrib
        case .isha: self = .isha
        }
    }

    var adhanPrayer: Prayer {
        switch self {
        case .fajr: .fajr
        case .sunrise: .sunrise
        case .dhuhr: .dhuhr
        case .asr: .asr
        case .maghrib: .maghrib
        case .isha: .isha
        }
    }
}

struct SavedLocation: Codable, Equatable, Hashable {
    var latitude: Double
    var longitude: Double
    var name: String
    var timeZoneIdentifier: String
    var countryCode: String?

    var coordinates: Coordinates { Coordinates(latitude: latitude, longitude: longitude) }
    var timeZone: TimeZone { TimeZone(identifier: timeZoneIdentifier) ?? .current }

    static let makkah = SavedLocation(latitude: 21.4225, longitude: 39.8262, name: "Makkah",
                                      timeZoneIdentifier: "Asia/Riyadh", countryCode: "SA")
}

enum HighLatitudeOption: String, Codable, CaseIterable, Identifiable {
    case automatic, middleOfTheNight, seventhOfTheNight, twilightAngle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .middleOfTheNight: "Middle of the night"
        case .seventhOfTheNight: "Seventh of the night"
        case .twilightAngle: "Twilight angle"
        }
    }

    var rule: HighLatitudeRule? {
        switch self {
        case .automatic: nil // Adhan picks the recommended rule for the location
        case .middleOfTheNight: .middleOfTheNight
        case .seventhOfTheNight: .seventhOfTheNight
        case .twilightAngle: .twilightAngle
        }
    }
}

struct PrayerSettings: Codable, Equatable {
    var method: CalculationMethod = .muslimWorldLeague
    var madhab: Madhab = .shafi
    var highLatitude: HighLatitudeOption = .automatic
    /// Minutes added to (or taken from) each calculated time.
    var adjustments: [String: Int] = [:]
    /// Once the user picks a method themselves we stop auto-suggesting one.
    var methodChosenManually = false

    init() {}

    func adjustment(for prayer: PrayerName) -> Int { adjustments[prayer.rawValue] ?? 0 }

    mutating func setAdjustment(_ minutes: Int, for prayer: PrayerName) {
        adjustments[prayer.rawValue] = minutes == 0 ? nil : minutes
    }

    var parameters: CalculationParameters {
        var params = method.params
        params.madhab = madhab
        params.highLatitudeRule = highLatitude.rule
        params.adjustments = PrayerAdjustments(
            fajr: adjustment(for: .fajr), sunrise: adjustment(for: .sunrise),
            dhuhr: adjustment(for: .dhuhr), asr: adjustment(for: .asr),
            maghrib: adjustment(for: .maghrib), isha: adjustment(for: .isha)
        )
        return params
    }

    // Tolerant decoding so adding settings in future versions never wipes old ones.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        method = (try? c.decodeIfPresent(CalculationMethod.self, forKey: .method)) ?? .muslimWorldLeague
        madhab = (try? c.decodeIfPresent(Madhab.self, forKey: .madhab)) ?? .shafi
        highLatitude = (try? c.decodeIfPresent(HighLatitudeOption.self, forKey: .highLatitude)) ?? .automatic
        adjustments = (try? c.decodeIfPresent([String: Int].self, forKey: .adjustments)) ?? [:]
        methodChosenManually = (try? c.decodeIfPresent(Bool.self, forKey: .methodChosenManually)) ?? false
    }
}

extension CalculationMethod {
    /// Methods shown in Settings (`.other` is for custom angles).
    static let selectable: [CalculationMethod] = allCases.filter { $0 != .other }

    var title: String {
        switch self {
        case .muslimWorldLeague: "Muslim World League"
        case .egyptian: "Egyptian General Authority"
        case .karachi: "University of Islamic Sciences, Karachi"
        case .ummAlQura: "Umm al-Qura, Makkah"
        case .dubai: "Dubai"
        case .moonsightingCommittee: "Moonsighting Committee"
        case .northAmerica: "ISNA (North America)"
        case .kuwait: "Kuwait"
        case .qatar: "Qatar"
        case .singapore: "Singapore / Malaysia / Indonesia"
        case .tehran: "Institute of Geophysics, Tehran"
        case .turkey: "Diyanet (Turkey)"
        case .other: "Custom"
        }
    }

    /// A sensible default for a country, based on what local mosques commonly use.
    static func recommended(forCountryCode code: String?) -> CalculationMethod {
        switch code?.uppercased() {
        case "US", "CA": .northAmerica
        case "GB", "IE": .moonsightingCommittee
        case "SA", "YE", "BH", "OM": .ummAlQura
        case "EG", "SD", "LY", "SY", "LB", "IQ", "JO", "PS", "DZ", "MA", "TN": .egyptian
        case "PK", "IN", "BD", "AF", "NP", "LK": .karachi
        case "AE": .dubai
        case "KW": .kuwait
        case "QA": .qatar
        case "SG", "MY", "ID", "BN": .singapore
        case "TR": .turkey
        case "IR": .tehran
        default: .muslimWorldLeague
        }
    }
}

extension Madhab {
    var title: String {
        switch self {
        case .shafi: "Standard"
        case .hanafi: "Hanafi"
        }
    }

    static func recommended(forCountryCode code: String?) -> Madhab {
        switch code?.uppercased() {
        case "PK", "IN", "BD", "AF", "TR": .hanafi
        default: .shafi
        }
    }
}

/// When, relative to each prayer, an alert is sent.
enum AlertTiming: String, Codable, CaseIterable, Identifiable, Comparable {
    case before30, before10, atTime, after30

    var id: String { rawValue }

    /// Offset from the prayer time, in minutes.
    var minutes: Int {
        switch self {
        case .before30: -30
        case .before10: -10
        case .atTime: 0
        case .after30: 30
        }
    }

    var title: String {
        switch self {
        case .before30: "30 minutes before"
        case .before10: "10 minutes before"
        case .atTime: "At prayer time (adhan)"
        case .after30: "30 minutes after"
        }
    }

    /// Alerts at or after the prayer time offer a "Log Prayer" button.
    var offersLogging: Bool { self == .atTime || self == .after30 }

    static func < (lhs: AlertTiming, rhs: AlertTiming) -> Bool { lhs.minutes < rhs.minutes }
}

struct NotificationSettings: Codable, Equatable {
    var enabledPrayers: Set<PrayerName> = Set(PrayerName.obligatory)
    /// Which alerts to send for each enabled prayer.
    var timings: Set<AlertTiming> = [.before10, .atTime, .after30]

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabledPrayers = (try? c.decodeIfPresent(Set<PrayerName>.self, forKey: .enabledPrayers)) ?? Set(PrayerName.obligatory)
        if let timings = try? c.decodeIfPresent(Set<AlertTiming>.self, forKey: .timings) {
            self.timings = timings
        } else {
            // Earlier versions had one optional "reminder before" setting.
            let legacy = try? decoder.container(keyedBy: LegacyKeys.self)
                .decodeIfPresent(Int.self, forKey: .reminderMinutesBefore)
            var timings: Set<AlertTiming> = [.atTime, .after30]
            if let legacy, legacy > 0 { timings.insert(legacy >= 20 ? .before30 : .before10) }
            self.timings = timings
        }
    }

    private enum LegacyKeys: String, CodingKey { case reminderMinutesBefore }
}
