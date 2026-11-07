import XCTest
@testable import Niyat

/// The built-in recitation model's pure parts: audio features and the word
/// check. Reference values come from scripts/align_quran_asr.py (research/asr-eval
/// branch), whose `kaldi` features reproduced sherpa-onnx's transcripts.
final class RecitationModelTests: XCTestCase {
    /// Half a second of a fixed test signal: two tones and a rising one.
    private func testSignal() -> [Float] {
        (0..<8000).map { i in
            let n = Double(i)
            return Float(0.3 * sin(2 * .pi * 440 * n / 16000) + 0.1 * sin(2 * .pi * 1234 * n / 16000)
                + 0.05 * sin(2 * .pi * 3000 * n / 16000 * (1 + n / 16000)))
        }
    }

    func testMelFiltersMatchTheReference() {
        let mel = RecitationFeatures.melFilters
        XCTAssertEqual(mel.count, 80)
        XCTAssertEqual(mel[0].count, 257)
        XCTAssertEqual(mel.reduce(0) { $0 + $1.filter { $0 > 0 }.count }, 500)
        for (m, k, value) in [(0, 1, 0.02253456), (21, 26, 0.02197685), (62, 124, 0.00079479), (79, 255, 0.00035059)] {
            XCTAssertEqual(Double(mel[m][k]), value, accuracy: 1e-6, "mel[\(m)][\(k)]")
        }
    }

    func testFeaturesMatchTheReference() {
        let features = RecitationFeatures.compute(testSignal())
        XCTAssertEqual(features.frames, 50)
        XCTAssertEqual(features.values.count, 80 * 50)
        let reference: [(Int, Int, Double)] = [
            (0, 0, 4.46152), (5, 3, -0.18005), (20, 10, -0.01724), (40, 25, -0.20205),
            (79, 49, 5.82093), (60, 0, 1.29711), (10, 49, -2.98597),
        ]
        for (mel, frame, value) in reference {
            XCTAssertEqual(Double(features.values[mel * features.frames + frame]), value, accuracy: 0.02,
                           "feature \(mel) at frame \(frame)")
        }
    }

    func testFeaturesOfSilenceAreFinite() {
        let features = RecitationFeatures.compute([Float](repeating: 0, count: 16000))
        XCTAssertTrue(features.values.allSatisfy(\.isFinite))
    }

    // MARK: Word check

    /// A small vocabulary where the model spells words with pieces a fixed
    /// split wouldn't choose, some carrying harakat, one pure harakat.
    private let pieces = ["<unk>", "▁الْ", "حَمْ", "دُ", "▁لِلَّهِ", "▁رَبِّ", "▁العا", "لَمِينَ", "َ", "▁"]
        + "ابتثجحخدذرزسشصضطظعغفقكلمنهوي".map(String.init) + ["<blk>"]

    /// Log-probabilities where each piece is clearly heard in one frame,
    /// with silence (blank) around it, as in real speech.
    private func heard(_ said: [String], vocabulary: RecitationVocabulary, framesPerPiece: Int = 8) -> RecitationLogProbs {
        var values: [Float] = []
        for piece in said {
            let id = pieces.firstIndex(of: piece)!
            for frame in 0..<framesPerPiece {
                var row = [Float](repeating: -9, count: pieces.count)
                row[frame == framesPerPiece / 2 ? id : vocabulary.blank] = -0.01
                values += row
            }
        }
        return RecitationLogProbs(frames: said.count * framesPerPiece, vocabulary: pieces.count, values: values)
    }

    private func letters(_ words: [String]) -> [[[UInt32]]] {
        words.map { [RecitationMatcher.normalize($0).unicodeScalars.map(\.value)] }
    }

