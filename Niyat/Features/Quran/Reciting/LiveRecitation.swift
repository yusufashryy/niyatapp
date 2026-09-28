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

    /// The reciter was found somewhere else in the Qur'an: the reader should
    /// go there (the page or surah), then call `move`.
    struct Jump: Equatable {
        let word: WordID
        let serial: Int
    }

    private(set) var status = Status.idle
    private(set) var jump: Jump?
    /// Set briefly when a word sounded clearly different, for a quick notice.
    private(set) var mistakeNotice: Int = 0
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
    /// Marks from a partial transcript; removed when a revision retracts them.
    @ObservationIgnored private var transientShown: Set<WordID> = []
    @ObservationIgnored private var tapInstalled = false
    /// Requests that ended at once with nothing heard (recogniser failing).
    @ObservationIgnored private var quickFailures = 0
    @ObservationIgnored private var requestStarted = Date.distantPast
    /// Finds a phrase anywhere in the Qur'an (built once per reading, off the main thread).
    @ObservationIgnored private var locator: (edition: QuranEdition, value: QuranLocator)?
    @ObservationIgnored private var buildingLocator = false
    @ObservationIgnored private var lastJumpGeneration = -1
    /// A place found elsewhere, waiting for the next words to confirm it.
    @ObservationIgnored private var jumpCandidate: (index: Int, heard: Int)?

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
        prepareLocator()
        prepare(verses: verses, at: start, searchingAhead: searchingAhead)
        isOnDevice = recognizer.supportsOnDeviceRecognition
        RecitationPlayer.shared.stop()
        do {
            try await AudioSessionQueue.perform {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.record, mode: .measurement, options: .duckOthers)
                try session.setActive(true, options: .notifyOthersOnDeactivation)
            }
            // Stopped while the microphone was being switched on.
            guard status == .starting else {
                Self.deactivateSession()
                return
            }
            // A microphone with no usable format (in a call, or none at all)
            // would crash installTap instead of throwing.
            let format = engine.inputNode.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                Self.deactivateSession()
                status = .unavailable("The microphone isn't available right now. End any call or recording and try again.")
                return
            }
            Self.installTap(on: engine.inputNode, sending: requests)
            tapInstalled = true
            engine.prepare()
            try engine.start()
        } catch {
            if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
            engine.stop()
            Self.deactivateSession()
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

    /// Hands the audio back to other apps (music resumes), off the main thread.
    private static func deactivateSession() {
        AudioSessionQueue.run {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    func stop() {
        guard isListening else { return }
        pauseTimer?.cancel()
        finalTimer?.cancel()
        generation += 1
        task?.cancel()
        task = nil
        requests.set(nil)
        engine.stop()
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        Self.deactivateSession()
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
        transientShown = []
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
        jumpCandidate = nil
    }

    // MARK: Review

    /// Words marked in this session, by verse.
    func review() -> [ReviewVerse] {
        let byVerse = Dictionary(grouping: shownMarks.filter { $0.value != .correct }, by: { $0.key.verseKey })
        return byVerse.keys.sorted().map { key in
            let words = byVerse[key, default: []].sorted { $0.key < $1.key }
                .map { ReviewWord(id: $0.key, text: wordText[$0.key] ?? "", mark: $0.value) }
            return ReviewVerse(key: key, words: words)
        }
    }

    // MARK: Recognition

    private func startRequest() {
        guard let recognizer, tracker != nil else { return }
        pauseTimer?.cancel()
        finalTimer?.cancel()
        task?.cancel()
        generation += 1
        lastHeard = []
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.addsPunctuation = false
        if isOnDevice { request.requiresOnDeviceRecognition = true }
        // Expected words bias dictation toward the answer, hiding substitutions.
        // Keep the transcript independent of the text being checked.
        requests.set(request)
        requestStarted = .now
        task = Self.recognize(request, with: recognizer, generation: generation, requests: requests) { [weak self] words, confidences, isFinal, failed, generation in
            self?.received(words: words, confidences: confidences, isFinal: isFinal, failed: failed, generation: generation)
        }
        let currentGeneration = generation
        pauseTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled, let self, self.generation == currentGeneration else { return }
                // Silence is measured from microphone samples, never from the
                // interval between callbacks (which can lag behind speech).
                if self.requests.hasSpeechPause || Date.now.timeIntervalSince(self.requestStarted) >= 45 {
                    self.endUtterance(generation: currentGeneration)
                    return
                }
            }
        }
    }

    private func received(words: [String], confidences: [Float], isFinal: Bool, failed: Bool, generation: Int) {
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
        if !failed { quickFailures = 0 }
        if !isFinal, words == lastHeard { return }
        if !words.isEmpty { lastHeard = words }
        let result = tracker.update(heard: words.isEmpty ? lastHeard : words,
                                    confidences: isFinal && !failed ? confidences : nil, isFinal: isFinal && !failed)
        if failed { tracker.finishUtterance() }
        self.tracker = tracker
        switch result {
        case .searching: status = .searching
        case .lost: status = .lost
        case .following: status = .following
        }
        if result != .following { lookElsewhere(for: words.isEmpty ? lastHeard : words, tracker: tracker) }
        publish()
        if isFinal {
            finalTimer?.cancel()
            startRequest()
        }
    }

    private func endUtterance(generation: Int) {
        guard generation == self.generation, isListening,
              requests.endCurrentAudio() else { return }
        finalTimer?.cancel()
        finalTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled, let self, generation == self.generation, self.isListening else { return }
            self.tracker?.finishUtterance()
            self.publish()
            self.startRequest()
        }
    }

    // MARK: Anywhere in the Qur'an

    private func prepareLocator() {
        guard locator?.edition != edition, !buildingLocator else { return }
        buildingLocator = true
        let store = QuranStore.shared
        let edition = edition
        let texts = store.surahs.flatMap { store.verses(for: $0.id) }.map { ($0.surah, $0.number, $0.arabic) }
        Task.detached(priority: .utility) {
            let built = QuranLocator(verses: texts.map { VerseWords(surah: $0.0, verse: $0.1, text: $0.2) })
            await MainActor.run {
                LiveRecitation.shared.locator = (edition, built)
                LiveRecitation.shared.buildingLocator = false
            }
        }
    }

    /// Words needed before looking elsewhere in the Qur'an.
    private static let wordsBeforeJumping = 6

    /// Heard words that don't fit the text around the place: if they're
    /// clearly somewhere else (another surah, or far away), go there. Once per
    /// utterance, and only after at least six words, when the next words heard
    /// confirm the same place (so a phrase shared by several surahs, or a
    /// misheard word, doesn't send the reader away).
    private func lookElsewhere(for heard: [String], tracker: RecitationTracker) {
        let count = heard.filter { !RecitationMatcher.normalize($0).isEmpty }.count
        guard lastJumpGeneration != generation, count >= Self.wordsBeforeJumping,
              let locator, locator.edition == edition,
              let index = locator.value.locateIndex(heard) else { return }
        let word = locator.value.ids[index]
        // Close by in the text being followed: the tracker finds it itself.
        if let near = tracker.tokens.firstIndex(where: { $0.id == word }), abs(near - tracker.focus) < 300 {
            jumpCandidate = nil
            return
        }
        // Confirmed: more words heard since, and they carry on from the same place.
        if let candidate = jumpCandidate, count > candidate.heard,
           index >= candidate.index, index - candidate.index <= count - candidate.heard + 3 {
            jumpCandidate = nil
            lastJumpGeneration = generation
            jump = Jump(word: word, serial: (jump?.serial ?? 0) + 1)
        } else {
            jumpCandidate = (index, count)
        }
    }

    /// Sends the tracker's state to the highlight system: the current word,
    /// and marks for words to review. Only changes are sent.
    private func publish() {
        guard let tracker else { return }
        let current = tracker.position.map { tracker.tokens[$0].id }
        WordHighlights.shared.setCurrent(isListening ? current : nil)
        // Only final, confident exact matches turn green. Provisional marks
        // are recomputed, including removal when a transcript is revised.
        let results = tracker.displayResults
        var changes: [WordID: WordMark?] = [:]
        let currentIDs = Set(results.keys.map { tracker.tokens[$0].id })
        for id in transientShown.subtracting(currentIDs) { changes[id] = .some(nil) }
        for (index, result) in results {
            let id = tracker.tokens[index].id
            let mark: WordMark = switch result {
            case .correct: .correct
            case .uncertain: .uncertain
            case .mistake: .mistake
            case .skipped: .skipped
            }
            if shownMarks[id] != mark { changes[id] = .some(mark) }
        }
        transientShown = Set(tracker.provisional.keys.map { tracker.tokens[$0].id })
        if changes.values.contains(where: { $0 == .mistake }) { mistakeNotice += 1 }
        for (id, mark) in changes { shownMarks[id] = mark }
        WordHighlights.shared.updateMarks(changes)
        // Memorisation: words recited so far show through the hidden text.
        var passed: [WordID] = tracker.committed.keys.map { tracker.tokens[$0].id }
        passed += tracker.provisional.compactMap { $0.value == .matched ? tracker.tokens[$0.key].id : nil }
        WordHighlights.shared.reveal(passed)
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
        requests: RequestBox,
        update: @escaping @MainActor ([String], [Float], Bool, Bool, Int) -> Void
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            let segments = result?.bestTranscription.segments ?? []
            // A segment can contain several words. Keep confidence aligned to
            // each split word, including joined/split Arabic phrases.
            let split = segments.flatMap { segment in
                RecitationMatcher.words(segment.substring).map { ($0, segment.confidence) }
            }
            let words = split.map(\.0)
            let confidences = split.map(\.1)
            let isFinal = (result?.isFinal ?? false) || error != nil
            if isFinal { requests.endCurrentAudio(ifCurrent: request) }
            Task { @MainActor in update(words, confidences, isFinal, error != nil, generation) }
        }
    }
}

