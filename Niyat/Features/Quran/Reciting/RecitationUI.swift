import Speech
import SwiftUI

// Live recitation's pieces of UI, shared by the verse-by-verse reader and the
// mushaf pages: the status and the first-time explanation. The row with the
// Recite button is RecitationDock.

/// Where live recitation is at, in a few words.
struct LiveRecitationStatus: View {
    /// On light paper.
    var light = false
    /// Inside another bar: no capsule of its own.
    var plain = false
    @State private var live = LiveRecitation.shared
    @State private var pulse = false

    var body: some View {
        if let text {
            HStack(spacing: 6) {
                Circle()
                    .fill(dot)
                    .frame(width: 7, height: 7)
                    .opacity(pulse ? 0.35 : 1)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulse)
                    .onAppear { pulse = true }
                Text(text)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .contentTransition(.opacity)
            }
            .foregroundStyle(light ? Color.black.opacity(0.75) : .white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background((light ? Color.black : Color.white).opacity(plain ? 0 : 0.08), in: .capsule)
            .animation(.smooth, value: text)
            .accessibilityElement(children: .combine)
        }
    }

    private var text: String? {
        switch live.status {
        case .starting: "Starting…"
        case .searching: "Listening · start reciting"
        case .following: "Following"
        case .lost: "Finding your place…"
        case .paused: "Paused · tap to carry on"
        case .idle, .unavailable: nil
        }
    }

    private var dot: Color {
        switch live.status {
        case .following: .green
        case .lost: .orange
        case .paused, .idle: .gray
        default: .red
        }
    }
}

/// Shown the first time Recite is tapped: what it does and what happens to
/// the audio. Permission is only asked for after this.
struct ReciteIntroSheet: View {
    let edition: QuranEdition
    let onStart: () -> Void
    @Environment(\.dismiss) private var dismiss

    static let seenKey = "quran.reciteIntroSeen.v3"

    /// Whether tapping Recite should show this sheet first.
    static func isNeeded(for edition: QuranEdition) -> Bool {
        !UserDefaults.standard.bool(forKey: seenKey)
    }

    private var usesModel: Bool { LiveRecitation.modelAvailable(for: edition) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    point("text.word.spacing", "Follows you word by word",
                          "Recite from anywhere. Niyat finds your place, lights up the word you're on and turns the pages with you. Start another surah and it goes there.")
                    point("eye.slash", "Recite from memory",
                          "Hide the text with the eye button. The words show again as you recite them.")
                    point("lock.shield", "Private",
                          usesModel
                              ? "Your recitation is followed by Niyat's own recitation model, on this iPhone. Nothing is recorded, saved or sent anywhere."
                              : "Your recitation is followed by Apple's speech recognition (on this iPhone when it supports Arabic, otherwise on Apple's servers, encrypted as with dictation). Niyat never records or saves it.")
                    point("person.2", "Not a teacher",
                          "Niyat finds and follows your place; it doesn't judge your recitation. For pronunciation and tajweed, recite to a qualified teacher.")
                }
                .padding(20)
                .readableWidth()
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    UserDefaults.standard.set(true, forKey: Self.seenKey)
                    dismiss()
                    onStart()
                } label: {
                    Text("Continue").font(.headline).frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(Palette.control)
                .controlSize(.large)
                .padding(20)
                .background { BottomFade() }
            }
            .niyatBackground()
            .navigationTitle("Recite with Niyat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.large])
    }

    private func point(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Palette.highlight)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .combine)
    }
}

/// Behind buttons pinned to the bottom of a scrolling sheet, so text scrolls
/// under them without showing through.
struct BottomFade: View {
    var body: some View {
        LinearGradient(colors: [.black.opacity(0), .black.opacity(0.85), .black], startPoint: .top, endPoint: .bottom)
            .padding(.top, -24)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}
