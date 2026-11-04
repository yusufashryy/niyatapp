import AVFoundation
import Foundation
import Observation
import Speech

/// Finds where someone is reciting, anywhere in the Qur'an, like a song
/// finder: listen, then name the surah and ayah. With the recitation check on
/// it asks Quran Muaalem on Niyat's server (better with learners' voices);
/// otherwise it uses Apple's speech recognition and the on-phone locator.
@MainActor
@Observable
final class RecitationFinder {
    enum State: Equatable {
        case idle
        case listening
        /// Several places share these words: the reader picks.
        case choose([VerseReference])
        case found(VerseReference)
        case failed(String)
    }

    private(set) var state = State.idle
    private(set) var level: Float = 0

    /// Give up after this much listening.
    static let timeLimit: TimeInterval = 30
    /// Voice needed before asking the server, and between attempts.
    private static let firstTry = 3.0
    private static let nextTry = 3.0

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let recorder = RecitationClipRecorder()
    @ObservationIgnored private let meter = VoiceMeter()
    @ObservationIgnored private var client: RecitationCheckClient?
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var asking = false
    @ObservationIgnored private var lastTry = 0.0
    @ObservationIgnored private var started = Date.distantPast
    // On the phone, without the server.
    @ObservationIgnored private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ar-SA"))
    @ObservationIgnored private var speechRequest: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var speechTask: SFSpeechRecognitionTask?
    @ObservationIgnored private var locator: QuranLocator?

    /// Whether the server is used (the recitation check is on for this reading).
    var usesServer: Bool { RecitationCheckSettings.isOn(for: QuranStore.shared.edition) }

    func start() async {
        guard state != .listening else { return }
        LiveRecitation.shared.stop()
        RecitationPlayer.shared.stop()
        guard await AVAudioApplication.requestRecordPermission() else {
            state = .failed("Allow the Microphone for Niyat in the Settings app to find a surah by reciting.")
            return
        }
        if usesServer, let server = RecitationCheckSettings.server, let key = RecitationCheckSettings.key {
            client = RecitationCheckClient(server: server, key: key)
        } else {
            client = nil
            guard await prepareSpeech() else { return }
        }
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
            recorder.setOn(true)
            let recorder = recorder, meter = meter, request = speechRequest
            engine.inputNode.removeTap(onBus: 0)
            engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                let isVoice = meter.measure(buffer)
                recorder.append(buffer, isVoice: isVoice)
                request?.append(buffer)
            }
            engine.prepare()
            try engine.start()
        } catch {
            fail("Couldn't start the microphone. Close other apps using it and try again.")
            return
        }
        state = .listening
        started = .now
        lastTry = 0
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
        recorder.setOn(false)
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

    private func finish(with places: [VerseReference]) {
        guard state == .listening, let first = places.first else { return }
        stop()
        state = places.count == 1 ? .found(first) : .choose(places)
    }

    /// The level for the ring, and when to ask the server.
    private func watch() {
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, !Task.isCancelled, self.state == .listening else { return }
                self.level = self.meter.level
                if Date.now.timeIntervalSince(self.started) > Self.timeLimit {
                    self.fail("Couldn't tell where that is. Try reciting a little longer, from the start of an ayah.")
                    return
                }
                self.askIfReady()
            }
        }
    }

    // MARK: With the server

    private func askIfReady() {
        guard let client, !asking else { return }
        let (samples, voice) = recorder.peek()
        let paused = meter.secondsSinceVoice > 0.6
        guard voice >= Self.firstTry, voice - lastTry >= Self.nextTry || (paused && voice > lastTry + 0.5) else { return }
        asking = true
        lastTry = voice
        let wav = WAVFile.data(samples: samples)
        Task {
            defer { asking = false }
            do {
                let answer = try await client.find(wav: wav)
                guard answer.status == .found else { return }
                finish(with: Self.places(from: answer))
            } catch {
                switch error as? RecitationCheckError {
                case .offline: fail("Couldn't reach Niyat's server. Check your connection and try again.")
                case .notSetUp: fail("Finding by reciting isn't set up in this version of Niyat.")
                default: break // busy, or this recording wasn't accepted: the next try may do
                }
            }
        }
    }

    nonisolated static func places(from answer: RecitationFindAnswer) -> [VerseReference] {
        var seen = Set<VerseReference>()
        return answer.places
            .map { VerseReference(surah: $0.start.surah, verse: $0.start.ayah) }
            .filter { seen.insert($0).inserted }
    }

    // MARK: On the phone

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
        if locator == nil {
            let store = QuranStore.shared
            let verses = store.surahs.flatMap { store.verses(for: $0.id) }
                .map { VerseWords(surah: $0.surah, verse: $0.number, text: $0.arabic) }
            locator = await Task.detached(priority: .userInitiated) { QuranLocator(verses: verses) }.value
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        speechRequest = request
        let locator = locator
        speechTask = recognizer.recognitionTask(with: request) { [weak self] result, _ in
            let words = result.map { RecitationMatcher.words($0.bestTranscription.formattedString) } ?? []
            guard let word = locator?.locate(words) else { return }
            let place = VerseReference(surah: word.surah, verse: word.verse)
            Task { @MainActor in self?.finish(with: [place]) }
        }
        return true
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
