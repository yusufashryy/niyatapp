import AVFoundation
import Foundation
import MediaPlayer
import Observation
import SwiftUI

/// A reciter available from the Islamic Network audio CDN (cdn.islamic.network),
/// which allows free non-commercial use; each recitation's copyright stays with
/// its reciter. Audio is streamed verse by verse, never bundled.
struct Reciter: Identifiable, Hashable {
    let id: String          // Islamic Network edition, e.g. "ar.alafasy"
    let name: String
    let arabicName: String
    let style: String
    let bitrate: Int
    var isTranslation = false

    func url(forGlobalAyah number: Int) -> URL {
        URL(string: "https://cdn.islamic.network/quran/audio/\(bitrate)/\(id)/\(number).mp3")!
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
    var repeatVerse = false

    private(set) var reciter: Reciter = Reciter.with(id: UserDefaults.standard.string(forKey: "quran.reciter") ?? "")

    /// Changes the reciter; if something is playing, it carries on from the same verse.
    func select(_ newReciter: Reciter) {
        guard newReciter != reciter else { return }
        reciter = newReciter
        UserDefaults.standard.set(newReciter.id, forKey: "quran.reciter")
        if let current, isPlaying || isLoading {
            play(surah: current.surah, from: current.verse ?? 1, verseCounts: verseCounts)
        }
    }

    @ObservationIgnored private let player = AVPlayer()
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var timeControlObservation: NSKeyValueObservation?
    @ObservationIgnored private var queue: [RecitationItem] = []
    @ObservationIgnored private var verseCounts: [Int] = []

    private init() {
        setUpRemoteCommands()
        timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let status = player.timeControlStatus
            Task { @MainActor in
                self?.isPlaying = status == .playing
                self?.isLoading = status == .waitingToPlayAtSpecifiedRate
            }
        }
    }

    // MARK: Playback

    /// Starts reciting `surah` from `verse` to the end of the surah.
    func play(surah: Int, from verse: Int = 1, verseCounts: [Int]) {
        self.verseCounts = verseCounts
        guard surah >= 1, surah <= verseCounts.count else { return }
        var items: [RecitationItem] = []
        if verse == 1, surah != 1, surah != 9 { items.append(.bismillah(surah: surah)) }
        items += (verse...verseCounts[surah - 1]).map { RecitationItem.verse(surah: surah, verse: $0) }
        queue = items
        errorMessage = nil
        activateAudioSession()
        advance()
    }

    func togglePlayPause() {
        if isPlaying { player.pause() } else if current != nil { player.play() }
        updateNowPlaying()
    }

    func next() {
        advance()
    }

    func previous() {
        guard case .verse(let surah, let verse)? = current, verse > 1 else { return }
        play(surah: surah, from: verse - 1, verseCounts: verseCounts)
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        queue = []
        current = nil
        isPlaying = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func advance() {
        guard !queue.isEmpty else {
            stop()
            return
        }
        let item = queue.removeFirst()
        current = item
        load(item)
    }

    private func load(_ item: RecitationItem) {
        let url = reciter.url(forGlobalAyah: globalAyahNumber(for: item))
        let playerItem = AVPlayerItem(url: url)

        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: playerItem,
                                                             queue: .main) { [weak self] _ in
            Task { @MainActor in self?.itemFinished() }
        }
        statusObservation = playerItem.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor in self?.itemFailed() }
        }

        player.replaceCurrentItem(with: playerItem)
        player.play()
        updateNowPlaying()
    }

    private func itemFinished() {
        consecutiveFailures = 0
        if repeatVerse, let current, current.verse != nil {
            player.seek(to: .zero)
            player.play()
        } else {
            advance()
        }
    }

    @ObservationIgnored private var consecutiveFailures = 0

    private func itemFailed() {
        consecutiveFailures += 1
        if consecutiveFailures >= 3 {
            consecutiveFailures = 0
            stop()
            errorMessage = "Couldn't play the recitation. Check your internet connection and try again."
        } else {
            // One verse missing on the server shouldn't stop the whole surah.
            advance()
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
                    Image(systemName: "backward.fill").frame(width: 32, height: 32)
                }
                .accessibilityLabel("Previous verse")

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
    @Environment(\.dismiss) private var dismiss
    @State private var player = RecitationPlayer.shared
    @State private var search = ""

    private var filtered: [Reciter] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return Reciter.all }
        return Reciter.all.filter { $0.name.localizedCaseInsensitiveContains(query) || $0.arabicName.contains(query) }
    }

    var body: some View {
        NavigationStack {
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
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
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
