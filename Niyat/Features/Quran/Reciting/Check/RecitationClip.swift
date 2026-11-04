import AVFoundation
import Foundation

/// Keeps the microphone audio since the last pause, at 16 kHz mono, in
/// memory only, so the part just recited can be sent to the recitation check.
/// Filled on the audio thread; cut on the main thread.
final class RecitationClipRecorder: @unchecked Sendable {
    static let sampleRate = 16_000.0
    /// The server's limit.
    static let maxSeconds = 45.0

    private let lock = NSLock()
    private var samples: [Int16] = []
    private var voiced = 0
    /// Silence since the last voice, in samples. After a short pause the rest
    /// of the silence isn't kept: it would only stretch the part out.
    private var silence = 0
    private static let keptSilence = Int(1.5 * sampleRate)
    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?
    private var isOn = false
    private let output = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: 1, interleaved: true)!

    func setOn(_ on: Bool) {
        lock.lock()
        defer { lock.unlock() }
        isOn = on
        samples = []
        voiced = 0
        silence = 0
    }

    func append(_ buffer: AVAudioPCMBuffer, isVoice: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard isOn, let converted = convert(buffer) else { return }
        if isVoice {
            silence = 0
            voiced += converted.count
        } else {
            silence += converted.count
            // Before any voice, and after a long pause, silence is left out.
            if voiced == 0 || silence > Self.keptSilence { return }
        }
        samples.append(contentsOf: converted)
        let limit = Int(Self.maxSeconds * Self.sampleRate)
        if samples.count > limit { samples.removeFirst(samples.count - limit) }
    }

    /// Everything kept so far, without starting again, and how much of it was voice.
    func peek() -> (samples: [Int16], voiceSeconds: Double) {
        lock.lock()
        defer { lock.unlock() }
        return (samples, Double(voiced) / Self.sampleRate)
    }

    /// The audio since the last cut, if enough of it was voice to be worth checking.
    func cut(minimumVoice seconds: Double = 0.6) -> [Int16]? {
        lock.lock()
        defer { lock.unlock() }
        let clip = samples
        let enough = Double(voiced) / Self.sampleRate >= seconds
        samples = []
        voiced = 0
        silence = 0
        return enough ? clip : nil
    }

    private func convert(_ buffer: AVAudioPCMBuffer) -> [Int16]? {
        if inputFormat != buffer.format {
            inputFormat = buffer.format
            converter = AVAudioConverter(from: buffer.format, to: output)
        }
        guard let converter, buffer.frameLength > 0 else { return nil }
        let ratio = Self.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 32)
        guard let out = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: capacity) else { return nil }
        var given = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if given {
                status.pointee = .noDataNow
                return nil
            }
            given = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let channel = out.int16ChannelData else { return nil }
        return Array(UnsafeBufferPointer(start: channel[0], count: Int(out.frameLength)))
    }
}

/// 16-bit PCM WAV, as the server expects.
enum WAVFile {
    static func data(samples: [Int16], sampleRate: Int = 16_000) -> Data {
        var data = Data(capacity: 44 + samples.count * 2)
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        let bytes = UInt32(samples.count * 2)
        data.append(contentsOf: Array("RIFF".utf8)); append(36 + bytes)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(sampleRate)); append(UInt32(sampleRate * 2)); append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); append(bytes)
        // Apple devices are little-endian, as WAV is.
        samples.withUnsafeBufferPointer { data.append(Data(buffer: $0)) }
        return data
    }
}
