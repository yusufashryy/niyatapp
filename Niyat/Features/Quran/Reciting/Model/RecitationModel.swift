import AVFoundation
import Foundation
#if canImport(OnnxRuntimeBindings)
import OnnxRuntimeBindings
#else
import onnxruntime_objc
#endif

/// The built-in Qur'an recitation model: NVIDIA FastConformer CTC fine-tuned
/// on recitations of the Qur'an (TheGreatQuran/QuranKarim-SpeechToText, 8-bit
/// ONNX, CC BY 4.0). Runs on the iPhone with ONNX Runtime; nothing is sent
/// anywhere. Bundled by `make model` (scripts/fetch_recitation_model.sh).
///
/// It was trained on Hafs recitations, so other riwayat use Apple's speech
/// recognition instead.
actor RecitationModel {
    static let shared = RecitationModel()

    static let modelName = "qurankarim-fastconformer-q8"
    static let tokensName = "recitation-model-tokens"

    /// The model files are in the app.
    nonisolated static var isBundled: Bool {
        Bundle.main.url(forResource: modelName, withExtension: "onnx") != nil
            && Bundle.main.url(forResource: tokensName, withExtension: "txt") != nil
    }

    enum Failure: Error { case missing, badOutput }

    private var env: ORTEnv?
    private var session: ORTSession?
    private var featureInput = "audio_signal"
    private var lengthInput: String?
    private var output = "logprobs"
    private(set) var vocabulary: RecitationVocabulary?

    /// Loads the model (once). Takes a moment the first time.
    func load() throws {
        guard session == nil else { return }
        guard let modelURL = Bundle.main.url(forResource: Self.modelName, withExtension: "onnx"),
              let tokensURL = Bundle.main.url(forResource: Self.tokensName, withExtension: "txt") else {
            throw Failure.missing
        }
        let env = try ORTEnv(loggingLevel: .warning)
        let options = try ORTSessionOptions()
        try options.setIntraOpNumThreads(2)
        try options.setGraphOptimizationLevel(.all)
        let session = try ORTSession(env: env, modelPath: modelURL.path, sessionOptions: options)
        let inputs = try session.inputNames()
        featureInput = inputs.first { $0.localizedCaseInsensitiveContains("audio") } ?? inputs.first ?? featureInput
        lengthInput = inputs.first { $0 != featureInput }
        output = try session.outputNames().first ?? output
        vocabulary = RecitationVocabulary(tokensFile: try String(contentsOf: tokensURL, encoding: .utf8))
        self.env = env
        self.session = session
    }

    /// Log-probabilities of every piece in every ~80 ms frame of 16 kHz audio.
    func logProbs(_ samples: [Float]) throws -> RecitationLogProbs {
        try load()
        guard let session else { throw Failure.missing }
        let features = RecitationFeatures.compute(samples)
        var values = features.values
        let data = NSMutableData(bytes: &values, length: values.count * MemoryLayout<Float>.size)
        var inputs = [featureInput: try ORTValue(
            tensorData: data, elementType: .float,
            shape: [1, NSNumber(value: RecitationFeatures.melCount), NSNumber(value: features.frames)])]
        if let lengthInput {
            var length = Int64(features.frames)
            let lengthData = NSMutableData(bytes: &length, length: MemoryLayout<Int64>.size)
            inputs[lengthInput] = try ORTValue(tensorData: lengthData, elementType: .int64, shape: [1])
        }
        let outputs = try session.run(withInputs: inputs, outputNames: [output], runOptions: nil)
        guard let value = outputs[output] else { throw Failure.badOutput }
        let shape = try value.tensorTypeAndShapeInfo().shape.map(\.intValue)
        guard shape.count == 3 else { throw Failure.badOutput }
        let frames = shape[1], vocab = shape[2]
        let raw = try value.tensorData() as Data
        var out = [Float](repeating: 0, count: frames * vocab)
        _ = out.withUnsafeMutableBytes { raw.copyBytes(to: $0) }
        // Log-softmax per frame (the export already gives log-probabilities;
        // this keeps it safe if a model gives raw scores).
        for t in 0..<frames {
            let row = t * vocab
            var peak = -Float.infinity
            for v in 0..<vocab { peak = max(peak, out[row + v]) }
            var sum: Float = 0
            for v in 0..<vocab { sum += exp(out[row + v] - peak) }
            let shift = peak + log(sum)
            for v in 0..<vocab { out[row + v] -= shift }
        }
        return RecitationLogProbs(frames: frames, vocabulary: vocab, values: out)
    }

    /// What was said, as plain words (for following along).
    func transcribe(_ samples: [Float]) throws -> (words: [String], logProbs: RecitationLogProbs) {
        let lp = try logProbs(samples)
        return (vocabulary?.greedyWords(lp) ?? [], lp)
    }

    /// How well the audio fits each expected word (see `RecitationAligner`).
    func check(_ lp: RecitationLogProbs, words: [[[UInt32]]]) -> [RecitationAligner.Score]? {
        guard let vocabulary else { return nil }
        return RecitationAligner.align(lp, vocabulary: vocabulary, words: words)
    }
}

