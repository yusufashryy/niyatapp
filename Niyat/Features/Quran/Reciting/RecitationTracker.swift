import Foundation

/// Follows a recitation through a stretch of Qur'an text, word by word.
///
/// Pure logic (no audio), so it is unit-tested. The speech recogniser hands it
/// what it heard in the current utterance (a growing list of words, revised as
/// it listens); the tracker lines that up with the expected words and keeps:
/// - `position`: the word the reciter has reached,
/// - a result for each word passed: correct, uncertain, likely mistake, or skipped.
///
/// Design choices:
/// - It never assumes the reciter starts at word 1: the first words heard are
///   searched for across the window it is given (the page, or the verses on
///   screen), preferring places close to where it expects them.
/// - Pauses keep the position; the next utterance continues from there. Going
///   back (repeating a phrase, restarting an ayah) is allowed and never flagged.
/// - It is conservative. Words are only judged when an utterance ends, and a
///   word is called a likely mistake only when something clearly different was
///   heard with good recogniser confidence. Otherwise it is "uncertain".
struct RecitationTracker {
    struct Token {
        let id: WordID
        /// Recognition forms: the normalised word, plus accepted alternatives
        /// (everyday spelling, letter names for the disjoined letters).
        let forms: [String]
    }

    enum Result: Equatable {
        /// Final transcript matched an accepted spelling; not a pronunciation verdict.
        case correct
        /// Couldn't tell: shown with a neutral mark, never as an error.
        case uncertain
        /// Something clearly different was heard.
        case mistake
        /// Passed over: words on both sides were heard, this one wasn't.
        case skipped
    }

    enum Status: Equatable {
        /// Listening for the first words, to find where the reciter is.
        case searching
        /// Several words heard that don't match the text in the window.
        case lost
        /// Following word by word.
        case following
    }

    let tokens: [Token]
    private(set) var position: Int?
    private(set) var committed: [Int: Result] = [:]
    /// Words passed in the current utterance, before it is judged.
    private(set) var provisional: [Int: Kind] = [:]
    /// Provisional mismatches are unverified until a confident final result.
    private(set) var early: [Int: Result] = [:]
    private let tokenForms: [[[UInt16]]]
    private var expected = 0
    private var locked = false
    private var searchRange: Range<Int> = 0..<0

    enum Kind { case matched, different, skipped }

    // Alignment costs. A match earns a reward, so the best path explains the
    // most speech. Different words cost little (the recogniser mishears);
    // skipping text costs more; extra speech (repeats, the isti'adha) is cheap.
    private static let matchCost = -1.0
    private static let differentCost = 0.3
    private static let skipCost = 1.0
    private static let extraCost = 0.4
    private static let leadingExtraCost = 0.1

    init(tokens: [Token]) {
        self.tokens = tokens
        tokenForms = tokens.map { $0.forms.map { Array($0.utf16) } }
        searchRange = 0..<tokens.count
    }

    /// Starts following near `index`, searching `ahead` words forward (and a
    /// few back) for the first words heard.
    mutating func begin(at index: Int, searchingAhead ahead: Int = 200) {
        expected = min(max(index, 0), max(tokens.count - 1, 0))
        locked = false
        position = nil
        provisional = [:]
        early = [:]
        searchRange = max(0, expected - 5)..<min(tokens.count, expected + max(1, ahead))
    }

    /// Where the reciter is, or where they're expected to start.
    var focus: Int { position ?? expected }

    /// Partial hypotheses never certify a word, even when they match the text.
    /// Re-reading a word temporarily replaces its old verdict until finalized.
    var displayResults: [Int: Result] {
        var results = committed
        for index in provisional.keys { results[index] = .uncertain }
        return results
    }

    func result(at index: Int) -> Result? { displayResults[index] }

    /// Words worth reviewing: everything not judged correct.
    var flagged: [(index: Int, result: Result)] {
        committed.filter { $0.value != .correct }.map { ($0.key, $0.value) }.sorted { $0.index < $1.index }
    }

