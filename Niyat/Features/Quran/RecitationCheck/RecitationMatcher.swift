import Foundation

/// Compares what the speech recogniser heard with the words of the verse
/// being recited. Pure logic, no audio, so it's fully unit-tested.
///
/// It's tuned to avoid false alarms: a word only counts as a mistake when the
/// words around it were clearly recognised, and small spelling differences
/// between the recogniser and the Qur'an text are ignored.
enum RecitationMatcher {
    enum WordState: Equatable {
        /// Not reached yet.
        case pending
        /// Heard and matched.
        case matched
        /// Something else was heard in its place.
        case different
        /// Passed over: later words were heard but not this one.
        case skipped
    }

    /// Letters only, with the spelling differences between Qur'anic and modern
    /// Arabic folded together (alef forms, hamza seats, ta marbuta, alef maqsura).
    static func normalize(_ word: String) -> String {
        var result = String.UnicodeScalarView()
        for scalar in word.unicodeScalars {
            switch scalar.value {
            case 0x0622, 0x0623, 0x0625, 0x0671, 0x0672, 0x0673: result.append("ا")
            case 0x0649, 0x0626: result.append("ي")
            case 0x0629: result.append("ه")
            case 0x0624: result.append("و")
            case 0x0621, 0x0640: continue
            default:
                if ArabicLetters.isLetter(scalar.value) { result.append(scalar) }
            }
        }
        return String(result)
    }

    static func words(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init).filter { !normalize($0).isEmpty }
    }

    /// Close enough to count as the same word (allows one letter off in
    /// short words, a quarter of the letters in longer ones).
    static func similar(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let allowed = max(1, max(a.count, b.count) / 4)
        guard abs(a.count - b.count) <= allowed else { return false }
        return distance(Array(a), Array(b)) <= allowed
    }

    private static func distance(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count]
    }

    /// Lines up `heard` against `expected` (both already normalised) and
    /// returns a state for each expected word. Extra words (repeating a
    /// phrase, saying the isti'adha first) are allowed and never flagged.
    static func align(expected: [String], heard: [String]) -> [WordState] {
        let n = expected.count, m = heard.count
        guard n > 0 else { return [] }
        guard m > 0 else { return Array(repeating: .pending, count: n) }

        // A match earns a reward, so the best path is the one that explains
        // the most of what was heard. Extra words cost little; skipping costs more.
        let matchCost = -1.0, differentCost = 0.3, skipCost = 1.0
        let extraCost = 0.4, leadingExtraCost = 0.1
        // cost[i][j]: best cost of matching expected[0..<i] with heard[0..<j].
        var cost = Array(repeating: Array(repeating: Double.infinity, count: m + 1), count: n + 1)
        enum Step { case start, match, different, skip, extra }
        var step = Array(repeating: Array(repeating: Step.start, count: m + 1), count: n + 1)
        cost[0][0] = 0
        for j in 1...m {
            cost[0][j] = Double(j) * leadingExtraCost
            step[0][j] = .extra
        }
        for i in 1...n {
            cost[i][0] = Double(i) * skipCost
            step[i][0] = .skip
            for j in 1...m {
                let same = similar(expected[i - 1], heard[j - 1])
                let options: [(Double, Step)] = [
                    (cost[i - 1][j - 1] + (same ? matchCost : differentCost), same ? .match : .different),
                    (cost[i - 1][j] + skipCost, .skip),
                    (cost[i][j - 1] + extraCost, .extra),
                ]
                let best = options.min { $0.0 < $1.0 }!
                cost[i][j] = best.0
                step[i][j] = best.1
            }
        }

        // How far through the verse the reciter has got: the end point that
        // explains everything heard most cheaply (later words are pending).
        var end = 0
        for i in 0...n where cost[i][m] <= cost[end][m] { end = i }

        var states = Array(repeating: WordState.pending, count: n)
        var i = end, j = m
        while i > 0 || j > 0 {
            switch step[i][j] {
            case .match: states[i - 1] = .matched; i -= 1; j -= 1
            case .different: states[i - 1] = .different; i -= 1; j -= 1
            case .skip: states[i - 1] = .skipped; i -= 1
            case .extra, .start: j -= 1
            }
        }
        return states
    }

    /// The last word was heard: the verse is done.
    static func isComplete(_ states: [WordState]) -> Bool {
        states.last == .matched
    }

    /// The end was reached but the last word sounded different. The caller
    /// waits a moment (the recogniser often corrects itself) before moving on.
    static func probablyComplete(_ states: [WordState]) -> Bool {
        states.last == .different && states.filter { $0 == .matched }.count * 2 >= states.count
    }
}
