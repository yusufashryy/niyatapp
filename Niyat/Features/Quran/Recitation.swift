import AVFoundation
import Foundation
import MediaPlayer
import Observation
import SwiftUI

/// A reciter whose verse-by-verse audio is streamed, never bundled. Each
/// recitation's copyright stays with its reciter.
///
/// Most come from the Islamic Network CDN (cdn.islamic.network), which allows
/// free non-commercial use. A few reciters it doesn't carry come from
/// EveryAyah.com (see docs/SOURCES.md).
struct Reciter: Identifiable, Hashable {
    enum Source: Hashable {
        /// Islamic Network, numbered 1...6236 across the Qur'an.
        case islamicNetwork
        /// EveryAyah, one folder per reciter, files named SSSAAA.mp3.
        case everyAyah(folder: String)
    }

    let id: String          // Islamic Network edition (e.g. "ar.alafasy") or our own id
    let name: String
    let arabicName: String
    let style: String
    let bitrate: Int
    var isTranslation = false
    var source = Source.islamicNetwork

    /// `globalAyah` is 1...6236; `surah`/`verse` locate the same verse (Hafs).
    func url(globalAyah: Int, surah: Int, verse: Int) -> URL {
        switch source {
        case .islamicNetwork:
            return URL(string: "https://cdn.islamic.network/quran/audio/\(bitrate)/\(id)/\(globalAyah).mp3")!
        case .everyAyah(let folder):
            return URL(string: String(format: "https://everyayah.com/data/%@/%03d%03d.mp3", folder, surah, verse))!
        }
    }

    static let all: [Reciter] = [
        Reciter(id: "ar.alafasy", name: "Mishary Rashid Alafasy", arabicName: "مشاري راشد العفاسي", style: "Murattal", bitrate: 128),
        Reciter(id: "ar.abdulbasitmurattal", name: "Abdul Basit Abdul Samad", arabicName: "عبد الباسط عبد الصمد", style: "Murattal", bitrate: 192),
        Reciter(id: "ar.abdulsamad", name: "Abdul Basit Abdul Samad", arabicName: "عبد الباسط عبد الصمد", style: "Mujawwad", bitrate: 64),
        Reciter(id: "ar.abdurrahmaansudais", name: "Abdul Rahman Al-Sudais", arabicName: "عبد الرحمن السديس", style: "Murattal", bitrate: 192),
        Reciter(id: "ar.saoodshuraym", name: "Saud Al-Shuraim", arabicName: "سعود الشريم", style: "Murattal", bitrate: 64),
        Reciter(id: "ar.mahermuaiqly", name: "Maher Al-Muaiqly", arabicName: "ماهر المعيقلي", style: "Murattal", bitrate: 128),
        Reciter(id: "ar.husary", name: "Mahmoud Khalil Al-Husary", arabicName: "محمود خليل الحصري", style: "Murattal", bitrate: 128),
        Reciter(id: "ar.husarymujawwad", name: "Mahmoud Khalil Al-Husary", arabicName: "محمود خليل الحصري", style: "Mujawwad", bitrate: 128),
        Reciter(id: "ar.minshawi", name: "Mohamed Siddiq Al-Minshawi", arabicName: "محمد صديق المنشاوي", style: "Murattal", bitrate: 128),
        Reciter(id: "ar.minshawimujawwad", name: "Mohamed Siddiq Al-Minshawi", arabicName: "محمد صديق المنشاوي", style: "Mujawwad", bitrate: 64),
        Reciter(id: "ar.hudhaify", name: "Ali Al-Hudhaify", arabicName: "علي الحذيفي", style: "Murattal", bitrate: 128),
        Reciter(id: "ar.shaatree", name: "Abu Bakr Al-Shatri", arabicName: "أبو بكر الشاطري", style: "Murattal", bitrate: 128),
        Reciter(id: "ar.ahmedajamy", name: "Ahmed Al-Ajamy", arabicName: "أحمد العجمي", style: "Murattal", bitrate: 128),
        Reciter(id: "ar.muhammadayyoub", name: "Muhammad Ayyub", arabicName: "محمد أيوب", style: "Murattal", bitrate: 128),
        Reciter(id: "ar.muhammadjibreel", name: "Muhammad Jibreel", arabicName: "محمد جبريل", style: "Murattal", bitrate: 128),
        Reciter(id: "ar.hanirifai", name: "Hani Al-Rifai", arabicName: "هاني الرفاعي", style: "Murattal", bitrate: 192),
        Reciter(id: "ar.abdullahbasfar", name: "Abdullah Basfar", arabicName: "عبد الله بصفر", style: "Murattal", bitrate: 64),
        Reciter(id: "ar.aymanswoaid", name: "Ayman Suwayd", arabicName: "أيمن سويد", style: "Teaching", bitrate: 64),
        Reciter(id: "ar.ibrahimakhbar", name: "Ibrahim Al-Akhdar", arabicName: "إبراهيم الأخضر", style: "Murattal", bitrate: 32),
        Reciter(id: "everyayah.yasseraldosari", name: "Yasser Al-Dosari", arabicName: "ياسر الدوسري", style: "Murattal", bitrate: 128,
                source: .everyAyah(folder: "Yasser_Ad-Dussary_128kbps")),
        Reciter(id: "en.walk", name: "Ibrahim Walk", arabicName: "", style: "English translation", bitrate: 192, isTranslation: true),
        Reciter(id: "ur.khan", name: "Shamshad Ali Khan", arabicName: "", style: "Urdu translation", bitrate: 64, isTranslation: true),
    ]