/// The audio boundary can be tested without calling Apple's speech service.
protocol RecitationAudioRequest: AnyObject {
    func append(_ audioPCMBuffer: AVAudioPCMBuffer)
    func endAudio()
}

extension SFSpeechAudioBufferRecognitionRequest: RecitationAudioRequest {}

/// Hands microphone audio to whichever recognition request is current.
final class RequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var request: (any RecitationAudioRequest)?
    private var draining = false
    private var pending: [AVAudioPCMBuffer] = []
    private var pendingDuration: Double = 0
    private var lastVoice: TimeInterval?
    private var pendingLastVoice: TimeInterval?

    var hasSpeechPause: Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !draining, let lastVoice else { return false }
        return ProcessInfo.processInfo.systemUptime - lastVoice >= 1.1
    }

    func set(_ newRequest: (any RecitationAudioRequest)?) {
        lock.lock()
        defer { lock.unlock() }
        if !draining { request?.endAudio() }
        request = newRequest
        if let newRequest {
            for buffer in pending { newRequest.append(buffer) }
        }
        pending = []
        pendingDuration = 0
        draining = false
        lastVoice = newRequest == nil ? nil : pendingLastVoice
        pendingLastVoice = nil
    }

    /// Keep capturing while the old request produces its final transcript.
    /// A stale callback must never close a newer request.
    @discardableResult
    func endCurrentAudio(ifCurrent current: (any RecitationAudioRequest)? = nil) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let request, !draining, current == nil || current === request else { return false }
        draining = true
        request.endAudio()
        return true
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard request != nil else { return }
        if let samples = buffer.floatChannelData, buffer.frameLength > 0 {
            var energy: Float = 0
            let stride = buffer.stride
            for frame in 0..<Int(buffer.frameLength) {
                let sample = samples[0][frame * stride]
                energy += sample * sample
            }
            if energy / Float(buffer.frameLength) > 0.00001 {
                lastVoice = ProcessInfo.processInfo.systemUptime
                if draining { pendingLastVoice = lastVoice }
            }
        }
        if draining {
            // Audio tap buffers are reused: own a copy until the next request.
            guard let copy = Self.copy(buffer) else { return }
            pending.append(copy)
            pendingDuration += Double(copy.frameLength) / copy.format.sampleRate
            // The final-result timeout is 1.5s. Bound memory even if the UI stalls.
            while pendingDuration > 3, !pending.isEmpty {
                let removed = pending.removeFirst()
                pendingDuration -= Double(removed.frameLength) / removed.format.sampleRate
            }
        } else {
            request?.append(buffer)
        }
    }

    static func copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else { return nil }
        copy.frameLength = buffer.frameLength
        let source = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: buffer.audioBufferList))
        let destination = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for (from, to) in zip(source, destination) {
            guard let input = from.mData, let output = to.mData else { return nil }
            memcpy(output, input, Int(from.mDataByteSize))
        }
        return copy
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
