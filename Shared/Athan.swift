import Foundation

/// A muezzin whose athan Niyat plays: Aladhan's recordings (Islamic Network,
/// see docs/SOURCES.md). The alert plays a short opening bundled with the
/// app; the full athan streams from Aladhan when you open the alert.
enum Muezzin: String, Codable, CaseIterable, Identifiable {
    case alafasy
    case alafasyDubai = "alafasy-dubai"
    case alafasy2 = "alafasy-2"
    case nafees
    case ozcan
    case zahrani

    var id: String { rawValue }

    var name: String {
        switch self {
        case .alafasy, .alafasyDubai, .alafasy2: "Mishary Rashid Alafasy"
        case .nafees: "Ahmad al-Nafees"
        case .ozcan: "Hafiz Mustafa Özcan"
        case .zahrani: "Mansour Al-Zahrani"
        }
    }

    /// Tells Alafasy's three recordings apart.
    var detail: String? {
        switch self {
        case .alafasy: "Recording 1"
        case .alafasy2: "Recording 2"
        case .alafasyDubai: "From Dubai One TV"
        case .ozcan: "Turkey"
        case .nafees, .zahrani: nil
        }
    }

    private var fileName: String {
        switch self {
        case .alafasy: "a9.mp3"
        case .alafasyDubai: "a4.mp3"
        case .alafasy2: "a7.mp3"
        case .nafees: "a1.mp3"
        case .ozcan: "a2.mp3"
        case .zahrani: "a11-mansour-al-zahrani.mp3"
        }
    }

    /// The whole recording.
    var recordingURL: URL {
        URL(string: "https://cdn.aladhan.com/audio/adhans/\(fileName)")!
    }

    /// Seconds into the recording where the muezzin begins, after any intro
    /// (the same start as the alert sound, see scripts/make_athan_sounds.sh).
    var startOffset: TimeInterval {
        switch self {
        case .alafasy: 0.85
        case .alafasyDubai: 5.95
        case .alafasy2: 4.85
        case .nafees: 9.05
        case .ozcan: 7.85
        case .zahrani: 0
        }
    }

    /// The alert sound in the app bundle: the athan's opening, under the
    /// 30 seconds iOS allows.
    var alertSoundName: String { "athan-\(rawValue).caf" }
}

/// Which athan the prayer alerts play.
struct AthanSettings: Codable, Equatable {
    /// The athan when a prayer begins; nil keeps the standard alert sound.
    var muezzin: Muezzin? = .alafasy
    /// Fajr's own athan; nil uses `muezzin`.
    var fajrMuezzin: Muezzin?
    /// Opening the alert, or having Niyat open when it comes, plays the whole athan.
    var playsFullAthan = true
    /// The alert itself plays the whole athan, in parts sent back to back
    /// (see `AthanSegments`), without opening Niyat.
    var fullAthanFromAlert = false

    init() {}

    /// The athan for an alert, or nil for the standard sound. Only the alert
    /// when a prayer begins has one; the reminders before and after don't,
    /// and nor does sunrise.
    func muezzin(for prayer: PrayerName, timing: AlertTiming) -> Muezzin? {
        guard timing == .atTime, prayer.isObligatory else { return nil }
        if prayer == .fajr, let fajrMuezzin { return fajrMuezzin }
        return muezzin
    }

    // Tolerant decoding, so adding settings later never resets the others.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AthanSettings()
        muezzin = c.contains(.muezzin) ? try c.decodeIfPresent(Muezzin.self, forKey: .muezzin) : defaults.muezzin
        fajrMuezzin = (try? c.decodeIfPresent(Muezzin.self, forKey: .fajrMuezzin)) ?? nil
        playsFullAthan = (try? c.decodeIfPresent(Bool.self, forKey: .playsFullAthan)) ?? defaults.playsFullAthan
        fullAthanFromAlert = (try? c.decodeIfPresent(Bool.self, forKey: .fullAthanFromAlert)) ?? defaults.fullAthanFromAlert
    }

    /// Writes "no athan" as an explicit null, so it isn't read back as the default.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(muezzin, forKey: .muezzin)
        try c.encode(fajrMuezzin, forKey: .fajrMuezzin)
        try c.encode(playsFullAthan, forKey: .playsFullAthan)
        try c.encode(fullAthanFromAlert, forKey: .fullAthanFromAlert)
    }

    private enum CodingKeys: String, CodingKey { case muezzin, fajrMuezzin, playsFullAthan, fullAthanFromAlert }
}