    static let `default` = all[0]

    static func with(id: String) -> Reciter {
        all.first { $0.id == id } ?? .default
    }
}

/// What is currently being recited.
enum RecitationItem: Equatable {
    /// The Bismillah recited before verse 1 of a surah (except Al-Fatiha and At-Tawbah).
    case bismillah(surah: Int)
    case verse(surah: Int, verse: Int)

    var surah: Int {
        switch self {
        case .bismillah(let surah), .verse(let surah, _): surah
        }
    }

    var verse: Int? {
        if case .verse(_, let verse) = self { return verse }
        return nil
    }
}

/// Plays recitation verse by verse, following along in the reader.
@MainActor
@Observable
final class RecitationPlayer {
    static let shared = RecitationPlayer()

    private(set) var current: RecitationItem?
    private(set) var isPlaying = false
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    /// Repeat the current verse instead of moving on.
    var repeatVerse: Bool {
        get { repeatVerseValue }
        set {
            repeatVerseValue = newValue
            applyEndBehaviour()
        }
    }
    private var repeatVerseValue = false
    /// Carry on to the next verse automatically (off = stop after each verse).
    var continuous: Bool {
        get { continuousValue }
        set {
            continuousValue = newValue
            UserDefaults.standard.set(newValue, forKey: "quran.continuous")
            applyEndBehaviour()
        }
    }
    private var continuousValue: Bool = UserDefaults.standard.object(forKey: "quran.continuous") as? Bool ?? true

    private(set) var reciter: Reciter = Reciter.with(id: UserDefaults.standard.string(forKey: "quran.reciter") ?? "")

    /// Changes the reciter; if something is playing, it carries on from the same verse.
    func select(_ newReciter: Reciter) {
        guard newReciter != reciter else { return }
        reciter = newReciter
        UserDefaults.standard.set(newReciter.id, forKey: "quran.reciter")
        if let current, isPlaying || isLoading {
            play(surah: current.surah, from: current.verse ?? 1, verseCounts: verseCounts, acrossSurahs: acrossSurahs)
        }
    }

    /// A queue player with the next few verses already loaded, so each verse
    /// starts the instant the previous one ends (no gap between verses).
    @ObservationIgnored private let player = AVQueuePlayer()
    @ObservationIgnored private var itemsByPlayerItem: [ObjectIdentifier: RecitationItem] = [:]
    @ObservationIgnored private var lastEnqueued: RecitationItem?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var currentItemObservation: NSKeyValueObservation?
    @ObservationIgnored private var timeControlObservation: NSKeyValueObservation?
    @ObservationIgnored private var statusObservations: [ObjectIdentifier: NSKeyValueObservation] = [:]
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var verseCounts: [Int] = []
    /// Keep going into the next surah (the mushaf view) rather than stopping
    /// at the end of this one (the surah reader).
    @ObservationIgnored private var acrossSurahs = false
    /// Play just one verse, then stop.
    @ObservationIgnored private var singleVerse = false
    /// How many verses to keep loaded ahead of the one playing.
    private let lookahead = 3