/// Microphone audio for the recitation model: converted to 16 kHz mono as it
/// arrives (on the audio thread), kept for the current utterance only, and
/// never saved.
final class RecitationAudio: @unchecked Sendable {
    struct Snapshot {
        let samples: [Float]
        /// Speech has been heard in this utterance.
        let hasVoice: Bool
        /// The reciter stopped: about a second of quiet after speech.
        let pause: Bool
        var seconds: Double { Double(samples.count) / Double(RecitationFeatures.sampleRate) }
    }

    private let lock = NSLock()
    private var converter: AVAudioConverter?
    private var samples: [Float] = []
    private var lastVoice: TimeInterval?
    private let target = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                       sampleRate: Double(RecitationFeatures.sampleRate), channels: 1, interleaved: false)!
    /// Mean square above which a buffer counts as speech (as RequestBox).
    private static let voiceLevel: Float = 0.00001

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        samples = []
        lastVoice = nil
    }

    /// Drops the first `count` samples (an utterance that has been judged).
    func consume(_ count: Int) {
        lock.lock()
        defer { lock.unlock() }
        samples.removeFirst(min(count, samples.count))
        lastVoice = nil
        if samples.contains(where: { $0 * $0 > Self.voiceLevel }) { lastVoice = ProcessInfo.processInfo.systemUptime }
    }

    func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        let pause = lastVoice.map { ProcessInfo.processInfo.systemUptime - $0 >= 1.1 } ?? false
        return Snapshot(samples: samples, hasVoice: lastVoice != nil, pause: pause)
    }

    /// Called on the audio thread with each microphone buffer.
    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        if converter == nil || converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: target)
        }
        guard let converter, buffer.frameLength > 0 else { return }
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * target.sampleRate / buffer.format.sampleRate) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
        var given = false
        var error: NSError?
        _ = converter.convert(to: out, error: &error) { _, status in
            if given {
                status.pointee = .noDataNow
                return nil
            }
            given = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let channel = out.floatChannelData?[0], out.frameLength > 0 else { return }
        let new = UnsafeBufferPointer(start: channel, count: Int(out.frameLength))
        var energy: Float = 0
        for sample in new { energy += sample * sample }
        if energy / Float(new.count) > Self.voiceLevel { lastVoice = ProcessInfo.processInfo.systemUptime }
        // Nothing is kept from before the reciter starts beyond a second.
        if lastVoice == nil, samples.count > RecitationFeatures.sampleRate {
            samples.removeFirst(samples.count - RecitationFeatures.sampleRate)
        }
        samples.append(contentsOf: new)
    }

    /// The audio without long silence at either end (silence lowers the
    /// model's accuracy: features are normalised over the whole clip), keeping
    /// a fifth of a second either side.
    static func trimmed(_ samples: [Float]) -> [Float] {
        let window = RecitationFeatures.sampleRate / 50
        let margin = RecitationFeatures.sampleRate / 5
        guard samples.count > window * 2 else { return samples }
        func loud(_ start: Int) -> Bool {
            let end = min(start + window, samples.count)
            var energy: Float = 0
            for i in start..<end { energy += samples[i] * samples[i] }
            return energy / Float(end - start) > voiceLevel
        }
        var first = 0
        while first < samples.count, !loud(first) { first += window }
        var last = samples.count - window
        while last > first, !loud(last) { last -= window }
        guard first < samples.count else { return samples }
        let start = max(0, first - margin), end = min(samples.count, last + window + margin)
        return Array(samples[start..<end])
    }
}
