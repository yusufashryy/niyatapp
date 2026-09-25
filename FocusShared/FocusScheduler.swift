import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

/// Prayer Lock settings, shared with the Screen Time extensions.
struct FocusSettings: Codable, Equatable {
    var isEnabled = false
    var prayers: Set<PrayerName> = Set(PrayerName.obligatory)
    /// How long apps stay locked after the adhan. Apple requires at least 15 minutes.
    var minutes = 20

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .isEnabled)) ?? false
        prayers = (try? c.decodeIfPresent(Set<PrayerName>.self, forKey: .prayers)) ?? Set(PrayerName.obligatory)
        minutes = (try? c.decodeIfPresent(Int.self, forKey: .minutes)) ?? 20
    }
}

enum FocusStore {
    private enum Key {
        static let settings = "focus.settings"
        static let selection = "focus.selection"
        static let activePrayer = "focus.activePrayer"
        static let lockedUntil = "focus.lockedUntil"
    }

    private static var defaults: UserDefaults { AppGroup.defaults }

    static var settings: FocusSettings {
        get { defaults.decoded(FocusSettings.self, forKey: Key.settings) ?? FocusSettings() }
        set { defaults.setEncoded(newValue, forKey: Key.settings) }
    }

    /// The apps, categories and websites the user chose to lock.
    static var selection: FamilyActivitySelection {
        get { defaults.decoded(FamilyActivitySelection.self, forKey: Key.selection) ?? FamilyActivitySelection() }
        set { defaults.setEncoded(newValue, forKey: Key.selection) }
    }

    /// Which prayer the current lock is for (shown on the shield screen). nil = manual lock.
    static var activePrayer: PrayerName? {
        get { defaults.string(forKey: Key.activePrayer).flatMap(PrayerName.init(rawValue:)) }
        set { defaults.set(newValue?.rawValue, forKey: Key.activePrayer) }
    }

    /// When the current lock ends, if one is active.
    static var lockedUntil: Date? {
        get { defaults.object(forKey: Key.lockedUntil) as? Date }
        set { defaults.set(newValue, forKey: Key.lockedUntil) }
    }
}

extension ManagedSettingsStore.Name {
    static let prayerLock = Self("salah.prayerLock")
}

/// Schedules Screen Time "activities" that start at each prayer time. When one
/// starts, iOS wakes FocusMonitor, which locks the chosen apps; when it ends,
/// the apps unlock and the next prayers get scheduled.
enum FocusScheduler {
    private static let prayerPrefix = "prayer."
    private static let manualPrefix = "manual."
    /// iOS allows about 20 monitored activities; stay well under.
    private static let lookahead = 8
    private static let minimumMinutes = 15

    static func reschedule(now: Date = .now) {
        let center = DeviceActivityCenter()
        let existing = center.activities.filter { $0.rawValue.hasPrefix(prayerPrefix) }
        if !existing.isEmpty { center.stopMonitoring(existing) }

        let settings = FocusStore.settings
        guard settings.isEnabled, !settings.prayers.isEmpty, let location = SettingsStore.location else { return }
        let minutes = max(settings.minutes, minimumMinutes)

        // Look back one window so a lock that's already running gets kept.
        let windowStart = now.addingTimeInterval(TimeInterval(-minutes * 60))
        let upcoming = PrayerCalculator.upcoming(after: windowStart, count: 20, location: location,
                                                 settings: SettingsStore.prayerSettings)
            .filter { settings.prayers.contains($0.name) }
            .prefix(lookahead)

        for time in upcoming {
            let end = time.date.addingTimeInterval(TimeInterval(minutes * 60))
            let name = activityName(prefix: prayerPrefix, prayer: time.name, start: time.date, end: end)
            try? center.startMonitoring(name, during: schedule(from: time.date, to: end))
        }
    }

    /// Lock the chosen apps right now for `minutes` (e.g. "I want to read Quran").
    static func startManualLock(minutes: Int, now: Date = .now) throws {
        let minutes = max(minutes, minimumMinutes)
        let end = now.addingTimeInterval(TimeInterval(minutes * 60))
        let name = activityName(prefix: manualPrefix, prayer: nil, start: now, end: end)
        applyShield(for: nil, until: end)
        try DeviceActivityCenter().startMonitoring(name, during: schedule(from: now, to: end))
    }

    /// "I've prayed" — unlock now. The next prayer will still lock as usual.
    static func endCurrentLock() {
        let center = DeviceActivityCenter()
        let manual = center.activities.filter { $0.rawValue.hasPrefix(manualPrefix) }
        if !manual.isEmpty { center.stopMonitoring(manual) }
        clearShield()
    }

    /// Activity names look like "prayer.dhuhr.<start>.<end>" or "manual.none.<start>.<end>".
    private static func activityName(prefix: String, prayer: PrayerName?, start: Date, end: Date) -> DeviceActivityName {
        DeviceActivityName("\(prefix)\(prayer?.rawValue ?? "none").\(Int(start.timeIntervalSince1970)).\(Int(end.timeIntervalSince1970))")
    }

    static func handleIntervalStart(_ activity: DeviceActivityName) {
        let parts = activity.rawValue.split(separator: ".").map(String.init)
        let prayer = parts.count > 1 ? PrayerName(rawValue: parts[1]) : nil
        let end = parts.count > 3 ? Double(parts[3]).map { Date(timeIntervalSince1970: $0) } : nil
        let fallbackEnd = Date.now.addingTimeInterval(TimeInterval(max(FocusStore.settings.minutes, minimumMinutes) * 60))
        applyShield(for: prayer, until: end ?? fallbackEnd)
    }

    static func handleIntervalEnd(_ activity: DeviceActivityName) {
        clearShield()
        if activity.rawValue.hasPrefix(manualPrefix) {
            DeviceActivityCenter().stopMonitoring([activity])
        }
        reschedule()
    }

    static var isLocked: Bool {
        guard let until = FocusStore.lockedUntil else { return false }
        return until > .now
    }

    static func applyShield(for prayer: PrayerName?, until end: Date) {
        let selection = FocusStore.selection
        let store = ManagedSettingsStore(named: .prayerLock)
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
        if selection.categoryTokens.isEmpty {
            store.shield.applicationCategories = nil
            store.shield.webDomainCategories = nil
        } else {
            store.shield.applicationCategories = .specific(selection.categoryTokens)
            store.shield.webDomainCategories = .specific(selection.categoryTokens)
        }
        FocusStore.activePrayer = prayer
        FocusStore.lockedUntil = end
    }

    static func clearShield() {
        ManagedSettingsStore(named: .prayerLock).clearAllSettings()
        FocusStore.activePrayer = nil
        FocusStore.lockedUntil = nil
    }

    private static func schedule(from start: Date, to end: Date) -> DeviceActivitySchedule {
        let calendar = Calendar.current
        let units: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        return DeviceActivitySchedule(intervalStart: calendar.dateComponents(units, from: start),
                                      intervalEnd: calendar.dateComponents(units, from: end),
                                      repeats: false)
    }
}
