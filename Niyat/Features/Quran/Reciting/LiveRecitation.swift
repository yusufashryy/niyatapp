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
/// reciter word by word, going to another surah when they start one. For
/// Hafs it uses Niyat's built-in recitation model, on the iPhone; for Warsh
/// and Qalun, Apple's speech recognition. Audio is never recorded or saved.
///
/// It finds and follows; it doesn't judge recitation.
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
        /// Stopped by itself after a long silence; the marks stay.
        case paused
        case unavailable(String)
    }

    /// The reciter was found somewhere else in the Qur'an: the reader should
    /// go there (the page or surah), then call `move`.
    struct Jump: Equatable {
        let word: WordID
        let serial: Int
    }

    private(set) var status = Status.idle
    private(set) var jump: Jump?
    private(set) var isOnDevice = false
    /// Which reading the words are being compared with.
    private(set) var edition: QuranEdition = .uthmani
    /// How loud the microphone is, 0...1, a few times a second (for the Recite button).
    private(set) var level: Float = 0

    /// Silence this long stops listening by itself (the marks stay).
    static let autoPauseSilence: TimeInterval = 20

    var isListening: Bool {
        switch status {
        case .starting, .searching, .following, .lost: true
        case .idle, .paused, .unavailable: false
        }
    }

    @ObservationIgnored private var tracker: RecitationTracker?
    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ar-SA"))
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private let requests = RequestBox()
    @ObservationIgnored private var levelTimer: Task<Void, Never>?
    /// Following with the built-in recitation model (Hafs) instead of Apple's speech.
    @ObservationIgnored private(set) var usesModel = false
    @ObservationIgnored private let modelAudio = RecitationAudio()
    @ObservationIgnored private let modelMeter = VoiceMeter()
    @ObservationIgnored private var modelLoop: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    /// What the current utterance has produced so far (for pauses).
    @ObservationIgnored private var lastHeard: [String] = []
    @ObservationIgnored private var pauseTimer: Task<Void, Never>?
    @ObservationIgnored private var finalTimer: Task<Void, Never>?
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
    /// The ayah given a band because it's being recited (cleared on stop,
    /// unless something else has taken the band since).
    @ObservationIgnored private var bandVerse: VerseKey?

    /// The built-in model is used for this reading (it knows Hafs only).
    static func modelAvailable(for edition: QuranEdition) -> Bool {
        edition.riwayah == .hafs && RecitationModel.isBundled
    }

    private init() {}

    // MARK: Starting and stopping

    /// Starts listening. `verses` is the text around the reader's place (the
    /// page and what follows, or the surah); `start` is the word index where
    /// the reader is looking; the first words heard are searched for up to
    /// `searchingAhead` words from there. `focus` is an ayah already known to
    /// be recited (found by reciting): it's highlighted before the next words.
    func start(verses: [VerseWords], edition: QuranEdition, at start: Int, searchingAhead: Int,
               focus: VerseKey? = nil) async {
        guard !isListening else { return }
        status = .starting
        let model = Self.modelAvailable(for: edition)
        if !model {
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
        }
        guard await AVAudioApplication.requestRecordPermission() else {
            status = .unavailable("Allow the Microphone for Niyat in the Settings app to recite with the app.")
            return
        }
        // Stopped (or the page closed) while permission was being asked.
        guard status == .starting else { return }
        if model {
            do {
                try await RecitationModel.shared.load()
            } catch {
                status = .unavailable("Niyat's recitation model couldn't start. Please restart the app and try again.")
                return
            }
            guard status == .starting else { return }
        }

        self.edition = edition
        prepareLocator()
        prepare(verses: verses, at: start, searchingAhead: searchingAhead)
        usesModel = model
        isOnDevice = model || (recognizer?.supportsOnDeviceRecognition ?? false)
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
            if model {
                Self.installTap(on: engine.inputNode, collecting: modelAudio, meter: modelMeter)
            } else {
                Self.installTap(on: engine.inputNode, sending: requests)
            }
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
        if let focus {
            WordHighlights.shared.focus(focus)
            showBand(on: focus)
        }
        requests.heardVoice()
        modelMeter.heardVoice()
        watchLevel()
        if model { startModelListening() } else { startRequest() }
    }

    /// The reader moved (another page or verse) while listening: look there.
    func move(verses: [VerseWords], at start: Int, searchingAhead: Int) {
        guard isListening else { return }
        tracker?.finishUtterance()
        publish()
        prepare(verses: verses, at: start, searchingAhead: searchingAhead)
        status = .searching
        if usesModel { startModelListening() } else { startRequest() }
    }

    /// Hands the audio back to other apps (music resumes), off the main thread.
    private static func deactivateSession() {
        AudioSessionQueue.run {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    /// Stops listening. `pausing`: stopped by itself after a long silence.
    func stop(pausing: Bool = false) {
        guard isListening else { return }
        modelLoop?.cancel()
        modelAudio.reset()
        levelTimer?.cancel()
        level = 0
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
        if let bandVerse, WordHighlights.shared.band == bandVerse { WordHighlights.shared.setBand(nil) }
        bandVerse = nil
        status = pausing ? .paused : .idle
    }

    /// A band behind the ayah being recited, as for the reciter's recitation.
    private func showBand(on verse: VerseKey) {
        guard verse != bandVerse else { return }
        bandVerse = verse
        WordHighlights.shared.setBand(verse)
    }

    /// The "unavailable" message was seen.
    func acknowledge() {
        switch status {
        case .unavailable, .paused: status = .idle
        default: break
        }
    }

    /// Clears the marks from the last session.
    func clearReview() {
        tracker = nil
        WordHighlights.shared.clearRecitation()
    }

    private func prepare(verses: [VerseWords], at start: Int, searchingAhead: Int) {
        // Marks already made stay (see publish): only words judged again change.
        let tokens = RecognitionForms.tokens(for: verses, edition: edition)
        var fresh = RecitationTracker(tokens: tokens)
        fresh.begin(at: start, searchingAhead: searchingAhead)
        tracker = fresh
        lastHeard = []
        jumpCandidate = nil
    }


    /// The microphone level for the Recite button, about 12 times a second.
    private func watchLevel() {
        levelTimer?.cancel()
        levelTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(80))
                guard let self, !Task.isCancelled else { return }
                let next = self.usesModel ? self.modelMeter.level : self.requests.level
                if abs(next - self.level) > 0.02 { self.level = next }
            }
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
                if self.requests.secondsSinceVoice >= Self.autoPauseSilence {
                    self.stop(pausing: true)
                    return
                }
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
        // The whole ayah stays lit while it's recited, with or without memorisation.
        if isListening, let current { showBand(on: current.verseKey) }
        // Niyat finds and follows the reciter; it doesn't judge words, so no
        // marks are set. Memorisation: words recited so far show through.
        var passed: [WordID] = tracker.committed.keys.map { tracker.tokens[$0].id }
        passed += tracker.provisional.compactMap { $0.value == .matched ? tracker.tokens[$0.key].id : nil }
        WordHighlights.shared.reveal(passed)
    }

    // MARK: The built-in model

    /// The longest stretch transcribed at once; longer recitation is cut here.
    private static let longestUtterance = 20.0

    /// Follows with the model: every moment, transcribes the audio since the
    /// last pause and lines it up with the text, as speech recognition's words are.
    private func startModelListening() {
        modelLoop?.cancel()
        generation += 1
        let current = generation
        modelAudio.reset()
        modelLoop = Task { [weak self] in
            var decoded = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, self.generation == current, self.isListening else { return }
                if self.modelMeter.secondsSinceVoice >= Self.autoPauseSilence {
                    self.stop(pausing: true)
                    return
                }
                let snapshot = self.modelAudio.snapshot()
                guard snapshot.hasVoice else {
                    // Silence before any recitation isn't kept.
                    if snapshot.seconds > 5 { self.modelAudio.reset() }
                    continue
                }
                let isFinal = snapshot.pause || snapshot.seconds >= Self.longestUtterance
                // Nothing new since the last look (and not the end of a stretch yet).
                if !isFinal, snapshot.samples.count - decoded < RecitationFeatures.sampleRate / 4 { continue }
                decoded = snapshot.samples.count
                let audio = RecitationAudio.trimmed(snapshot.samples)
                guard let heard = try? await RecitationModel.shared.transcribe(audio) else { continue }
                guard self.generation == current, self.isListening else { return }
                if isFinal {
                    self.modelAudio.consume(snapshot.samples.count)
                    decoded = 0
                }
                self.modelHeard(heard.words, isFinal: isFinal)
            }
        }
    }

    private func modelHeard(_ words: [String], isFinal: Bool) {
        guard isListening, var tracker else { return }
        guard !words.isEmpty else {
            if isFinal {
                tracker.finishUtterance()
                self.tracker = tracker
                publish()
            }
            return
        }
        let result = tracker.update(heard: words, confidences: isFinal ? Array(repeating: 0, count: words.count) : nil,
                                    isFinal: isFinal)
        self.tracker = tracker
        switch result {
        case .searching: status = .searching
        case .lost: status = .lost
        case .following: status = .following
        }
        if result != .following { lookElsewhere(for: words, tracker: tracker) }
        publish()
        // Each stretch may look elsewhere in the Qur'an again.
        if isFinal {
            lastJumpGeneration = -1
            jumpCandidate = nil
        }
    }

    // MARK: Off the main thread

    private nonisolated static func installTap(on input: AVAudioInputNode, sending requests: RequestBox) {
        input.removeTap(onBus: 0)
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            requests.append(buffer)
        }
    }

    private nonisolated static func installTap(on input: AVAudioInputNode, collecting audio: RecitationAudio,
                                               meter: VoiceMeter) {
        input.removeTap(onBus: 0)
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            _ = meter.measure(buffer)
            audio.append(buffer)
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
    /// Last voice heard in any request (for the auto-pause).
    private var lastVoiceAny = ProcessInfo.processInfo.systemUptime
    private var latestLevel: Float = 0

    /// Seconds since anything louder than silence.
    var secondsSinceVoice: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return ProcessInfo.processInfo.systemUptime - lastVoiceAny
    }

    /// The latest microphone level, 0...1.
    var level: Float {
        lock.lock()
        defer { lock.unlock() }
        return latestLevel
    }

    /// Starts the silence clock again (listening just began).
    func heardVoice() {
        lock.lock()
        defer { lock.unlock() }
        lastVoiceAny = ProcessInfo.processInfo.systemUptime
    }

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

    /// Hands the audio on. Returns whether it was louder than silence.
    @discardableResult
    func append(_ buffer: AVAudioPCMBuffer) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard request != nil else { return false }
        var isVoice = false
        if let samples = buffer.floatChannelData, buffer.frameLength > 0 {
            var energy: Float = 0
            let stride = buffer.stride
            for frame in 0..<Int(buffer.frameLength) {
                let sample = samples[0][frame * stride]
                energy += sample * sample
            }
            let mean = energy / Float(buffer.frameLength)
            // About -60 dB to 0 dB, spread over 0...1.
            latestLevel = max(0, min(1, (10 * log10(max(mean, 1e-9)) + 60) / 60))
            if mean > 0.00001 {
                isVoice = true
                lastVoice = ProcessInfo.processInfo.systemUptime
                lastVoiceAny = lastVoice ?? lastVoiceAny
                if draining { pendingLastVoice = lastVoice }
            }
        }
        if draining {
            // Audio tap buffers are reused: own a copy until the next request.
            guard let copy = Self.copy(buffer) else { return isVoice }
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
        return isVoice
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
