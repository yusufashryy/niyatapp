import Accelerate
import Foundation

/// Turns 16 kHz audio into what the recitation model listens to: 80 log-mel
/// features every 10 ms, normalised per feature.
///
/// This copies kaldi-native-fbank as sherpa-onnx sets it up for NeMo models
/// (the recipe the research self-check matched: 99.2% of letters identical to
/// sherpa-onnx's own transcripts). See `scripts/align_quran_asr.py` on the
/// research/asr-eval branch, `features(mode: "kaldi")`, and the reference
/// values in RecitationModelTests.
enum RecitationFeatures {
    static let sampleRate = 16_000
    static let melCount = 80
    private static let fftSize = 512
    private static let window = 400
    private static let hop = 160
    private static let bins = fftSize / 2 + 1

    /// 80 rows (one per mel band) of `frames` values, row after row, ready to
    /// be the model's [1, 80, frames] input.
    struct Output {
        let values: [Float]
        let frames: Int
    }

    static func compute(_ samples: [Float]) -> Output {
        let n = samples.count
        let frames = max(1, (n + hop / 2) / hop)
        guard n > 0 else { return Output(values: [Float](repeating: 0, count: melCount * frames), frames: frames) }

        // Frames centred on multiples of the hop, edges reflected, pre-emphasis
        // within each frame, then a Hann window.
        var framed = [Float](repeating: 0, count: frames * window)
        let hann = Self.hann
        for f in 0..<frames {
            let start = f * hop + hop / 2 - window / 2
            var previous: Float = 0
            for j in 0..<window {
                var i = start + j
                if i < 0 { i = -i - 1 }
                if i >= n { i = 2 * n - 1 - i }
                let sample = samples[min(max(i, 0), n - 1)]
                let emphasised = j == 0 ? sample * (1 - 0.97) : sample - 0.97 * previous
                previous = sample
                framed[f * window + j] = emphasised * hann[j]
            }
        }

        // Power spectrum: the 400 samples of each frame zero-padded to 512,
        // as one matrix product with the cosine and sine tables.
        var spectrum = [Float](repeating: 0, count: frames * 2 * bins)
        vDSP_mmul(framed, 1, Self.dftBasis, 1, &spectrum, 1, vDSP_Length(frames), vDSP_Length(2 * bins), vDSP_Length(window))
        var power = [Float](repeating: 0, count: frames * bins)
        for f in 0..<frames {
            for k in 0..<bins {
                let re = spectrum[f * 2 * bins + k], im = spectrum[f * 2 * bins + bins + k]
                power[f * bins + k] = re * re + im * im
            }
        }

        // Mel bands (frames x 80), log with Kaldi's floor.
        var mel = [Float](repeating: 0, count: frames * melCount)
        vDSP_mmul(power, 1, Self.melTransposed, 1, &mel, 1, vDSP_Length(frames), vDSP_Length(melCount), vDSP_Length(bins))
        let floor = Float.ulpOfOne
        for i in mel.indices { mel[i] = log(max(mel[i], floor)) }

        // Per-feature normalisation over the clip (sample standard deviation).
        var out = [Float](repeating: 0, count: melCount * frames)
        for m in 0..<melCount {
            var mean: Double = 0
            for f in 0..<frames { mean += Double(mel[f * melCount + m]) }
            mean /= Double(frames)
            var variance: Double = 0
            if frames > 1 {
                for f in 0..<frames {
                    let d = Double(mel[f * melCount + m]) - mean
                    variance += d * d
                }
                variance /= Double(frames - 1)
            }
            let std = frames > 1 ? variance.squareRoot() : 1
            let scale = 1 / (std + 1e-5)
            for f in 0..<frames {
                out[m * frames + f] = Float((Double(mel[f * melCount + m]) - mean) * scale)
            }
        }
        return Output(values: out, frames: frames)
    }

    // MARK: Tables

    private static let hann: [Float] = (0..<window).map { j in
        Float(0.5 - 0.5 * cos(2 * Double.pi * Double(j) / Double(window - 1)))
    }

    /// window x (2 * bins): cosines, then minus sines, of the 512-point DFT.
    private static let dftBasis: [Float] = {
        var basis = [Float](repeating: 0, count: window * 2 * bins)
        for j in 0..<window {
            for k in 0..<bins {
                let angle = 2 * Double.pi * Double(k * j % fftSize) / Double(fftSize)
                basis[j * 2 * bins + k] = Float(cos(angle))
                basis[j * 2 * bins + bins + k] = Float(-sin(angle))
            }
        }
        return basis
    }()

    /// The 80 x 257 Slaney mel filter bank (librosa's default, as NeMo uses).
    static let melFilters: [[Float]] = {
        func hzToMel(_ f: Double) -> Double {
            f >= 1000 ? 15 + log(f / 1000) / (log(6.4) / 27) : 3 * f / 200
        }
        func melToHz(_ m: Double) -> Double {
            m >= 15 ? 1000 * exp((log(6.4) / 27) * (m - 15)) : 200 * m / 3
        }
        let nyquist = Double(sampleRate) / 2
        let fftFreqs = (0..<bins).map { nyquist * Double($0) / Double(bins - 1) }
        let low = hzToMel(0), high = hzToMel(nyquist)
        let melF = (0..<(melCount + 2)).map { melToHz(low + (high - low) * Double($0) / Double(melCount + 1)) }
        return (0..<melCount).map { m in
            let lowerWidth = melF[m + 1] - melF[m], upperWidth = melF[m + 2] - melF[m + 1]
            let norm = 2 / (melF[m + 2] - melF[m])
            return fftFreqs.map { f in
                let lower = (f - melF[m]) / lowerWidth
                let upper = (melF[m + 2] - f) / upperWidth
                return Float(max(0, min(lower, upper)) * norm)
            }
        }
    }()

    /// bins x 80, for the frames x bins power matrix.
    private static let melTransposed: [Float] = {
        var t = [Float](repeating: 0, count: bins * melCount)
        for m in 0..<melCount {
            for k in 0..<bins { t[k * melCount + m] = melFilters[m][k] }
        }
        return t
    }()
}
