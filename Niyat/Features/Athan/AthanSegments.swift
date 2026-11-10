import AVFoundation
import Foundation
import Observation

/// The whole athan from the alert itself, without opening Niyat.
///
/// iOS stops any notification sound at 30 seconds, and nothing an app can do
/// lengthens one. So the athan is cut into parts of under 30 seconds, at the
/// muezzin's own pauses, and each part is the sound of its own notification,
/// sent back to back. Only the first shows a banner.
///
/// The rules here are pure, so they're tested.
enum AthanSegments {
    /// Each part stays under iOS's 30-second limit, with room to spare.
    static let longestPart: TimeInterval = 28
    /// A part is never cut shorter than this (unless the athan ends).
    static let shortestPart: TimeInterval = 21
    /// How often the loudness is measured.
    static let frame: TimeInterval = 0.1
    /// Upcoming prayers that get the whole athan. A four-minute athan is
    /// about ten parts, and iOS lets an app queue 64 alerts in all, so the
    /// prayers after these keep the 30-second opening until Niyat is opened
    /// or refreshes in the background.
    static let prayersAhead = 2

    /// Where to cut: after each cut, the quietest moment between the shortest
    /// and longest part. `levels` is the loudness of each `frame` of the athan.
    /// Returns each part's length in seconds; they add up to the whole.
    static func parts(levels: [Float]) -> [TimeInterval] {
        let total = levels.count
        guard total > 0 else { return [] }
        let longest = Int(longestPart / frame), shortest = Int(shortestPart / frame)
        var parts: [TimeInterval] = []
        var start = 0
        while total - start > longest {
            let window = (start + shortest)...(start + longest)
            // The quietest frame, judged with its neighbours so one soft
            // consonant doesn't win over a real pause.
            let cut = window.min { quietness(levels, at: $0) < quietness(levels, at: $1) } ?? window.upperBound
            parts.append(Double(cut - start) * frame)
            start = cut
        }
        parts.append(Double(total - start) * frame)
        return parts
    }

    private static func quietness(_ levels: [Float], at index: Int) -> Float {
        let range = max(index - 2, 0)...min(index + 2, levels.count - 1)
        return range.reduce(0) { $0 + levels[$1] } / Float(range.count)
    }

    /// When each part after the first is sent: the alert's time plus the
    /// parts before it.
    static func followUps(start: Date, parts: [TimeInterval]) -> [(index: Int, date: Date)] {
        var elapsed: TimeInterval = 0
        var result: [(Int, Date)] = []
        for (index, length) in parts.enumerated() {
            if index > 0 { result.append((index, start.addingTimeInterval(elapsed))) }
            elapsed += length
        }
        return result
    }

    static func fileName(_ muezzin: Muezzin, part: Int) -> String { "fullathan-\(muezzin.rawValue)-\(part).caf" }

    static func followUpIdentifier(prayer: PrayerName, dayKey: String, part: Int) -> String {
        "\(followUpPrefix(prayer: prayer, dayKey: dayKey))\(part)"
    }

    /// The start shared by every part of one prayer's athan.
    static func followUpPrefix(prayer: PrayerName, dayKey: String) -> String {
        "\(followUpPrefix)\(prayer.rawValue).\(dayKey)."
    }

    static let followUpPrefix = "athanpart."
}

/// Downloads a muezzin's athan once and cuts it into parts in the app's
/// Library/Sounds folder, where iOS looks for notification sounds.
@MainActor @Observable
final class FullAthanStore {
    static let shared = FullAthanStore()

    enum State: Equatable {
        case missing, preparing, ready
        case failed(String)
    }

    private(set) var states: [Muezzin: State] = [:]
    private nonisolated static let manifestKey = "athan.fullParts"

    private init() {
        for muezzin in Muezzin.allCases { states[muezzin] = Self.parts(for: muezzin) == nil ? .missing : .ready }
    }

    /// Each part's length, if the athan has been prepared and its files are still there.
    nonisolated static func parts(for muezzin: Muezzin) -> [TimeInterval]? {
        guard let all = UserDefaults.standard.dictionary(forKey: manifestKey) as? [String: [Double]],
              let parts = all[muezzin.rawValue], !parts.isEmpty,
              let folder = soundsFolder else { return nil }
        let present = parts.indices.allSatisfy {
            FileManager.default.fileExists(atPath: folder.appendingPathComponent(AthanSegments.fileName(muezzin, part: $0)).path)
        }
        return present ? parts : nil
    }

    private nonisolated static var soundsFolder: URL? {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?.appendingPathComponent("Sounds", isDirectory: true)
    }

    func state(_ muezzin: Muezzin) -> State { states[muezzin] ?? .missing }

