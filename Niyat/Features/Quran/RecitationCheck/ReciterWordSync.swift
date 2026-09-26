import AVFoundation
import Foundation
import Speech

/// When each word of an ayah starts in a reciter's recording.
struct WordTimings: Codable, Equatable {
    /// Start time (seconds) of each word, by displayed word index.
    let starts: [Double]
    /// How many words were placed by recognition (the rest lie between them).
    let anchored: Int

    /// The word being recited at `time`.
    func word(at time: Double) -> Int? {
        guard let first = starts.first, time >= first else { return nil }
        var low = 0, high = starts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if starts[mid] <= time { low = mid } else { high = mid - 1 }
        }
        return low
    }
}

/// Highlights the word the reciter is saying.
///
/// Niyat's recitation audio has no published word timings, so each ayah's
/// recording is aligned on the iPhone: Apple's speech recognition transcribes
/// the reciter (with the time of each word), and the words it recognised are
/// matched to the verified text by the same aligner as live recitation. An
/// ayah is only followed word by word when most of its words (60%) were
/// placed this way; words between placed ones share the time in between.
/// Otherwise the whole ayah stays highlighted, as before. Nothing is guessed
/// from the text alone, and results are cached so each ayah is aligned once.
@MainActor
final class ReciterWordSync {
    static let shared = ReciterWordSync()
    static let settingKey = "quran.wordSync"

    /// Settings › Qur'an › Follow the reciter word by word. It also needs
    /// speech recognition permission, which is asked for in Settings or by
    /// live recitation, never when pressing play.
    var isEnabled: Bool {
        (UserDefaults.standard.object(forKey: Self.settingKey) as? Bool ?? true)
            && SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    private struct Job {
        let key: String
        let url: URL
        let tokens: [RecitationTracker.Token]
        let hints: [String]
        let letters: [Int]
    }

    private var timings: [String: WordTimings] = [:]
    private var unavailable: Set<String> = []
    private var queue: [Job] = []
    private var working: String?
    private var current: (item: RecitationItem, key: String?)?

    private init() {}

    /// The player moved to another ayah (or stopped).
    func itemChanged(to item: RecitationItem?, upcoming: [RecitationItem]) {
        let highlights = WordHighlights.shared
        let listening = LiveRecitation.shared.isListening
        guard let item, case .verse(let surah, let verse) = item else {
            current = nil
            queue = []
            if !listening { highlights.setCurrent(nil) }
            highlights.setBand(nil)
            return
        }
        let displayed = QuranStore.shared.verse(VerseReference(surah: surah, verse: verse))
        highlights.setBand(displayed.map { VerseKey(surah: $0.surah, verse: $0.number) })
        current = (item, key(for: item))
        if !listening { highlights.setCurrent(nil) }
        // Align this ayah and the next two, one at a time, this one first.
        queue = []
        guard isEnabled else { return }
        for next in [item] + upcoming.prefix(2) { enqueue(next) }
        pump()
    }

    /// Called about 20 times a second while audio plays.
    func playback(at time: Double, of item: RecitationItem) {
        guard !LiveRecitation.shared.isListening, let current, current.item == item,
              case .verse(let surah, let verse) = item,
              let key = current.key, let timing = timings[key],
              let displayed = QuranStore.shared.verse(VerseReference(surah: surah, verse: verse)) else { return }
        guard let index = timing.word(at: time) else { return }
        WordHighlights.shared.setCurrent(WordID(surah: displayed.surah, verse: displayed.number, index: index))
    }

    /// Forgets the session's results (the setting changed). Aligned ayat stay
    /// cached on disk.
    func reset() {
        timings = [:]
        unavailable = []
        queue = []
        if !LiveRecitation.shared.isListening { WordHighlights.shared.setCurrent(nil) }
    }

    private func key(for item: RecitationItem) -> String? {
        guard case .verse(let surah, let verse) = item else { return nil }
        let reciter = RecitationPlayer.shared.reciter
        return "\(reciter.id)|\(QuranStore.shared.edition.rawValue)|\(surah):\(verse)"
    }

    private func enqueue(_ item: RecitationItem) {
        let store = QuranStore.shared
        guard case .verse(let surah, let verse) = item, let key = key(for: item),
              timings[key] == nil, !unavailable.contains(key), working != key,
              !queue.contains(where: { $0.key == key }),
              let displayed = store.verse(VerseReference(surah: surah, verse: verse)) else { return }
        let words = QuranWords.shared.words(for: displayed, edition: store.edition)
        let text = words.text as NSString
        queue.append(Job(key: key,
                         url: RecitationPlayer.shared.audioURL(for: item),
                         tokens: RecognitionForms.tokens(for: [words], edition: store.edition),
                         hints: words.words.map { RecitationText.withoutMarks(text.substring(with: $0.range)) },
                         letters: words.words.map { max($0.normalized.count, 1) }))
    }

    private func pump() {
        guard working == nil, !queue.isEmpty else { return }
        let job = queue.removeFirst()
        working = job.key
        Task {
            let result = await WordTimingAligner.timings(for: job.url, key: job.key, tokens: job.tokens,
                                                         hints: job.hints, letters: job.letters)
            working = nil
            if let result { timings[job.key] = result } else { unavailable.insert(job.key) }
            pump()
        }
    }
}

/// Aligns one ayah recording with its words, on the device.
enum WordTimingAligner {
    /// Minimum share of words that must be placed by recognition.
    static let requiredShare = 0.6