    /// Takes what the recogniser has heard in the current utterance so far.
    /// `confidences` (one per word, 0-1) are only reliable when `isFinal`.
    mutating func update(heard words: [String], confidences: [Float]? = nil, isFinal: Bool) -> Status {
        let heard = words.map(RecitationMatcher.normalize)
        var keptConfidences: [Float] = []
        var kept: [[UInt16]] = []
        for (i, word) in heard.enumerated() where !word.isEmpty {
            kept.append(Array(word.utf16))
            keptConfidences.append(confidences?.indices.contains(i) == true ? confidences![i] : 0)
        }
        provisional = [:]
        early = [:]
        guard !kept.isEmpty, !tokens.isEmpty else { return locked ? .following : .searching }

        let window: Range<Int>
        let penaltyPerWord: Double
        if locked {
            window = max(0, expected - 40)..<min(tokens.count, expected + kept.count + 30)
            penaltyPerWord = 0.05
        } else {
            window = searchRange
            penaltyPerWord = 0.01
        }
        let steps = align(heard: kept, window: window, penaltyPerWord: penaltyPerWord)
        let matched = steps.filter { $0.kind == .matched }.compactMap(\.token)

        if !locked {
            let sorted = matched.sorted()
            let hasPair = zip(sorted, sorted.dropFirst()).contains { $1 == $0 + 1 }
            guard matched.count >= 2, hasPair else { return kept.count >= 8 ? .lost : .searching }
            expected = steps.compactMap(\.token).min() ?? expected
            locked = true
        }

        provisional = [:]
        guard !matched.isEmpty, let last = steps.compactMap(\.token).max() else {
            guard kept.count >= 8 else { return .following }
            // Lost the place: search more widely around it for the next words.
            locked = false
            searchRange = max(0, expected - 60)..<min(tokens.count, expected + 300)
            return .lost
        }
        // Once following, a gap between requests is unverified, not silently
        // passed. It may be an omission or a recognition failure.
        if let first = steps.compactMap(\.token).min(), position != nil, first > expected {
            for index in expected..<first { provisional[index] = .skipped }
        }
        for step in steps {
            guard let token = step.token, token <= last else { continue }
            provisional[token] = step.kind
            if !isFinal, step.kind != .matched { early[token] = .uncertain }
        }
        position = last

        if isFinal {
            judge(steps: steps, confidences: keptConfidences)
            expected = last + 1
        }
        return .following
    }

    /// Ends the utterance in progress (the reciter stopped), judging what was heard.
    mutating func finishUtterance() {
        // A timeout, stop or recognition error is not a confident final result.
        for token in provisional.keys { committed[token] = .uncertain }
        provisional = [:]
        early = [:]
        if let position { expected = position + 1 }
    }

    /// Replaces the verdict for some words with a better-informed one (the
    /// recitation model's check of the audio against the expected words).
    mutating func applyChecked(_ results: [Int: Result]) {
        for (index, result) in results where tokens.indices.contains(index) {
            committed[index] = result
        }
    }

    private mutating func judge(steps: [Step], confidences: [Float]) {
        // Include gaps at request boundaries and weakly anchored omissions.
        for token in provisional.keys { committed[token] = .uncertain }
        let confidentMatches = steps.map { step in
            step.kind == .matched && !step.heardIndices.isEmpty &&
                step.heardIndices.allSatisfy { confidences[$0] >= 0.5 }
        }
        var before = 0
        var remaining = confidentMatches.filter { $0 }.count
        for (offset, step) in steps.enumerated() {
            if confidentMatches[offset] { remaining -= 1 }
            defer { if confidentMatches[offset] { before += 1 } }
            guard let token = step.token, let kind = provisional[token] else { continue }
            switch kind {
            case .matched:
                committed[token] = confidentMatches[offset] ? .correct : .uncertain
            case .different:
                if let h = step.heard, confidences[h] >= 0.5 { committed[token] = .mistake }
            case .skipped:
                if before >= 2, remaining >= 2 { committed[token] = .skipped }
            }
        }
        provisional = [:]
        early = [:]
    }

    // MARK: Alignment

    /// Lines up everything heard in a whole recording (one ayah) with its
    /// words, for timing the reciter's audio. Returns the words that were
    /// clearly recognised: (token index, index in `words`). Words that were
    /// misheard or not heard are left out, never guessed.
    static func matchedPairs(tokens: [Token], heard words: [String]) -> [(token: Int, heard: Int)] {
        var kept: [[UInt16]] = []
        var original: [Int] = []
        for (index, word) in words.enumerated() {
            let normalized = RecitationMatcher.normalize(word)
            guard !normalized.isEmpty else { continue }
            kept.append(Array(normalized.utf16))
            original.append(index)
        }
        guard !kept.isEmpty, !tokens.isEmpty else { return [] }
        let tracker = RecitationTracker(tokens: tokens)
        let steps = tracker.align(heard: kept, window: 0..<tokens.count, penaltyPerWord: 0.05)
        var pairs: [(token: Int, heard: Int)] = []
        var used = Set<Int>()
        for step in steps where step.kind == .matched {
            // Two words heard as one: only the first starts at that time.
            guard let token = step.token, let heard = step.heard, used.insert(heard).inserted else { continue }
            pairs.append((token, original[heard]))
        }
        return pairs
    }