    /// Prepares the athan unless it's ready or already on its way. Returns whether it's ready.
    @discardableResult
    func prepare(_ muezzin: Muezzin) async -> Bool {
        switch state(muezzin) {
        case .ready: return true
        case .preparing: return false
        case .missing, .failed: break
        }
        states[muezzin] = .preparing
        do {
            let parts = try await Task.detached(priority: .utility) { try await Self.build(muezzin) }.value
            var all = UserDefaults.standard.dictionary(forKey: Self.manifestKey) as? [String: [Double]] ?? [:]
            all[muezzin.rawValue] = parts
            UserDefaults.standard.set(all, forKey: Self.manifestKey)
            states[muezzin] = .ready
            return true
        } catch {
            states[muezzin] = .failed("Couldn't download the athan. Check your internet and try again.")
            return false
        }
    }

    // MARK: Building

    private enum BuildError: Error { case badResponse, unreadable, noFolder }

    /// Sample rate of the parts: plenty for a voice, and a third of the size of CD quality.
    private nonisolated static let sampleRate: Double = 22_050

    private nonisolated static func build(_ muezzin: Muezzin) async throws -> [TimeInterval] {
        guard let folder = soundsFolder else { throw BuildError.noFolder }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let (downloaded, response) = try await URLSession.shared.download(from: muezzin.recordingURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw BuildError.badResponse }
        // AVAudioFile reads by extension.
        let source = downloaded.deletingPathExtension().appendingPathExtension("mp3")
        try? FileManager.default.removeItem(at: source)
        try FileManager.default.moveItem(at: downloaded, to: source)
        defer { try? FileManager.default.removeItem(at: source) }

        let samples = try monoSamples(of: source, from: muezzin.startOffset)
        let perFrame = Int(sampleRate * AthanSegments.frame)
        let levels: [Float] = stride(from: 0, to: samples.count, by: perFrame).map { start in
            let end = min(start + perFrame, samples.count)
            var sum: Float = 0
            for i in start..<end { sum += samples[i] * samples[i] }
            return (sum / Float(max(end - start, 1))).squareRoot()
        }
        let parts = AthanSegments.parts(levels: levels)

        var offset = 0
        for (index, length) in parts.enumerated() {
            let count = min(Int((length * sampleRate).rounded()), samples.count - offset)
            let url = folder.appendingPathComponent(AthanSegments.fileName(muezzin, part: index))
            try write(Array(samples[offset..<(offset + count)]), to: url)
            try excludeFromBackup(url)
            offset += count
        }
        return parts
    }

    /// The recording as mono samples at `sampleRate`, from `offset` seconds in.
    private nonisolated static func monoSamples(of url: URL, from offset: TimeInterval) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let input = file.processingFormat
        guard let output = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: input, to: output),
              let inBuffer = AVAudioPCMBuffer(pcmFormat: input, frameCapacity: 32_768) else { throw BuildError.unreadable }
        file.framePosition = min(AVAudioFramePosition(offset * input.sampleRate), file.length)

        var samples: [Float] = []
        samples.reserveCapacity(Int(Double(file.length) / input.sampleRate * sampleRate))
        var finished = false
        while true {
            guard let outBuffer = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: 32_768) else { throw BuildError.unreadable }
            var failure: NSError?
            let status = converter.convert(to: outBuffer, error: &failure) { _, inputStatus in
                if finished {
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                do {
                    try file.read(into: inBuffer)
                } catch {
                    inBuffer.frameLength = 0
                }
                if inBuffer.frameLength == 0 {
                    finished = true
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                inputStatus.pointee = .haveData
                return inBuffer
            }
            if let failure { throw failure }
            if let channel = outBuffer.floatChannelData?[0], outBuffer.frameLength > 0 {
                samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(outBuffer.frameLength)))
            }
            if status == .endOfStream || outBuffer.frameLength == 0 { break }
        }
        guard !samples.isEmpty else { throw BuildError.unreadable }
        return samples
    }

    /// The parts are made again from the download when missing (for example
    /// after restoring to a new iPhone), so they needn't fill iCloud backups.
    private nonisolated static func excludeFromBackup(_ url: URL) throws {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }

    /// Prepares the whole athan for the muezzins in use, if the setting is on
    /// and their parts are missing (on a restored iPhone, say). Returns whether any became ready.
    @discardableResult
    func prepareMissing(for settings: AthanSettings) async -> Bool {
        guard settings.fullAthanFromAlert else { return false }
        var prepared = false
        for muezzin in Self.muezzins(in: settings) where state(muezzin) != .ready {
            if await prepare(muezzin) { prepared = true }
        }
        return prepared
    }

    /// The athans in use: the main one and Fajr's, if it has its own.
    nonisolated static func muezzins(in settings: AthanSettings) -> [Muezzin] {
        var list: [Muezzin] = []
        if let muezzin = settings.muezzin { list.append(muezzin) }
        if let fajr = settings.fajrMuezzin, !list.contains(fajr) { list.append(fajr) }
        return list
    }

    /// Writes 16-bit mono PCM in a CAF, one of the formats iOS plays as an alert sound.
    private nonisolated static func write(_ samples: [Float], to url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { throw BuildError.unreadable }
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        try file.write(from: buffer)
    }
}
