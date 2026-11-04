import Speech
import SwiftUI

// Live recitation's pieces of UI, shared by the verse-by-verse reader and the
// mushaf pages: the status, the first-time explanation and the review. The
// row with the Recite button is RecitationDock.

/// Where live recitation is at, in a few words.
struct LiveRecitationStatus: View {
    /// On light paper.
    var light = false
    /// Inside another bar: no capsule of its own.
    var plain = false
    @State private var live = LiveRecitation.shared
    @State private var checker = RecitationChecker.shared
    @State private var pulse = false
    /// "Sounded different", shown for a moment in bright red.
    @State private var showMistake = false
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        content
            .haptic(.warning, trigger: live.mistakeNotice + checker.mistakeNotice)
            .onChange(of: live.mistakeNotice + checker.mistakeNotice) { _, _ in
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
        if showMistake, live.isListening || checker.pending > 0 {
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
            .background((light ? Color.black : Color.white).opacity(plain ? 0 : 0.08), in: .capsule)
            .animation(.smooth, value: text)
            .accessibilityElement(children: .combine)
        }
    }

    private var text: String? {
        switch live.status {
        case .starting: return "Starting…"
        case .searching: return "Listening · start reciting"
        case .following:
            if checker.isActive, checker.health == .offline { return "Following · check offline" }
            return checker.pending > 0 ? "Following · checking" : "Following"
        case .lost: return "Can't find your place"
        case .paused: return "Paused · tap to carry on"
        case .idle, .unavailable: return checker.pending > 0 ? "Checking…" : nil
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

/// Shown the first time the microphone is tapped: what live recitation does,
/// what it doesn't, and what happens to the audio. Permission is only asked
/// for after this.
struct ReciteIntroSheet: View {
    let edition: QuranEdition
    let onStart: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var onDevice = SFSpeechRecognizer(locale: Locale(identifier: "ar-SA"))?.supportsOnDeviceRecognition ?? false
    /// After the introduction: the recitation check's AI notice and choice.
    @State private var showsCheck = false

    static let seenKey = "quran.reciteIntroSeen.v2"

    /// Whether tapping Recite should show this sheet first.
    static func isNeeded(for edition: QuranEdition) -> Bool {
        !UserDefaults.standard.bool(forKey: seenKey) || needsCheckChoice(for: edition)
    }

    private static func needsCheckChoice(for edition: QuranEdition) -> Bool {
        RecitationCheckSettings.isAvailable && RecitationCheckSettings.supports(edition) && !RecitationCheckSettings.noticeSeen
    }

    var body: some View {
        NavigationStack {
            Group {
                if showsCheck || UserDefaults.standard.bool(forKey: Self.seenKey) {
                    RecitationCheckChoice { _ in
                        dismiss()
                        onStart()
                    }
                } else {
                    introduction
                }
            }
            .niyatBackground()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.large])
    }

    private var introduction: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    point("text.word.spacing", "Follows you word by word",
                          "Recite from anywhere on the page. Niyat finds your place, highlights the word you're on and turns the pages with you.")
                    point("checkmark.bubble", "Helps you review the words",
                          "Green means the final transcript matched the written word, not that your pronunciation was correct. While listening, words remain unverified. Underlined words may need review. Speech recognition can miss or change words, and Niyat cannot assess harakat, tajweed or makharij. Check your recitation with a qualified teacher.")
                    point("eye.slash", "Recite from memory",
                          "Hide the text with the eye button. Niyat keeps following and marking words; show the text to see them.")
                    point("lock.shield", "Private",
                          RecitationCheckSettings.isAvailable
                              ? (onDevice
                                  ? "Apple's speech recognition follows you on this iPhone. If you turn on the recitation check (next), each part you recite is also sent to Niyat's server to be checked, then deleted. Nothing is saved."
                                  : "Apple's speech recognition follows you (on Apple's servers on this iPhone, encrypted as with dictation). If you turn on the recitation check (next), each part you recite is also sent to Niyat's server to be checked, then deleted. Nothing is saved.")
                              : onDevice
                              ? "Your voice is turned into text by Apple's speech recognition on this iPhone. Nothing is sent anywhere, and Niyat never records or saves your recitation."
                              : "Your voice is turned into text by Apple's speech recognition, which on this iPhone runs on Apple's servers (encrypted, as with dictation). Niyat never records or saves your recitation.")
                    point("book", "Your reading",
                          edition.riwayah == .hafs
                              ? "Words are checked against the \(edition.title) text (\(edition.riwayah.title))."
                              : "Words are checked against the \(edition.riwayah.title) text. Arabic speech recognition isn't trained on each riwayah, so expect more words marked as uncertain.")
                }
                .padding(20)
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    UserDefaults.standard.set(true, forKey: Self.seenKey)
                    if Self.needsCheckChoice(for: edition) {
                        withAnimation(.smooth) { showsCheck = true }
                    } else {
                        dismiss()
                        onStart()
                    }
                } label: {
                    Text("Continue").font(.headline).frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(Palette.control)
                .controlSize(.large)
                .padding(20)
                .background { BottomFade() }
            }
            .navigationTitle("Recite with Niyat")
            .navigationBarTitleDisplayMode(.inline)
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
    @State private var checkUsed = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    legend(.mistake, "Sounded different", "Something clearly different was heard.")
                    legend(.skipped, "Possibly skipped", "The words around it were heard, but not this one.")
                    if checkUsed { legend(.check, "Check this", "A vowel or tajweed point worth checking.") }
                    legend(.uncertain, "Couldn't tell", "Not clearly heard. Often the recogniser, not you.")
                } footer: {
                    Text(checkUsed
                         ? "Marked by Quran Muaalem, an AI model that can make mistakes. It's for help only and isn't a replacement for a qualified teacher. Treat these as prompts to check with the text or a teacher."
                         : "Niyat compares words, not pronunciation or tajweed, and speech recognition can mishear. Treat these as prompts to check with the text or a teacher.")
                }
                if verses.isEmpty {
                    ContentUnavailableView("Nothing to review", systemImage: "checkmark.seal",
                                           description: Text("Words to double-check appear here after you recite."))
                        .listRowBackground(Color.clear)
                }
                ForEach(verses) { verse in
                    Section {
                        ForEach(verse.words) { word in
                            VStack(alignment: .leading, spacing: 6) {
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
                                ForEach(word.notes, id: \.self) { note in
                                    Text(note)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .padding(.leading, 42)
                                }
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
        .onAppear {
            verses = LiveRecitation.shared.review()
            checkUsed = !RecitationChecker.shared.checked.isEmpty
        }
        .presentationDetents([.medium, .large])
    }

    private func title(_ mark: WordMark) -> String {
        switch mark {
        case .correct: "Text matched"
        case .mistake: "Sounded different"
        case .skipped: "Possibly skipped"
        case .check: "Check this"
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
            case .check:
                context.stroke(path, with: .color(Color(style.check)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
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