    struct Step {
        let kind: Kind
        let token: Int?
        let heard: Int?
        var heardCount = 1
        var heardIndices: Range<Int> {
            guard let heard else { return 0..<0 }
            return heard..<(heard + heardCount)
        }
    }

    private enum Move {
        case start, match, different, mergedHeard(Int), mergedTokens, skip, extra
    }

    /// Lines `heard` up with the tokens in `window`: it may start at any token
    /// (small penalty for distance from `expected`) and end anywhere (words
    /// not reached yet are simply pending).
    private func align(heard: [[UInt16]], window: Range<Int>, penaltyPerWord: Double) -> [Step] {
        let forms = Array(tokenForms[window])
        let w = forms.count, m = heard.count
        let infinity = Double.greatestFiniteMagnitude
        var cost = Array(repeating: Array(repeating: infinity, count: m + 1), count: w + 1)
        var move = Array(repeating: Array(repeating: Move.start, count: m + 1), count: w + 1)

        // Heard words joined, for recognisers that split one Uthmani word
        // (يا أيها for يَٰٓأَيُّهَا, alif lam mim for الٓمٓ).
        // Build these once per transcript, not up to four times in every cell.
        let joined = (0...m).map { end in
            (2...5).map { count in end >= count ? heard[(end - count)..<end].flatMap { $0 } : [] }
        }

        for i in 0...w {
            let startPenalty = Double(abs(window.lowerBound + i - expected)) * penaltyPerWord
            for j in 0...m {
                var best = startPenalty + Double(j) * Self.leadingExtraCost
                var bestMove = Move.start
                if i > 0, j > 0 {
                    let same = forms[i - 1].contains { $0 == heard[j - 1] }
                    let c = cost[i - 1][j - 1] + (same ? Self.matchCost : Self.differentCost)
                    if c < best { best = c; bestMove = same ? .match : .different }
                }
                if i > 0 {
                    for count in 2...5 where j >= count {
                        let together = joined[j][count - 2]
                        if forms[i - 1].contains(where: { $0 == together }) {
                            let c = cost[i - 1][j - count] + Self.matchCost
                            if c < best { best = c; bestMove = .mergedHeard(count) }
                        }
                    }
                }
                if i > 1, j > 0, forms[i - 2].contains(where: { left in forms[i - 1].contains { left + $0 == heard[j - 1] } }) {
                    let c = cost[i - 2][j - 1] + 2 * Self.matchCost
                    if c < best { best = c; bestMove = .mergedTokens }
                }
                if i > 0 {
                    let c = cost[i - 1][j] + Self.skipCost
                    if c < best { best = c; bestMove = .skip }
                }
                if j > 0 {
                    let c = cost[i][j - 1] + Self.extraCost
                    if c < best { best = c; bestMove = .extra }
                }
                cost[i][j] = best
                move[i][j] = bestMove
            }
        }

        // Where the reciter has got to: the end that explains everything heard
        // most cheaply (ties go to the furthest).
        var end = 0
        for i in 0...w where cost[i][m] <= cost[end][m] { end = i }

        var steps: [Step] = []
        var i = end, j = m
        loop: while true {
            let token = window.lowerBound + i - 1
            switch move[i][j] {
            case .start:
                break loop
            case .match:
                steps.append(Step(kind: .matched, token: token, heard: j - 1)); i -= 1; j -= 1
            case .different:
                steps.append(Step(kind: .different, token: token, heard: j - 1)); i -= 1; j -= 1
            case .mergedHeard(let count):
                steps.append(Step(kind: .matched, token: token, heard: j - count, heardCount: count)); i -= 1; j -= count
            case .mergedTokens:
                steps.append(Step(kind: .matched, token: token, heard: j - 1))
                steps.append(Step(kind: .matched, token: token - 1, heard: j - 1)); i -= 2; j -= 1
            case .skip:
                steps.append(Step(kind: .skipped, token: token, heard: nil)); i -= 1
            case .extra:
                j -= 1
            }
        }
        return steps.reversed()
    }

}