    func testCorrectWordsScoreWellInAnySpelling() throws {
        let vocabulary = RecitationVocabulary(pieces: pieces)
        let lp = heard(["▁الْ", "حَمْ", "دُ", "َ", "▁لِلَّهِ", "▁رَبِّ", "▁العا", "لَمِينَ"], vocabulary: vocabulary)
        let vowelled = try XCTUnwrap(RecitationAligner.align(lp, vocabulary: vocabulary,
                                                             words: letters(["الْحَمْدُ", "لِلَّهِ", "رَبِّ", "الْعَالَمِينَ"])))
        XCTAssertTrue(vowelled.allSatisfy { $0.mean > -0.1 }, "\(vowelled.map(\.mean))")
        let bare = try XCTUnwrap(RecitationAligner.align(lp, vocabulary: vocabulary,
                                                         words: letters(["الحمد", "لله", "رب", "العالمين"])))
        XCTAssertTrue(bare.allSatisfy { $0.mean > -0.1 }, "\(bare.map(\.mean))")
    }

    func testSkippedAndWrongWordsScoreBadly() throws {
        let vocabulary = RecitationVocabulary(pieces: pieces)
        let lp = heard(["▁الْ", "حَمْ", "دُ", "▁لِلَّهِ", "▁رَبِّ", "▁العا", "لَمِينَ"], vocabulary: vocabulary)
        let skipped = try XCTUnwrap(RecitationAligner.align(
            lp, vocabulary: vocabulary, words: letters(["الحمد", "لله", "مالك", "رب", "العالمين"])))
        XCTAssertLessThan(skipped[2].mean, -3)
        for index in [0, 1, 3, 4] { XCTAssertGreaterThan(skipped[index].mean, -0.1, "word \(index)") }
        let wrong = try XCTUnwrap(RecitationAligner.align(
            lp, vocabulary: vocabulary, words: letters(["الحمد", "لله", "ربنا", "العالمين"])))
        XCTAssertLessThan(wrong[2].mean, -3)
        XCTAssertGreaterThan(wrong[3].mean, -0.1)
    }

    func testAnyAcceptedSpellingCounts() throws {
        // الرحمن recited, the word offered as both ٱلرَّحْمَٰنِ readings.
        let vocabulary = RecitationVocabulary(pieces: pieces)
        let lp = heard(["▁", "ا", "ل", "ر", "ح", "م", "ن"], vocabulary: vocabulary)
        let withAlif = RecitationMatcher.normalize("ٱلرَّحْمَٰنِ").unicodeScalars.map(\.value)
        let without = RecitationMatcher.normalize("الرحمن").unicodeScalars.map(\.value)
        let scores = try XCTUnwrap(RecitationAligner.align(lp, vocabulary: vocabulary, words: [[withAlif, without]]))
        XCTAssertGreaterThan(scores[0].mean, -0.1)
    }

    func testTooLittleAudioIsNotJudged() {
        let vocabulary = RecitationVocabulary(pieces: pieces)
        let lp = heard(["▁الْ"], vocabulary: vocabulary, framesPerPiece: 1)
        XCTAssertNil(RecitationAligner.align(lp, vocabulary: vocabulary, words: letters(["الحمد", "لله", "رب", "العالمين"])))
    }

    func testGreedyTranscription() {
        let vocabulary = RecitationVocabulary(pieces: pieces)
        let lp = heard(["▁الْ", "حَمْ", "دُ", "▁لِلَّهِ"], vocabulary: vocabulary)
        XCTAssertEqual(vocabulary.greedyWords(lp), ["الْحَمْدُ", "لِلَّهِ"])
    }

    func testTokensFileIsRead() {
        let vocabulary = RecitationVocabulary(tokensFile: "<unk> 0\n▁الْ 1\nحَمْ 2\n<blk> 3\n")
        XCTAssertEqual(vocabulary.pieces, ["<unk>", "▁الْ", "حَمْ", "<blk>"])
        XCTAssertEqual(vocabulary.blank, 3)
        XCTAssertTrue(vocabulary.fillers.contains(0))
    }

    func testTrimmingKeepsSpeechAndDropsLongSilence() {
        let silence = [Float](repeating: 0, count: 16000)
        let speech = (0..<8000).map { Float(0.2 * sin(Double($0) * 0.3)) }
        let trimmed = RecitationAudio.trimmed(silence + speech + silence)
        XCTAssertLessThan(trimmed.count, 8000 + 2 * 3200 + 640)
        XCTAssertGreaterThanOrEqual(trimmed.count, 8000)
    }
}