    static func timings(for url: URL, key: String, tokens: [RecitationTracker.Token],
                        hints: [String], letters: [Int]) async -> WordTimings? {
        guard !tokens.isEmpty, letters.count == tokens.count else { return nil }
        let cacheFile = cacheURL(for: key)
        if let data = try? Data(contentsOf: cacheFile),
           let cached = try? JSONDecoder().decode(WordTimings.self, from: data), cached.starts.count == tokens.count {
            return cached
        }
        // Only on the device: the recording is never sent anywhere.
        guard SFSpeechRecognizer.authorizationStatus() == .authorized,
              let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ar-SA")),
              recognizer.isAvailable, recognizer.supportsOnDeviceRecognition,
              let download = try? await URLSession.shared.download(from: url) else { return nil }
        let file = download.0
        // The recogniser reads audio files by their extension.
        let audio = file.deletingPathExtension().appendingPathExtension(url.pathExtension.isEmpty ? "mp3" : url.pathExtension)
        do {
            try FileManager.default.moveItem(at: file, to: audio)
        } catch {
            try? FileManager.default.removeItem(at: file)
            return nil
        }
        defer { try? FileManager.default.removeItem(at: audio) }

        let duration = (try? await AVURLAsset(url: audio).load(.duration).seconds) ?? 0
        guard let segments = await recognize(audio, with: recognizer, hints: hints,
                                             timeout: max(30, duration * 3)), !segments.isEmpty else { return nil }
        let end = max(duration, segments.last.map { $0.start + $0.length } ?? 0)

        let pairs = RecitationTracker.matchedPairs(tokens: tokens, heard: segments.map(\.text))
        let anchors = Dictionary(pairs.map { ($0.token, segments[$0.heard].start) }, uniquingKeysWith: min)
        guard anchors.count >= 2, Double(anchors.count) >= Double(tokens.count) * requiredShare,
              isInOrder(anchors) else { return nil }

        let result = WordTimings(starts: fill(anchors: anchors, count: tokens.count, letters: letters, duration: end),
                                 anchored: anchors.count)
        try? FileManager.default.createDirectory(at: cacheFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(result).write(to: cacheFile)
        return result
    }

    /// Placed words must follow each other in time, or the alignment is wrong.
    static func isInOrder(_ anchors: [Int: Double]) -> Bool {
        let times = anchors.keys.sorted().map { anchors[$0]! }
        return zip(times, times.dropFirst()).allSatisfy { $0 <= $1 }
    }

    /// Start times for every word: placed words keep their time; the others
    /// share the time between their placed neighbours in proportion to their
    /// letters (from the start of the recording before the first placed word,
    /// to its end after the last).
    static func fill(anchors: [Int: Double], count: Int, letters: [Int], duration: Double) -> [Double] {
        var starts = Array(repeating: 0.0, count: count)
        let placed = anchors.keys.filter { $0 >= 0 && $0 < count }.sorted()
        guard let first = placed.first, let last = placed.last, letters.count == count else { return starts }

        /// Spreads words `range` over `from..<to`, by letters.
        func spread(_ range: Range<Int>, from start: Double, to end: Double) {
            let total = Double(max(letters[range].reduce(0, +), 1))
            var time = start
            for index in range {
                starts[index] = time
                time += max(end - start, 0) * Double(letters[index]) / total
            }
        }

        if first > 0 { spread(0..<first, from: 0, to: anchors[first]!) }
        for (a, b) in zip(placed, placed.dropFirst()) { spread(a..<b, from: anchors[a]!, to: anchors[b]!) }
        spread(last..<count, from: anchors[last]!, to: max(duration, anchors[last]!))
        for index in placed { starts[index] = anchors[index]! }
        // Keep times in order.
        for index in starts.indices.dropFirst() where starts[index] < starts[index - 1] { starts[index] = starts[index - 1] }
        return starts
    }

    private static var cacheFolder: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WordTimings", isDirectory: true)
    }

    private static func cacheURL(for key: String) -> URL {
        let safe = key.map { $0.isLetter || $0.isNumber ? String($0) : "_" }.joined()
        return cacheFolder.appendingPathComponent(safe + ".json")
    }

    /// Deletes every saved alignment ("Erase all data").
    static func removeCache() {
        try? FileManager.default.removeItem(at: cacheFolder)
    }

    private struct Segment {
        let text: String
        let start: Double
        let length: Double
    }

    /// Resumes a continuation exactly once (result, error or timeout).
    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        func run(_ body: () -> Void) {
            lock.lock()
            defer { lock.unlock() }
            guard !done else { return }
            done = true
            body()
        }
    }

    private final class TaskBox: @unchecked Sendable {
        var task: SFSpeechRecognitionTask?
    }

    private static func recognize(_ file: URL, with recognizer: SFSpeechRecognizer, hints: [String],
                                  timeout: Double) async -> [Segment]? {
        let request = SFSpeechURLRecognitionRequest(url: file)
        request.shouldReportPartialResults = false
        request.taskHint = .dictation
        request.requiresOnDeviceRecognition = true
        request.contextualStrings = Array(hints.prefix(100))
        let once = Once()
        let box = TaskBox()
        return await withCheckedContinuation { continuation in
            box.task = recognizer.recognitionTask(with: request) { result, error in
                if let result, result.isFinal {
                    let segments = result.bestTranscription.segments.map {
                        Segment(text: $0.substring, start: $0.timestamp, length: $0.duration)
                    }
                    once.run { continuation.resume(returning: segments) }
                } else if error != nil {
                    once.run { continuation.resume(returning: nil) }
                }
            }
            // Give up if the recogniser never answers.
            Task {
                try? await Task.sleep(for: .seconds(timeout))
                once.run {
                    box.task?.cancel()
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
