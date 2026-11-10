import Foundation

/// Counts Arabic letters (not diacritics) for the recitation-reward estimate.
///
/// Based on the hadith in Jami' al-Tirmidhi 2910: each letter recited is a good
/// deed, multiplied tenfold, and "Alif Lam Mim" is three letters. We count the
/// letters written in the displayed Qur'an text (its rasm):
/// - counted: the Arabic letters U+0621–U+063A and U+0641–U+064A (including
///   hamza and alif maqsura), alif wasla (ٱ U+0671), and the dotless/Maghribi
///   letter forms some riwayat use (U+066E, U+066F, U+06A1, U+06A2, U+06A7, U+06A8, U+06BA)
/// - not counted: harakat and every other mark, the small "dagger" alif (U+0670),
///   small waw/ya (U+06E5, U+06E6), tatweel, spaces and waqf signs.
/// It is an estimate: letter-counting conventions differ between scholars.
enum ArabicLetters {
    static func count(in text: String) -> Int {
        text.unicodeScalars.reduce(0) { total, scalar in
            total + (isLetter(scalar.value) ? 1 : 0)
        }
    }

    static func isLetter(_ value: UInt32) -> Bool {
        switch value {
        case 0x0621...0x063A, 0x0641...0x064A: return true
        case 0x0671: return true
        case 0x066E, 0x066F, 0x06A1, 0x06A2, 0x06A7, 0x06A8, 0x06BA: return true
        default: return false
        }
    }
}

/// One day of Qur'an reading.
struct QuranDay: Codable, Equatable {
    /// Verses read that day, as "surah:verse" keys, so re-reading never double-counts.
    var verses: Set<String> = []
    /// Letters in those verses, for the reward estimate.
    var letters: Int = 0
    /// The daily goal in force that day. Stored per day so changing your goal
    /// later never rewrites past streaks.
    var goal: Int
    /// When the goal was reached, if it was.
    var completedAt: Date?
    /// Seconds spent in the daily reader that day.
    var seconds: Int = 0

    var count: Int { verses.count }
    var isComplete: Bool { completedAt != nil }

    init(verses: Set<String> = [], letters: Int = 0, goal: Int, completedAt: Date? = nil, seconds: Int = 0) {
        self.verses = verses
        self.letters = letters
        self.goal = goal
        self.completedAt = completedAt
        self.seconds = seconds
    }

    private enum CodingKeys: String, CodingKey { case verses, letters, goal, completedAt, seconds }

    // Days saved before reading time was kept have no `seconds`.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        verses = try c.decodeIfPresent(Set<String>.self, forKey: .verses) ?? []
        letters = try c.decodeIfPresent(Int.self, forKey: .letters) ?? 0
        goal = try c.decode(Int.self, forKey: .goal)
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        seconds = try c.decodeIfPresent(Int.self, forKey: .seconds) ?? 0
    }
}

/// Totals over a stretch of days, for "Today", "This week" and "All time".
struct QuranTotals: Equatable {
    var ayat = 0
    var letters = 0
    var seconds = 0
    /// Every verse read in the stretch, as "surah:verse".
    var verses: Set<String> = []

    /// The recitation-reward estimate (Tirmidhi 2910): ten per letter.
    var hasanat: Int { letters * 10 }
}

/// Tracks the daily Qur'an goal, reading progress and streaks. Stored in the App
/// Group so widgets, reminders and Groups can read it.
enum QuranProgress {
    private static let daysKey = "quran.days"
    private static let goalKey = "quran.dailyGoal"

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// The local calendar day an event happened on, e.g. "2026-09-26". Uses the
    /// phone's time zone at that moment, so reading just after midnight counts
    /// for the new day, and travelling doesn't merge or split days.
    static func dayKey(for date: Date) -> String {
        dayFormatter.timeZone = .current
        return dayFormatter.string(from: date)
    }

    /// Ayat per day, or nil if the user hasn't chosen a goal yet.
    static var dailyGoal: Int? {
        get {
            let value = AppGroup.defaults.integer(forKey: goalKey)
            return value > 0 ? value : nil
        }
        set { AppGroup.defaults.set(newValue ?? 0, forKey: goalKey) }
    }