    private init() {
        setUpRemoteCommands()
        timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let status = player.timeControlStatus
            Task { @MainActor in
                self?.isPlaying = status == .playing
                self?.isLoading = status == .waitingToPlayAtSpecifiedRate
            }
        }
        currentItemObservation = player.observe(\.currentItem, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.currentItemChanged() }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil,
                                                             queue: .main) { [weak self] note in
            let finished = note.object as? AVPlayerItem
            Task { @MainActor in self?.itemFinished(finished) }
        }
        // 20 times a second: which word the reciter is on (see ReciterWordSync).
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 20), queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, let playing = self.player.currentItem,
                      let item = self.itemsByPlayerItem[ObjectIdentifier(playing)] else { return }
                ReciterWordSync.shared.playback(at: time.seconds, of: item)
            }
        }
    }

    // MARK: Playback

    /// Starts reciting `surah` from `verse`: to the end of the surah, or on
    /// through the following surahs when `acrossSurahs` is true.
    func play(surah: Int, from verse: Int = 1, verseCounts: [Int], acrossSurahs: Bool = false, only single: Bool = false) {
        self.verseCounts = verseCounts
        self.acrossSurahs = acrossSurahs
        self.singleVerse = single
        guard surah >= 1, surah <= verseCounts.count else { return }
        resetQueue()
        errorMessage = nil
        consecutiveFailures = 0
        let first: RecitationItem = verse == 1 && surah != 1 && surah != 9 && !single
            ? .bismillah(surah: surah) : .verse(surah: surah, verse: verse)
        activateAudioSession()
        enqueue(first)
        topUp()
        applyEndBehaviour()
        player.play()
    }

    func togglePlayPause() {
        if isPlaying {
            player.pause()
        } else if let item = player.currentItem, item.duration.isNumeric,
                  item.currentTime().seconds >= item.duration.seconds - 0.2 {
            // Paused at the end of a verse ("stop after each verse"): go on to the next.
            next()
        } else if current != nil {
            player.play()
        }
        updateNowPlaying()
    }

    func next() {
        guard current != nil else { return }
        if player.items().count <= 1 {
            // Nothing loaded after this one yet (e.g. after pausing at a verse end).
            if let current, let following = item(after: current) {
                play(surah: following.surah, from: following.verse ?? 1, verseCounts: verseCounts, acrossSurahs: acrossSurahs)
            }
            return
        }
        player.advanceToNextItem()
        player.play()
    }

    /// Plays the current verse again from the start.
    func replay() {
        guard current != nil else { return }
        player.seek(to: .zero)
        player.play()
    }

    func previous() {
        guard case .verse(let surah, let verse)? = current, verse > 1 else { return }
        play(surah: surah, from: verse - 1, verseCounts: verseCounts, acrossSurahs: acrossSurahs)
    }

    func stop() {
        resetQueue()
        current = nil
        isPlaying = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        ReciterWordSync.shared.itemChanged(to: nil, upcoming: [])
    }

    private func resetQueue() {
        player.pause()
        player.removeAllItems()
        itemsByPlayerItem.removeAll()
        statusObservations.removeAll()
        lastEnqueued = nil
    }

    /// The verse that follows `item`, or nil at the end.
    private func item(after item: RecitationItem) -> RecitationItem? {
        if singleVerse { return nil }
        switch item {
        case .bismillah(let surah):
            return .verse(surah: surah, verse: 1)
        case .verse(let surah, let verse):
            guard surah <= verseCounts.count else { return nil }
            if verse < verseCounts[surah - 1] { return .verse(surah: surah, verse: verse + 1) }
            guard acrossSurahs, surah < verseCounts.count else { return nil }
            let nextSurah = surah + 1
            return nextSurah == 9 ? .verse(surah: 9, verse: 1) : .bismillah(surah: nextSurah)
        }
    }

    private func enqueue(_ item: RecitationItem) {
        let asset = AVURLAsset(url: audioURL(for: item))
        let playerItem = AVPlayerItem(asset: asset)
        playerItem.preferredForwardBufferDuration = 10
        let key = ObjectIdentifier(playerItem)
        itemsByPlayerItem[key] = item
        statusObservations[key] = playerItem.observe(\.status, options: [.new]) { [weak self] observed, _ in
            guard observed.status == .failed else { return }
            Task { @MainActor in self?.itemFailed(observed) }
        }
        player.insert(playerItem, after: nil)
        lastEnqueued = item
    }

    /// Keeps `lookahead` verses loaded after the one playing.
    private func topUp() {
        while player.items().count < lookahead + 1, let last = lastEnqueued, let following = item(after: last) {
            enqueue(following)
        }
    }

    private func currentItemChanged() {
        guard let playerItem = player.currentItem else {
            // The queue ran out: the surah (or the Qur'an) is finished.
            if current != nil, lastEnqueued.map({ item(after: $0) == nil }) ?? true { stop() }
            return
        }
        current = itemsByPlayerItem[ObjectIdentifier(playerItem)]
        // Forget items that have already played.
        let live = Set(player.items().map(ObjectIdentifier.init))
        itemsByPlayerItem = itemsByPlayerItem.filter { live.contains($0.key) }
        statusObservations = statusObservations.filter { live.contains($0.key) }
        topUp()
        let upcoming = player.items().dropFirst().compactMap { itemsByPlayerItem[ObjectIdentifier($0)] }
        ReciterWordSync.shared.itemChanged(to: current, upcoming: Array(upcoming))
        updateNowPlaying()
    }

    /// Repeat and "stop after each verse" are handled by what the player does
    /// when an item ends; otherwise it glides straight into the next verse.
    private func applyEndBehaviour() {
        player.actionAtItemEnd = repeatVerse || !continuous ? .pause : .advance
    }

    private func itemFinished(_ finished: AVPlayerItem?) {
        guard let finished, finished == player.currentItem else { return }
        consecutiveFailures = 0
        applyEndBehaviour()
        if repeatVerse {
            player.seek(to: .zero)
            player.play()
        } else if !continuous {
            // Stop after this verse, but remember where we are.
            player.pause()
        }
    }

    @ObservationIgnored private var consecutiveFailures = 0

    private func itemFailed(_ failed: AVPlayerItem) {
        consecutiveFailures += 1
        if consecutiveFailures >= 3 {
            stop()
            errorMessage = "Couldn't play the recitation. Check your internet connection and try again."
        } else if failed == player.currentItem {
            // One verse missing on the server shouldn't stop the whole surah.
            player.advanceToNextItem()
            player.play()
        } else {
            player.remove(failed)
            topUp()
        }
    }

    /// The recording of one verse (or the Bismillah) by the selected reciter.
    func audioURL(for item: RecitationItem) -> URL {
        switch item {
        case .bismillah:
            // Al-Fatiha 1:1 is the Bismillah.
            return reciter.url(globalAyah: 1, surah: 1, verse: 1)
        case .verse(let surah, let verse):
            return reciter.url(globalAyah: globalAyahNumber(for: item), surah: surah, verse: verse)
        }
    }

    /// Verses are numbered 1...6236 across the whole Quran on the CDN.
    func globalAyahNumber(for item: RecitationItem) -> Int {
        switch item {
        case .bismillah:
            return 1 // Al-Fatiha 1:1 is the Bismillah
        case .verse(let surah, let verse):
            return verseCounts.prefix(surah - 1).reduce(0, +) + verse
        }
    }

    // MARK: System integration

    private func activateAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func setUpRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.player.play() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.player.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }
    }

    private func updateNowPlaying() {
        guard let current else { return }
        let surahName = QuranStore.shared.surah(current.surah)?.transliteration ?? "Surah \(current.surah)"
        let title: String = switch current {
        case .bismillah: "\(surahName) · Bismillah"
        case .verse(let surah, let verse): "\(surahName) \(surah):\(verse)"
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: reciter.name,
            MPMediaItemPropertyAlbumTitle: "Niyat",
        ]
    }
}

