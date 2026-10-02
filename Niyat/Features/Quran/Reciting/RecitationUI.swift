import Speech
import SwiftUI

// Live recitation's pieces of UI, shared by the verse-by-verse reader and the
// mushaf pages: the status pill, the first-time explanation and the review.

/// Where live recitation is at, in a few words.
struct LiveRecitationStatus: View {
    /// On light paper.
    var light = false
    @State private var live = LiveRecitation.shared
    @State private var pulse = false
    /// "Sounded different", shown for a moment in bright red.
    @State private var showMistake = false
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        content
            .haptic(.warning, trigger: live.mistakeNotice)
            .onChange(of: live.mistakeNotice) { _, _ in
                withAnimation(.smooth) { showMistake = true }
                hideTask?.cancel()
                hideTask = Task {
                    try? await Task.sleep(for: .seconds(2))
                    guard !Task.isCancelled else { return }
                    withAnimation(.smooth) { showMistake = false }
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if showMistake, live.isListening {
            Label("Sounded different", systemImage: "exclamationmark.circle.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(red: 1.0, green: 0.23, blue: 0.19), in: .capsule)
                .transition(.scale(scale: 0.9).combined(with: .opacity))
                .accessibilityLabel("A word sounded different")
        } else if let text {
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
            .background((light ? Color.black : Color.white).opacity(0.08), in: .capsule)
            .animation(.smooth, value: text)
            .accessibilityElement(children: .combine)
        }
    }

    private var text: String? {
        switch live.status {
        case .starting: "Starting…"
        case .searching: "Listening · start reciting"
        case .following: "Following"
        case .lost: "Can't find your place"
        case .idle, .unavailable: nil
        }
    }

    private var dot: Color {
        switch live.status {
        case .following: .green
        case .lost: .orange
        default: .red
        }
    }
}

/// Words to review after reciting: its own pill that pops up above the
/// controls (verse by verse and mushaf alike), so it's hard to miss.
struct RecitationReviewPill: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "text.badge.checkmark")
                Text(count == 1 ? "1 word to review" : "\(count) words to review")
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .opacity(0.7)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(height: 42)
            .glassEffect(.regular.tint(Palette.control.opacity(0.55)).interactive(), in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.pressable)
        .haptic(.impact(weight: .light), trigger: count > 0) { !$0 && $1 }
        .animation(.smooth, value: count)
        .transition(.scale(scale: 0.8, anchor: .bottom).combined(with: .opacity))
        .accessibilityLabel("Review \(count) marked words")
    }
}

/// Shown the first time the microphone is tapped: what live recitation does,
/// what it doesn't, and what happens to the audio. Permission is only asked
/// for after this.
struct ReciteIntroSheet: View {
    let edition: QuranEdition
    let onStart: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var onDevice = SFSpeechRecognizer(locale: Locale(identifier: "ar-SA"))?.supportsOnDeviceRecognition ?? false

    // v3: recitation is checked by the built-in model (Hafs).
    static let seenKey = "quran.reciteIntroSeen.v3"

    private var usesModel: Bool { LiveRecitation.modelAvailable(for: edition) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    point("text.word.spacing", "Follows you word by word",
                          "Recite from anywhere on the page. Niyat finds your place, highlights the word you're on and turns the pages with you.")
                    point("checkmark.bubble", "Helps you review the words",
                          usesModel
                              ? "When you pause, Niyat checks each word you recited against the audio. Green means the word was clearly there; underlined words were missed, sounded different, or weren't clear. Niyat checks words, not pronunciation: it cannot assess harakat, tajweed or makharij. Check your recitation with a qualified teacher."
                              : "Green means the final transcript matched the written word, not that your pronunciation was correct. While listening, words remain unverified. Underlined words may need review. Speech recognition can miss or change words, and Niyat cannot assess harakat, tajweed or makharij. Check your recitation with a qualified teacher.")
                    point("eye.slash", "Recite from memory",
                          "Hide the text with the eye button. Niyat keeps following and marking words; show the text to see them.")
                    point("lock.shield", "Private",
                          usesModel
                              ? "Your recitation is checked by Niyat's own Qur'an recitation model, on this iPhone. Nothing is sent anywhere, and Niyat never records or saves your recitation."
                              : onDevice
                              ? "Your voice is turned into text by Apple's speech recognition on this iPhone. Nothing is sent anywhere, and Niyat never records or saves your recitation."
                              : "Your voice is turned into text by Apple's speech recognition, which on this iPhone runs on Apple's servers (encrypted, as with dictation). Niyat never records or saves your recitation.")
                    point("book", "Your reading",
                          edition.riwayah == .hafs
                              ? "Words are checked against the \(edition.title) text (\(edition.riwayah.title))."
                              : "Words are checked against the \(edition.riwayah.title) text with Apple's speech recognition (Niyat's recitation model knows Hafs only). It isn't trained on each riwayah, so expect more words marked as uncertain.")
                }
                .padding(20)
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
                .controlSize(.large)
                .padding(20)
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
    }
}