    /// Every day's record. Read many times a second while reading, so the
    /// decoded days are kept until the saved bytes change (another process,
    /// such as a widget or the watch sync, may write them too).
    static func allDays() -> [String: QuranDay] {
        guard let data = AppGroup.defaults.data(forKey: daysKey) else { return [:] }
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cache, cache.data == data { return cache.days }
        let days = (try? JSONDecoder().decode([String: QuranDay].self, from: data)) ?? [:]
        cache = (data, days)
        return days
    }

    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cache: (data: Data, days: [String: QuranDay])?

    /// The days and goal the Apple Watch shows, as sent from the iPhone.
    static func recent(days count: Int, asOf date: Date = .now) -> [String: QuranDay] {
        let calendar = Calendar.current
        let keys = Set((0..<count).compactMap { calendar.date(byAdding: .day, value: -$0, to: date) }.map(dayKey(for:)))
        return allDays().filter { keys.contains($0.key) }
    }

    /// On the watch: takes the iPhone's days, which are the record.
    static func merge(_ days: [String: QuranDay], goal: Int?) {
        save(allDays().merging(days) { _, phone in phone })
        dailyGoal = goal
    }

    private static func save(_ days: [String: QuranDay]) {
        AppGroup.defaults.setEncoded(days, forKey: daysKey)
    }

    static func day(_ date: Date = .now) -> QuranDay {
        allDays()[dayKey(for: date)] ?? QuranDay(goal: dailyGoal ?? 0)
    }

    /// Records a verse as read. Returns true only the moment the day's goal is
    /// first reached (so the celebration shows once per day).
    @discardableResult
    static func recordRead(surah: Int, verse: Int, letters: Int, at date: Date = .now) -> Bool {
        let key = dayKey(for: date)
        var days = allDays()
        var day = days[key] ?? QuranDay(goal: dailyGoal ?? 0)
        let verseKey = "\(surah):\(verse)"
        guard !day.verses.contains(verseKey) else { return false }
        day.verses.insert(verseKey)
        day.letters += letters
        var justCompleted = false
        if day.completedAt == nil, day.goal > 0, day.count >= day.goal {
            day.completedAt = date
            justCompleted = true
        }
        days[key] = day
        save(days)
        return justCompleted
    }

    /// Sets a new goal. Today picks it up (and may complete immediately); past days keep theirs.
    static func setGoal(_ goal: Int, at date: Date = .now) {
        dailyGoal = goal
        let key = dayKey(for: date)
        var days = allDays()
        var today = days[key] ?? QuranDay(goal: goal)
        if today.completedAt == nil {
            today.goal = goal
            if today.count >= goal { today.completedAt = date }
        }
        days[key] = today
        save(days)
    }

    // MARK: Streaks and totals

    /// Consecutive completed days ending today (or yesterday, if today isn't done yet).
    static func currentStreak(asOf date: Date = .now, days: [String: QuranDay]? = nil) -> Int {
        let days = days ?? allDays()
        let calendar = Calendar.current
        var cursor = date
        if days[dayKey(for: cursor)]?.isComplete != true {
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }
        var streak = 0
        while days[dayKey(for: cursor)]?.isComplete == true, streak < 100_000 {
            streak += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }
        return streak
    }

    static func longestStreak(days: [String: QuranDay]? = nil) -> Int {
        let days = days ?? allDays()
        let completed = days.filter { $0.value.isComplete }.keys.compactMap { dayFormatter.date(from: $0) }.sorted()
        var longest = 0, run = 0
        var previous: Date?
        let calendar = Calendar(identifier: .gregorian)
        for date in completed {
            if let previous, calendar.dateComponents([.day], from: previous, to: date).day == 1 {
                run += 1
            } else {
                run = 1
            }
            longest = max(longest, run)
            previous = date
        }
        return longest
    }

