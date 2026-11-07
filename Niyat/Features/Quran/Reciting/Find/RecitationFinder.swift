import AVFoundation
import Foundation
import Observation
import Speech

/// Finds where someone is reciting, anywhere in the Qur'an, like a song
/// finder: listen, then name the surah and ayah. Everything runs on the
/// iPhone: Niyat's built-in recitation model for Hafs, Apple's speech
/// recognition for the other readings.
@MainActor
@Observable
final class RecitationFinder {
    enum State: Equatable {
        case idle
        case listening
        case found(VerseReference)
        case failed(String)
    }

    private(set) var state = State.idle
    private(set) var level: Float = 0

    /// Give up after this much listening.
    static let timeLimit: TimeInterval = 30

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let audio = RecitationAudio()
    @ObservationIgnored private let meter = VoiceMeter()
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var started = Date.distantPast
    @ObservationIgnored private var usesModel = false
    @ObservationIgnored private var search: (words: QuranLocator, letters: QuranLetterSearch)?
    @ObservationIgnored private var confirmation = FindConfirmation()
    // Apple's speech recognition, for the readings the model doesn't know.
    @ObservationIgnored private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ar-SA"))
    @ObservationIgnored private var speechRequest: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var speechTask: SFSpeechRecognitionTask?

    func start() async {
        guard state != .listening else { return }
        LiveRecitation.shared.stop()
        RecitationPlayer.shared.stop()
        let edition = QuranStore.shared.edition
        usesModel = LiveRecitation.modelAvailable(for: edition)
        guard await AVAudioApplication.requestRecordPermission() else {
            state = .failed("Allow the Microphone for Niyat in the Settings app to find a surah by reciting.")
            return
        }
        if usesModel {
            do {
                try await RecitationModel.shared.load()
            } catch {
                state = .failed("Niyat's recitation model couldn't start. Please restart the app and try again.")
                return
            }
        } else {
            guard await prepareSpeech() else { return }
        }
        await prepareSearch()
        do {
            try await AudioSessionQueue.perform {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.record, mode: .measurement, options: .duckOthers)
                try session.setActive(true, options: .notifyOthersOnDeactivation)
            }
            let format = engine.inputNode.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                fail("The microphone isn't available right now. End any call or recording and try again.")
                return
            }
            audio.reset()
            let audio = audio, meter = meter, request = speechRequest
            engine.inputNode.removeTap(onBus: 0)
            engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                _ = meter.measure(buffer)
                audio.append(buffer)
                request?.append(buffer)
            }
            engine.prepare()
            try engine.start()
        } catch {
            fail("Couldn't start the microphone. Close other apps using it and try again.")
            return
        }
        confirmation = FindConfirmation()
        state = .listening
        started = .now
        watch()
    }

    func stop() {
        loop?.cancel()
        speechTask?.cancel()
        speechTask = nil
        speechRequest?.endAudio()
        speechRequest = nil
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        audio.reset()
        level = 0
        AudioSessionQueue.run {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        if state == .listening { state = .idle }
    }

    func reset() {
        stop()
        state = .idle
    }

    private func fail(_ message: String) {
        stop()
        state = .failed(message)
    }

    private func finish(at place: VerseReference) {
        guard state == .listening else { return }
        stop()
        state = .found(place)
    }

    /// Both searches over the reading shown, built once per reading (kept
    /// between visits, so opening the finder again starts at once), off the
    /// main thread.
    private func prepareSearch() async {
        guard search == nil else { return }
        let store = QuranStore.shared
        let edition = store.edition
        if let cached = Self.cachedSearch, cached.edition == edition {
            search = cached.value
            return
        }
        let verses = store.surahs.flatMap { store.verses(for: $0.id) }
            .map { QuranWords.shared.words(for: $0, edition: edition) }
        let built = await Task.detached(priority: .userInitiated) {
            (words: QuranLocator(verses: verses), letters: QuranLetterSearch(verses: verses))
        }.value
        // Only the current reading's search is kept.
        Self.cachedSearch = (edition, built)
        search = built
    }

    private static var cachedSearch: (edition: QuranEdition, value: (words: QuranLocator, letters: QuranLetterSearch))?

    /// Forgets the kept search (memory is low); it's rebuilt next time.
    static func removeCachedSearch() { cachedSearch = nil }

    /// The level for the ring, and (with the model) a look at what's been heard.
    private func watch() {
        loop = Task { [weak self] in
            var decoded = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(150))
                guard let self, !Task.isCancelled, self.state == .listening else { return }
                self.level = self.meter.level
                if Date.now.timeIntervalSince(self.started) > Self.timeLimit {
                    self.fail("Couldn't tell where that is. Try reciting a little longer, from the start of an ayah.")
                    return
                }
                guard self.usesModel else { continue }
                // About every second of new audio, transcribe all of it so far.
                let snapshot = self.audio.snapshot()
                guard snapshot.hasVoice, snapshot.samples.count - decoded >= RecitationFeatures.sampleRate else { continue }
                decoded = snapshot.samples.count
                let samples = RecitationAudio.trimmed(Array(snapshot.samples.suffix(RecitationFeatures.sampleRate * 20)))
                guard let heard = try? await RecitationModel.shared.transcribe(samples) else { continue }
                guard self.state == .listening else { return }
                self.heard(heard.words)
            }
        }
    }

    private func heard(_ words: [String]) {
        guard let search, let place = confirmation.place(for: words, words: search.words, letters: search.letters) else { return }
        finish(at: place)
    }

    // MARK: Apple's speech recognition

    private func prepareSpeech() async -> Bool {
        guard let recognizer, recognizer.isAvailable else {
            state = .failed("Arabic speech recognition isn't available on this iPhone right now. Try again later.")
            return false
        }
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard status == .authorized else {
            state = .failed("Allow Speech Recognition for Niyat in the Settings app to find a surah by reciting.")
            return false
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        speechRequest = request
        speechTask = recognizer.recognitionTask(with: request) { [weak self] result, _ in
            let words = result.map { RecitationMatcher.words($0.bestTranscription.formattedString) } ?? []
            guard !words.isEmpty else { return }
            Task { @MainActor in self?.heard(words) }
        }
        return true
    }
}

