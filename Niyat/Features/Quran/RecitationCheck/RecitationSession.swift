import AVFoundation
import Foundation
import Observation
import Speech

/// Listens while you recite and follows along word by word.
///
/// Uses Apple's speech recognition for Arabic, on the iPhone itself whenever
/// the device supports it. Audio is never recorded or stored by Niyat. The
/// words are compared with Tanzil's modern-spelling (Imla'i) Hafs text, which
/// is closest to what the recogniser writes. See docs/research/recitation-checker.md.
@MainActor
@Observable
final class RecitationSession {
    typealias WordState = RecitationMatcher.WordState

    struct CheckVerse {
        let number: Int
        /// As displayed, with harakat.
        let words: [String]
        /// Letters only, for matching.
        let normalized: [String]
    }

    struct VerseResult: Identifiable {
        let number: Int
        let words: [String]
        let states: [WordState]
        var id: Int { number }
        var issues: Int { states.filter { $0 == .different || $0 == .skipped }.count }
    }

    enum Status: Equatable {
        case idle, listening, finished
        case unavailable(String)
    }

    private(set) var surah = 1
    private(set) var verses: [CheckVerse] = []
    private(set) var index = 0
    private(set) var states: [WordState] = []
    private(set) var results: [VerseResult] = []
    private(set) var status = Status.idle
    private(set) var isOnDevice = false
    /// The last few words the recogniser heard, to show it's listening.
    private(set) var heard = ""

    var current: CheckVerse? { verses.indices.contains(index) ? verses[index] : nil }

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ar-SA"))
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private let requests = RequestBox()
    /// Which word the current transcript starts matching from (after a restart).
    @ObservationIgnored private var anchor = 0
    /// Ignores results from recognition tasks that have been replaced.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var settle: Task<Void, Never>?

    // MARK: Setup

    func load(surah: Int, from verse: Int) async {
        stop()
        self.surah = surah
        verses = await RecitationText.verses(for: surah)
        results = []
        index = max(0, min(verse - 1, verses.count - 1))
        prepareVerse()
        status = .idle
    }

    func jump(to verse: Int) {
        guard let target = verses.firstIndex(where: { $0.number == verse }) else { return }
        index = target
        prepareVerse()
        if status == .listening { restartRecognition() }
        if status == .finished { status = .idle }
    }

    private func prepareVerse() {
        settle?.cancel()
        states = Array(repeating: .pending, count: current?.normalized.count ?? 0)
        anchor = 0
        heard = ""
    }

    // MARK: Listening

