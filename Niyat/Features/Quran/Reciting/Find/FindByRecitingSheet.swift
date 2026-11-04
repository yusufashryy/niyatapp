import AVFoundation
import Speech
import SwiftUI

/// Where to carry on once a recitation was found: the reader opens there and
/// starts following, without asking again.
@MainActor
enum RecitationHandoff {
    static var pending: VerseReference?

    /// The place waiting for this surah, if any (taken once).
    static func take(for surah: Int) -> VerseReference? {
        guard let place = pending, place.surah == surah else { return nil }
        pending = nil
        return place
    }
}

/// "Recite and Niyat finds it": listens, names the surah and ayah, then the
/// Qur'an list opens it there and keeps following.
struct FindByRecitingSheet: View {
    let onFound: (VerseReference) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var finder = RecitationFinder()
    @State private var store = QuranStore.shared
    @State private var step = Step.start

    private enum Step { case start, listening }

    var body: some View {
        NavigationStack {
            content
            .niyatBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        finder.reset()
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.large])
        .onAppear(perform: firstStep)
        .onDisappear { finder.stop() }
        .onChange(of: finder.state) { _, state in
            guard case .found(let place) = state else { return }
            Task {
                try? await Task.sleep(for: .milliseconds(700))
                dismiss()
                onFound(place)
            }
        }
    }

    private var content: some View {
        VStack(spacing: 28) {
            Spacer()
            ring
            VStack(spacing: 8) {
                Text(title)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                    .contentTransition(.opacity)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .accessibilityElement(children: .combine)
            Spacer()
            footer
        }
        .foregroundStyle(.white)
        .padding(.bottom, 20)
        .readableWidth(520)
        .animation(.smooth, value: finder.state)
    }

    private var ring: some View {
        let listening = finder.state == .listening
        let level = reduceMotion ? 0.3 : CGFloat(finder.level)
        return ZStack {
            Circle()
                .stroke(Palette.highlight.opacity(0.5), lineWidth: 4)
                .scaleEffect(listening ? 1.05 + level * 0.25 : 1)
                .opacity(listening ? 1 : 0)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: finder.level)
            Circle().fill(Palette.control.gradient)
            icon
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.black)
        }
        .frame(width: 120, height: 120)
        .padding(20)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var icon: some View {
        switch finder.state {
        case .found: Image(systemName: "checkmark")
        case .failed: Image(systemName: "questionmark")
        default: Image(systemName: "mic.fill")
        }
    }

    private var title: String {
        switch finder.state {
        case .idle: step == .start ? "Recite to find a surah" : "Starting…"
        case .listening: "Listening…"
        case .found(let place): name(place)
        case .failed: "Couldn't find it"
        }
    }

    private var detail: String {
        switch finder.state {
        case .idle where step == .start:
            "Recite a few words from anywhere in the Qur'an. Niyat finds the surah and ayah, opens it there and follows you."
        case .idle, .listening:
            "Recite a few words. Niyat opens the surah as soon as it knows where you are."
        case .found: "Opening…"
        case .failed(let message): message
        }
    }

    @ViewBuilder
    private var footer: some View {
        switch finder.state {
        case .idle where step == .start:
            // A neutral Continue before iOS asks for the microphone.
            wideButton("Continue") { begin() }
        case .failed:
            wideButton("Try again") { Task { await finder.start() } }
        default:
            Text("Works on your iPhone. Nothing you recite is saved or sent anywhere.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
    }

    private func wideButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.headline).frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .tint(Palette.control)
        .controlSize(.large)
        .padding(.horizontal, 24)
    }

    private func name(_ place: VerseReference) -> String {
        "\(store.surah(place.surah)?.transliteration ?? "Surah \(place.surah)") · \(place.surah):\(place.verse)"
    }

    /// The Continue page only when iOS hasn't asked for the microphone yet.
    private func firstStep() {
        if needsAsking {
            step = .start
        } else {
            begin()
        }
    }

    private var needsAsking: Bool {
        if AVAudioApplication.shared.recordPermission == .undetermined { return true }
        return !LiveRecitation.modelAvailable(for: store.edition) && SFSpeechRecognizer.authorizationStatus() == .notDetermined
    }

    private func begin() {
        step = .listening
        Task { await finder.start() }
    }
}

/// The button on the Qur'an list that opens the finder.
struct FindByRecitingButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "mic.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.black)
                .frame(width: 64, height: 64)
                .background(Palette.control.gradient, in: .circle)
                .overlay { Circle().strokeBorder(Palette.highlight.opacity(0.5), lineWidth: 1) }
                .shadow(color: Palette.control.opacity(0.3), radius: 12, y: 3)
                .contentShape(.circle)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Find by reciting")
        .accessibilityHint("Recite a few words and Niyat opens that surah and ayah.")
    }
}
