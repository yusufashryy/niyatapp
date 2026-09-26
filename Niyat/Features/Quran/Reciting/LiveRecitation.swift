import AVFoundation
import Foundation
import Observation
import Speech

/// Extra spellings that live tracking accepts for a few Uthmani words (from
/// Tanzil's Imla'i edition, and letter names for the disjoined letters).
/// Recognition only; see scripts/generate_recognition_forms.py.
@MainActor
enum RecognitionForms {
    private static var byWord: [String: [String]]?

    static func forms(for word: WordID) -> [String] {
        if byWord == nil {
            guard let url = Bundle.main.url(forResource: "recognition-forms", withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let loaded = root["forms"] as? [String: [String]] else {
                byWord = [:]
                return []
            }
            byWord = loaded
        }
        return byWord?["\(word.surah):\(word.verse):\(word.index)"] ?? []
    }

    /// Tracker tokens for some verses of the displayed reading.
    static func tokens(for verses: [VerseWords], edition: QuranEdition) -> [RecitationTracker.Token] {
        verses.flatMap { verse in
            verse.words.map { word in
                // The extra forms were made for the Uthmani text's word
                // positions (the "fewer marks" edition has the same words).
                let extra = edition == .uthmani || edition == .uthmaniMinimal ? forms(for: word.id) : []
                return RecitationTracker.Token(id: word.id, forms: [word.normalized] + extra)
            }
        }
    }
}

/// Live recitation: listens on the current page (or surah) and follows the
/// reciter word by word, marking words for review. Uses Apple's speech
/// recognition for Arabic, on the iPhone itself whenever the device supports
/// it. Audio is never recorded or saved by Niyat.
///
/// Words are only compared, never pronunciation: tajweed is not assessed.
@MainActor
@Observable
final class LiveRecitation {
    static let shared = LiveRecitation()

    enum Status: Equatable {
        case idle
        case starting
        /// Listening for the first words, to find the place.
        case searching
        case following
        /// Heard several words that don't match the text around the place.
        case lost
        case unavailable(String)
    }

    struct ReviewWord: Identifiable, Hashable {
        let id: WordID
        let text: String
        let mark: WordMark
    }

    struct ReviewVerse: Identifiable, Hashable {
        let key: VerseKey
        let words: [ReviewWord]
        var id: VerseKey { key }
    }

    private(set) var status = Status.idle
    private(set) var isOnDevice = false
    /// Which reading the words are being compared with.
    private(set) var edition: QuranEdition = .uthmani

    var isListening: Bool {
        switch status {
        case .starting, .searching, .following, .lost: true
        case .idle, .unavailable: false
        }
    }

    @ObservationIgnored private var tracker: RecitationTracker?
    @ObservationIgnored private var wordText: [WordID: String] = [:]
    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ar-SA"))
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private let requests = RequestBox()
    @ObservationIgnored private var generation = 0
    /// What the current utterance has produced so far (for pauses).
    @ObservationIgnored private var lastHeard: [String] = []
    @ObservationIgnored private var pauseTimer: Task<Void, Never>?
    @ObservationIgnored private var finalTimer: Task<Void, Never>?
    @ObservationIgnored private var shownMarks: [WordID: WordMark] = [:]
    /// Requests that ended at once with nothing heard (recogniser failing).
    @ObservationIgnored private var quickFailures = 0
    @ObservationIgnored private var requestStarted = Date.distantPast

    private init() {}

    // MARK: Starting and stopping

    /// Starts listening. `verses` is the text around the reader's place (the
    /// page and what follows, or the surah); `start` is the word index where
    /// the reader is looking; the first words heard are searched for up to
    /// `searchingAhead` words from there.
    func start(verses: [VerseWords], edition: QuranEdition, at start: Int, searchingAhead: Int) async {
        guard !isListening else { return }
        status = .starting
        guard let recognizer, recognizer.isAvailable else {
            status = .unavailable("Arabic speech recognition isn't available on this iPhone right now. Check your connection, or try again later.")
            return
        }
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speech == .authorized else {
            status = .unavailable("Allow Speech Recognition for Niyat in the Settings app to recite with the app.")
            return
        }
        guard await AVAudioApplication.requestRecordPermission() else {
            status = .unavailable("Allow the Microphone for Niyat in the Settings app to recite with the app.")
            return
        }
        // Stopped (or the page closed) while permission was being asked.
        guard status == .starting else { return }

        self.edition = edition
        prepare(verses: verses, at: start, searchingAhead: searchingAhead)
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
        status = .searching
        startRequest()
    }

    /// The reader moved (another page or verse) while listening: look there.
    func move(verses: [VerseWords], at start: Int, searchingAhead: Int) {
        guard isListening else { return }
        tracker?.finishUtterance()
        publish()
        prepare(verses: verses, at: start, searchingAhead: searchingAhead)
        status = .searching
        startRequest()
    }

    func stop() {
        guard isListening else { return }
        pauseTimer?.cancel()
        finalTimer?.cancel()
        generation += 1
        task?.cancel()
        task = nil
        requests.set(nil)
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        tracker?.finishUtterance()
        publish()
        WordHighlights.shared.setCurrent(nil)
        status = .idle
    }

    /// The "unavailable" message was seen.
    func acknowledge() {
        if case .unavailable = status { status = .idle }
    }

    /// Clears the marks from the last session.
    func clearReview() {
        tracker = nil
        shownMarks = [:]
        WordHighlights.shared.clearRecitation()
    }