/// When to believe a place. Exact word pairs were never wrong in testing, so
/// they're trusted at once; the looser letter search only when it names the
/// same ayah twice in a row (more recitation, same answer).
struct FindConfirmation {
    private var lastGuess: VerseReference?

    mutating func place(for heard: [String], words: QuranLocator, letters: QuranLetterSearch) -> VerseReference? {
        if let index = words.locateIndex(heard) {
            let word = words.ids[index]
            return VerseReference(surah: word.surah, verse: word.verse)
        }
        guard let guess = letters.find(heard)?.verse else { return nil }
        defer { lastGuess = guess }
        return guess == lastGuess ? guess : nil
    }
}

/// How loud the microphone is and when the voice last stopped, measured on
/// the audio thread and read on the main thread.
final class VoiceMeter: @unchecked Sendable {
    private let lock = NSLock()
    private var latest: Float = 0
    private var lastVoice = ProcessInfo.processInfo.systemUptime

    var level: Float {
        lock.lock()
        defer { lock.unlock() }
        return latest
    }

    var secondsSinceVoice: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return ProcessInfo.processInfo.systemUptime - lastVoice
    }

    /// Starts the silence clock again (listening just began).
    func heardVoice() {
        lock.lock()
        defer { lock.unlock() }
        lastVoice = ProcessInfo.processInfo.systemUptime
    }

    /// Returns whether the buffer was louder than silence.
    func measure(_ buffer: AVAudioPCMBuffer) -> Bool {
        guard let samples = buffer.floatChannelData, buffer.frameLength > 0 else { return false }
        var energy: Float = 0
        for frame in 0..<Int(buffer.frameLength) {
            let sample = samples[0][frame * buffer.stride]
            energy += sample * sample
        }
        let mean = energy / Float(buffer.frameLength)
        lock.lock()
        defer { lock.unlock() }
        latest = max(0, min(1, (10 * log10(max(mean, 1e-9)) + 60) / 60))
        let voiced = mean > 0.00001
        if voiced { lastVoice = ProcessInfo.processInfo.systemUptime }
        return voiced
    }
}