    func start() async {
        guard let recognizer, recognizer.isAvailable else {
            status = .unavailable("Arabic speech recognition isn't available on this iPhone right now. Check your internet connection, or try again later.")
            return
        }
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speech == .authorized else {
            status = .unavailable("Allow Speech Recognition for Niyat in the Settings app to use this.")
            return
        }
        guard await AVAudioApplication.requestRecordPermission() else {
            status = .unavailable("Allow the Microphone for Niyat in the Settings app to use this.")
            return
        }
        isOnDevice = recognizer.supportsOnDeviceRecognition
        RecitationPlayer.shared.stop()
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            Self.installTap(on: engine.inputNode, sending: requests)
            engine.prepare()
            try engine.start()
        } catch {
            status = .unavailable("Couldn't start the microphone. Close other apps using it and try again.")
            return
        }
        if status == .finished { index = 0; results = []; prepareVerse() }
        status = .listening
        restartRecognition()
    }

    func stop() {
        settle?.cancel()
        generation += 1
        task?.cancel()
        task = nil
        requests.set(nil)
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        if status == .listening { status = .idle }
    }

    /// Moves on without finishing the verse (words not heard are left as they are).
    func skipVerse() {
        finishVerse()
    }

    private func restartRecognition() {
        guard let recognizer, let verse = current else { return }
        task?.cancel()
        generation += 1
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        if isOnDevice { request.requiresOnDeviceRecognition = true }
        // Hints: the words we expect help the recogniser a lot.
        request.contextualStrings = Array(verse.words.map(RecitationText.withoutMarks).prefix(100))
        requests.set(request)
        task = Self.recognize(request, with: recognizer, generation: generation) { [weak self] text, isFinal, generation in
            self?.received(text, isFinal: isFinal, generation: generation)
        }
    }

    private func received(_ text: String?, isFinal: Bool, generation: Int) {
        guard generation == self.generation, status == .listening, let verse = current else { return }
        if let text {
            let heardWords = RecitationMatcher.words(text)
            heard = heardWords.suffix(8).joined(separator: " ")
            let tail = RecitationMatcher.align(expected: Array(verse.normalized[anchor...]),
                                               heard: heardWords.map(RecitationMatcher.normalize))
            states = Array(states.prefix(anchor)) + tail
            if RecitationMatcher.isComplete(states) {
                finishVerse()
                return
            } else if RecitationMatcher.probablyComplete(states) {
                // Give the recogniser a moment to correct the last word.
                settle?.cancel()
                settle = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(1.5))
                    guard !Task.isCancelled, let self, RecitationMatcher.probablyComplete(self.states) else { return }
                    self.finishVerse()
                }
            }
        }
        if isFinal {
            // Recognition stops after a pause or about a minute: carry on from
            // the last word reached.
            anchor = (states.lastIndex { $0 != .pending }).map { $0 + 1 } ?? anchor
            anchor = min(anchor, max(verse.normalized.count - 1, 0))
            restartRecognition()
        }
    }

    private func finishVerse() {
        settle?.cancel()
        guard let verse = current else { return }
        results.removeAll { $0.number == verse.number }
        results.append(VerseResult(number: verse.number, words: verse.words, states: states))
        if index + 1 < verses.count {
            index += 1
            prepareVerse()
            if status == .listening { restartRecognition() }
        } else {
            stop()
            status = .finished
        }
    }

    // MARK: Off the main thread

    /// The microphone tap runs on an audio thread, so it's set up outside the main actor.
    private nonisolated static func installTap(on input: AVAudioInputNode, sending requests: RequestBox) {
        input.removeTap(onBus: 0)
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            requests.append(buffer)
        }
    }

    private nonisolated static func recognize(_ request: SFSpeechAudioBufferRecognitionRequest,
                                              with recognizer: SFSpeechRecognizer, generation: Int,
                                              update: @escaping @MainActor (String?, Bool, Int) -> Void) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = (result?.isFinal ?? false) || error != nil
            Task { @MainActor in update(text, isFinal, generation) }
        }
    }
}

/// Hands microphone audio to whichever recognition request is current.
final class RequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func set(_ newRequest: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock()
        request?.endAudio()
        request = newRequest
        lock.unlock()
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        request?.append(buffer)
        lock.unlock()
    }
}

/// The Hafs text in modern spelling (Tanzil Imla'i, bundled and checksummed),
/// used only for checking recitation.
enum RecitationText {
    private struct Raw: Decodable {
        let verse: Int
        let text: String
    }

    @MainActor private static var cache: [String: [Raw]]?

    @MainActor
    static func verses(for surah: Int) async -> [RecitationSession.CheckVerse] {
        if cache == nil {
            cache = await Task.detached(priority: .userInitiated) { () -> [String: [Raw]] in
                guard let url = Bundle.main.url(forResource: "quran-imlaei", withExtension: "json"),
                      let data = try? Data(contentsOf: url) else { return [:] }
                return (try? JSONDecoder().decode([String: [Raw]].self, from: data)) ?? [:]
            }.value
        }
        guard let cache, let raw = cache[String(surah)] else { return [] }
        let bismillah = cache["1"]?.first?.text ?? ""
        return raw.map { verse in
            var text = verse.text
            // Verse 1 of most surahs starts with the Bismillah in the source; it's
            // recited separately, so it isn't part of the verse being checked.
            if verse.verse == 1, surah != 1, surah != 9,
               let stripped = QuranStore.removingBismillah(from: text, bismillah: bismillah) {
                text = stripped
            }
            let words = RecitationMatcher.words(text)
            return RecitationSession.CheckVerse(number: verse.verse, words: words,
                                                normalized: words.map(RecitationMatcher.normalize))
        }
    }

    /// Removes harakat and Qur'anic marks, keeping letters and spaces.
    static func withoutMarks(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.filter { scalar in
            !(0x064B...0x065F).contains(scalar.value) && scalar.value != 0x0670 && !(0x06D6...0x06ED).contains(scalar.value)
        }))
    }
}