// MARK: - Mini player

/// Floating player shown at the bottom of the reader while recitation plays.
struct RecitationMiniPlayer: View {
    @State private var player = RecitationPlayer.shared
    @State private var showReciters = false

    var body: some View {
        if let current = player.current {
            HStack(spacing: 12) {
                Button { showReciters = true } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(label(for: current))
                            .font(.subheadline.weight(.bold))
                            .contentTransition(.numericText())
                        Text(player.reciter.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.pressable)

                Button { player.repeatVerse.toggle() } label: {
                    Image(systemName: "repeat.1")
                        .foregroundStyle(player.repeatVerse ? Palette.accent : .secondary)
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel(player.repeatVerse ? "Stop repeating verse" : "Repeat verse")

                Button { player.previous() } label: {
                    Image(systemName: "backward.fill").frame(width: 30, height: 32)
                }
                .accessibilityLabel("Previous verse")

                Button { player.replay() } label: {
                    Image(systemName: "gobackward").frame(width: 30, height: 32)
                }
                .accessibilityLabel("Replay verse")

                Button { player.togglePlayPause() } label: {
                    Group {
                        if player.isLoading {
                            ProgressView()
                        } else {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .contentTransition(.symbolEffect(.replace))
                        }
                    }
                    .font(.title3)
                    .frame(width: 40, height: 40)
                }
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

                Button { player.next() } label: {
                    Image(systemName: "forward.fill").frame(width: 32, height: 32)
                }
                .accessibilityLabel("Next verse")

                Button { withAnimation(.smooth) { player.stop() } } label: {
                    Image(systemName: "xmark").font(.footnote.weight(.bold)).frame(width: 28, height: 28)
                }
                .accessibilityLabel("Stop recitation")
            }
            .buttonStyle(.pressable)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassEffect(.regular.tint(Palette.glow.opacity(0.4)).interactive(), in: .capsule)
            .padding(.horizontal, 12)
            .haptic(.selection, trigger: player.repeatVerse)
            .sheet(isPresented: $showReciters) { ReciterPicker() }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func label(for item: RecitationItem) -> String {
        switch item {
        case .bismillah(let surah): "\(surah) · Bismillah"
        case .verse(let surah, let verse): "\(surah):\(verse)"
        }
    }
}

// MARK: - Reciter picker

struct ReciterPicker: View {
    /// true when pushed inside Qur'an settings (no own navigation stack).
    var embedded = false
    @Environment(\.dismiss) private var dismiss
    @State private var player = RecitationPlayer.shared
    @State private var search = ""

    private var filtered: [Reciter] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return Reciter.all }
        return Reciter.all.filter { $0.name.localizedCaseInsensitiveContains(query) || $0.arabicName.contains(query) }
    }

    var body: some View {
        if embedded {
            list
        } else {
            NavigationStack {
                list
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                    }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var list: some View {
            List {
                Section {
                    ForEach(filtered.filter { !$0.isTranslation }) { reciter in row(reciter) }
                } header: {
                    Text("Reciters")
                }
                let translations = filtered.filter(\.isTranslation)
                if !translations.isEmpty {
                    Section {
                        ForEach(translations) { reciter in row(reciter) }
                    } header: {
                        Text("Translation audio")
                    } footer: {
                        Text("Audio streams from the Islamic Network CDN, free for non-commercial use. Each recitation's copyright stays with its reciter.")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .searchable(text: $search, prompt: "Search reciters")
            .navigationTitle("Reciter")
            .navigationBarTitleDisplayMode(.inline)
            .haptic(.selection, trigger: player.reciter)
    }

    private func row(_ reciter: Reciter) -> some View {
        Button {
            player.select(reciter)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(reciter.name).font(.body.weight(.semibold))
                    Text(reciter.style).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if !reciter.arabicName.isEmpty {
                    Text(reciter.arabicName)
                        .font(.calligraphy(size: 18))
                        .foregroundStyle(Palette.highlight)
                }
                Image(systemName: player.reciter == reciter ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(player.reciter == reciter ? Palette.accent : .secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .contentShape(.rect)
        }
        .buttonStyle(.pressable)
        .foregroundStyle(.white)
    }
}