    /// Verses and letters read over the last `count` days including today.
    static func totals(lastDays count: Int, asOf date: Date = .now) -> (ayat: Int, letters: Int, completedDays: Int) {
        let days = allDays()
        let calendar = Calendar.current
        var ayat = 0, letters = 0, completed = 0
        for offset in 0..<count {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: date), let entry = days[dayKey(for: day)] else { continue }
            ayat += entry.count
            letters += entry.letters
            if entry.isComplete { completed += 1 }
        }
        return (ayat, letters, completed)
    }

    /// Adds time spent reading to that day. Ignores nonsense (negative or over a day).
    static func addReadingTime(_ seconds: Int, at date: Date = .now) {
        guard seconds > 0, seconds < 86_400 else { return }
        let key = dayKey(for: date)
        var days = allDays()
        var day = days[key] ?? QuranDay(goal: dailyGoal ?? 0)
        day.seconds += seconds
        days[key] = day
        save(days)
    }

    /// Totals for the last `count` days including today, or every day when nil.
    static func totals(days count: Int?, asOf date: Date = .now, from days: [String: QuranDay]? = nil) -> QuranTotals {
        let days = days ?? allDays()
        let entries: [QuranDay]
        if let count {
            let calendar = Calendar.current
            entries = (0..<max(count, 0)).compactMap { offset in
                calendar.date(byAdding: .day, value: -offset, to: date).flatMap { days[dayKey(for: $0)] }
            }
        } else {
            entries = Array(days.values)
        }
        return entries.reduce(into: QuranTotals()) { total, day in
            total.ayat += day.count
            total.letters += day.letters
            total.seconds += day.seconds
            total.verses.formUnion(day.verses)
        }
    }

    static func allTime() -> (ayat: Int, letters: Int) {
        allDays().values.reduce((0, 0)) { ($0.0 + $1.count, $0.1 + $1.letters) }
    }
}

/// Settings for Qur'an notifications (Qur'an › Notifications).
struct QuranReminderSettings: Codable, Equatable {
    /// Master switch for every Qur'an notification.
    var isEnabled = false

    /// Morning nudge towards the daily goal (skipped if already done).
    var morningEnabled = true
    /// Minutes after midnight.
    var morningMinute = 8 * 60
    /// Afternoon check-in, only if the goal isn't done yet.
    var afternoonEnabled = true
    var afternoonMinute = 16 * 60
    /// If the goal is already done by the afternoon, send "completed" instead of nothing.
    var sendCompletionMessage = false
    /// Late-evening "your streak is at risk", only if the goal isn't done yet.
    var eveningEnabled = false
    var eveningMinute = 21 * 60
    /// One verse each day (from the verified daily-verse list), opening at that verse.
    var verseOfDayEnabled = false
    var verseOfDayMinute = 7 * 60
    /// Friday reminder to read Surah Al-Kahf.
    var kahfEnabled = false
    var kahfMinute = 10 * 60

    init() {}

    // Tolerant decoding: older saved settings simply miss the newer fields.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            ((try? c.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
        }
        let defaults = QuranReminderSettings()
        isEnabled = value(.isEnabled, defaults.isEnabled)
        morningEnabled = value(.morningEnabled, defaults.morningEnabled)
        morningMinute = value(.morningMinute, defaults.morningMinute)
        afternoonEnabled = value(.afternoonEnabled, defaults.afternoonEnabled)
        afternoonMinute = value(.afternoonMinute, defaults.afternoonMinute)
        sendCompletionMessage = value(.sendCompletionMessage, defaults.sendCompletionMessage)
        eveningEnabled = value(.eveningEnabled, defaults.eveningEnabled)
        eveningMinute = value(.eveningMinute, defaults.eveningMinute)
        verseOfDayEnabled = value(.verseOfDayEnabled, defaults.verseOfDayEnabled)
        verseOfDayMinute = value(.verseOfDayMinute, defaults.verseOfDayMinute)
        kahfEnabled = value(.kahfEnabled, defaults.kahfEnabled)
        kahfMinute = value(.kahfMinute, defaults.kahfMinute)
    }
}