/// Words marked during live recitation, by verse.
struct RecitationReviewSheet: View {
    /// Plays a verse (nil when there's no audio for the reading).
    let onListen: ((VerseKey) -> Void)?
    let onGoTo: (VerseKey) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var store = QuranStore.shared
    @State private var verses: [LiveRecitation.ReviewVerse] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    legend(.mistake, "Sounded different", "Something clearly different was heard.")
                    legend(.skipped, "Possibly skipped", "The words around it were heard, but not this one.")
                    legend(.uncertain, "Couldn't tell", "Not clearly heard. Often the recogniser, not you.")
                } footer: {
                    Text("Niyat compares words, not pronunciation or tajweed, and speech recognition can mishear. Treat these as prompts to check with the text or a teacher.")
                }
                if verses.isEmpty {
                    ContentUnavailableView("Nothing to review", systemImage: "checkmark.seal",
                                           description: Text("Words to double-check appear here after you recite."))
                        .listRowBackground(Color.clear)
                }
                ForEach(verses) { verse in
                    Section {
                        ForEach(verse.words) { word in
                            HStack(spacing: 12) {
                                MarkSwatch(mark: word.mark)
                                Text(title(word.mark))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(word.text)
                                    .font(.quran(size: 26))
                                    .foregroundStyle(.white)
                            }
                            .accessibilityElement(children: .combine)
                        }
                        HStack {
                            if let onListen {
                                Button("Listen", systemImage: "play.fill") { onListen(verse.key) }
                            }
                            Spacer()
                            Button("Go to verse", systemImage: "arrow.right") {
                                dismiss()
                                onGoTo(verse.key)
                            }
                        }
                        .buttonStyle(.borderless)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.accent)
                    } header: {
                        Text("\(store.surah(verse.key.surah)?.transliteration ?? "") \(verse.key.surah):\(verse.key.verse)")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .niyatBackground()
            .navigationTitle("Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                if !verses.isEmpty {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Clear") {
                            LiveRecitation.shared.clearReview()
                            dismiss()
                        }
                    }
                }
            }
        }
        .onAppear { verses = LiveRecitation.shared.review() }
        .presentationDetents([.medium, .large])
    }

    private func title(_ mark: WordMark) -> String {
        switch mark {
        case .correct: "Text matched"
        case .mistake: "Sounded different"
        case .skipped: "Possibly skipped"
        case .uncertain: "Couldn't tell"
        }
    }

    private func legend(_ mark: WordMark, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 12) {
            MarkSwatch(mark: mark)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(.white)
    }
}

/// The underline a mark gets in the text, as a small sample.
struct MarkSwatch: View {
    let mark: WordMark

    var body: some View {
        Canvas { context, size in
            var path = Path()
            path.move(to: CGPoint(x: 2, y: size.height / 2))
            path.addLine(to: CGPoint(x: size.width - 2, y: size.height / 2))
            let style = QuranTextStyle()
            switch mark {
            case .correct:
                context.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: size.height / 2),
                             with: .color(Color(style.correct)))
            case .uncertain:
                context.stroke(path, with: .color(Color(style.uncertain)),
                               style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [0.1, 5]))
            case .mistake:
                context.stroke(path, with: .color(Color(style.mistake)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            case .skipped:
                context.stroke(path, with: .color(Color(style.mistake)),
                               style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [8, 4]))
            }
        }
        .frame(width: 30, height: 10)
        .accessibilityHidden(true)
    }
}