    private func prepare(verses: [VerseWords], at start: Int, searchingAhead: Int) {
        // Marks already made stay (see publish): only words judged again change.
        let tokens = RecognitionForms.tokens(for: verses, edition: edition)
        for verse in verses {
            for word in verse.words { wordText[word.id] = (verse.text as NSString).substring(with: word.range) }
        }
        var fresh = RecitationTracker(tokens: tokens)
        fresh.begin(at: start, searchingAhead: searchingAhead)
        tracker = fresh
        lastHeard = []
    }

    // MARK: Review

    /// Words marked in this session, by verse.
    func review() -> [ReviewVerse] {
        let byVerse = Dictionary(grouping: shownMarks, by: { $0.key.verseKey })
        return byVerse.keys.sorted().map { key in
            let words = byVerse[key, default: []].sorted { $0.key < $1.key }
                .map { ReviewWord(id: $0.key, text: wordText[$0.key] ?? "", mark: $0.value) }
            return ReviewVerse(key: key, words: words)
        }
    }

    // MARK: Recognition

    private func startRequest() {
        guard let recognizer, let tracker else { return }
        task?.cancel()
        generation += 1
        lastHeard = []
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        if isOnDevice { request.requiresOnDeviceRecognition = true }
        // The words around the place help the recogniser (up to 100 hints).
        let around = tracker.focus
        let hints = tracker.tokens[max(0, around - 5)..<min(tracker.tokens.count, around + 95)]
            .compactMap { wordText[$0.id].map(RecitationText.withoutMarks) }
        request.contextualStrings = Array(hints)
        requests.set(request)
        requestStarted = .now
        task = Self.recognize(request, with: recognizer, generation: generation) { [weak self] words, confidences, isFinal, generation in
            self?.received(words: words, confidences: confidences, isFinal: isFinal, generation: generation)
        }
    }

    private func received(words: [String], confidences: [Float], isFinal: Bool, generation: Int) {
        guard generation == self.generation, isListening, var tracker else { return }
        if isFinal, words.isEmpty, lastHeard.isEmpty {
            // Nothing heard. After a long silence the recogniser simply times
            // out (listen again); ending at once several times means it can't work.
            if Date.now.timeIntervalSince(requestStarted) < 2 {
                quickFailures += 1
                if quickFailures >= 3 {
                    stop()
                    status = .unavailable("Speech recognition isn't working right now. Please try again later.")
                    return
                }
            }
            startRequest()
            return
        }
        quickFailures = 0
        if !words.isEmpty { lastHeard = words }
        let result = tracker.update(heard: words.isEmpty ? lastHeard : words,
                                    confidences: isFinal ? confidences : nil, isFinal: isFinal)
        self.tracker = tracker
        switch result {
        case .searching: status = .searching
        case .lost: status = .lost
        case .following: status = .following
        }
        publish()
        if isFinal {
            finalTimer?.cancel()
            startRequest()
        } else {
            // A pause of about two seconds ends the utterance: ask the
            // recogniser for its final (confidence-rated) result.
            pauseTimer?.cancel()
            pauseTimer = Task { [weak self] in
                try? await Task.sleep(for: .seconds(1.8))
                guard !Task.isCancelled else { return }
                self?.endUtterance(generation: generation)
            }
        }
    }

    private func endUtterance(generation: Int) {
        guard generation == self.generation, isListening else { return }
        requests.set(nil) // endAudio: the final result follows shortly
        finalTimer?.cancel()
        finalTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled, let self, generation == self.generation, self.isListening else { return }
            // No final result came: judge what was heard, conservatively.
            self.tracker?.finishUtterance()
            self.publish()
            self.startRequest()
        }
    }

    /// Sends the tracker's state to the highlight system: the current word,
    /// and marks for words to review. Only changes are sent.
    private func publish() {
        guard let tracker else { return }
        let current = tracker.position.map { tracker.tokens[$0].id }
        WordHighlights.shared.setCurrent(isListening ? current : nil)
        // Only words this tracker has judged change; a word re-recited
        // correctly loses its mark.
        var changes: [WordID: WordMark?] = [:]
        for (index, result) in tracker.committed {
            let id = tracker.tokens[index].id
            let mark: WordMark? = switch result {
            case .correct: nil
            case .uncertain: .uncertain
            case .mistake: .mistake
            case .skipped: .skipped
            }
            if shownMarks[id] != mark { changes[id] = .some(mark) }
        }
        for (id, mark) in changes { shownMarks[id] = mark }
        WordHighlights.shared.updateMarks(changes)
    }

    // MARK: Off the main thread

    private nonisolated static func installTap(on input: AVAudioInputNode, sending requests: RequestBox) {
        input.removeTap(onBus: 0)
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            requests.append(buffer)
        }
    }

    private nonisolated static func recognize(
        _ request: SFSpeechAudioBufferRecognitionRequest, with recognizer: SFSpeechRecognizer, generation: Int,
        update: @escaping @MainActor ([String], [Float], Bool, Int) -> Void
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            let segments = result?.bestTranscription.segments ?? []
            let words = segments.map(\.substring)
            let confidences = segments.map(\.confidence)
            let isFinal = (result?.isFinal ?? false) || error != nil
            Task { @MainActor in update(words, confidences, isFinal, generation) }
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

enum RecitationText {
    /// Removes harakat and Qur'anic marks, keeping letters and spaces (for
    /// recogniser hints only).
    static func withoutMarks(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.filter { scalar in
            !(0x064B...0x065F).contains(scalar.value) && scalar.value != 0x0670 && !(0x06D6...0x06ED).contains(scalar.value)
        }))
    }
}
