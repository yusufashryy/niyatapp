import AVFoundation
import Observation
import SwiftUI

/// Plays the athan: in full when a prayer alert is opened (streamed from
/// Aladhan, from where the muezzin begins), or a muezzin's alert sound as a
/// preview in Settings. One at a time; it stops at the end or with Stop.
@MainActor
@Observable
final class AthanPlayer {
    static let shared = AthanPlayer()

    private(set) var playing: Muezzin?
    /// The alert sound is playing as a preview (no Stop banner for it).
    private(set) var isPreview = false

    private var player: AVPlayer?
    private var endObservers: [NSObjectProtocol] = []
    private var statusObservation: NSKeyValueObservation?

    private init() {}

    /// The whole athan. Without internet, the opening bundled with the app plays instead.
    func play(_ muezzin: Muezzin) {
        start(muezzin, url: muezzin.recordingURL, from: muezzin.startOffset, preview: false)
    }

    /// The alert sound, as you'd hear it when a prayer begins. Tapping again stops it.
    func preview(_ muezzin: Muezzin) {
        if playing == muezzin, isPreview {
            stop()
        } else if let url = Self.alertSoundURL(muezzin) {
            start(muezzin, url: url, from: 0, preview: true)
        }
    }

    func stop() {
        player?.pause()
        player = nil
        statusObservation = nil
        endObservers.forEach(NotificationCenter.default.removeObserver)
        endObservers = []
        guard playing != nil else { return }
        playing = nil
        isPreview = false
        AudioSessionQueue.run {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private static func alertSoundURL(_ muezzin: Muezzin) -> URL? {
        Bundle.main.url(forResource: (muezzin.alertSoundName as NSString).deletingPathExtension, withExtension: "caf")
    }

    private func start(_ muezzin: Muezzin, url: URL, from offset: TimeInterval, preview: Bool) {
        stop()
        RecitationPlayer.shared.stop()
        AudioSessionQueue.run {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try? AVAudioSession.sharedInstance().setActive(true)
        }
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        let center = NotificationCenter.default
        endObservers = [
            center.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.stop() }
            },
            center.addObserver(forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.fallBack(from: muezzin, preview: preview) }
            },
        ]
        // A stream that can't load (no internet, server down) plays the bundled opening.
        statusObservation = item.observe(\.status) { [weak self] item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor in self?.fallBack(from: muezzin, preview: preview) }
        }
        if offset > 0 {
            player.seek(to: CMTime(seconds: offset, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        }
        player.play()
        self.player = player
        playing = muezzin
        isPreview = preview
    }

    private func fallBack(from muezzin: Muezzin, preview: Bool) {
        guard !preview, playing == muezzin, let url = Self.alertSoundURL(muezzin) else {
            stop()
            return
        }
        start(muezzin, url: url, from: 0, preview: false)
    }
}

/// While an athan plays in full: who is calling, and a Stop button.
struct AthanNowPlaying: View {
    @State private var athan = AthanPlayer.shared

    var body: some View {
        if let muezzin = athan.playing, !athan.isPreview {
            HStack(spacing: 12) {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(Palette.highlight)
                    .symbolEffect(.variableColor.iterative, options: .repeating)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Athan").font(.subheadline.weight(.bold))
                    Text(muezzin.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                Button {
                    athan.stop()
                } label: {
                    Label("Stop", systemImage: "stop.fill").font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.pressable)
                .haptic(.impact(weight: .light), trigger: athan.playing)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .glassEffect(.regular.tint(Palette.glow.opacity(0.4)), in: .capsule)
            .padding(.horizontal, 16)
            // Below the navigation bar, so Back and the title stay reachable.
            .padding(.top, 56)
            .readableWidth(600)
            .transition(.move(edge: .top).combined(with: .opacity))
            .accessibilityElement(children: .contain)
        }
    }
}
