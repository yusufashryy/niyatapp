import SwiftUI
import UIKit

/// Qur'an › Recite: recite aloud and Niyat follows along word by word,
/// pointing out words that may be worth double-checking. Beta.
struct RecitationCheckView: View {
    let startSurah: Int
    let startVerse: Int

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var session = RecitationSession()
    @State private var store = QuranStore.shared
    @State private var player = RecitationPlayer.shared
    @State private var surah: Int

    init(surah: Int, verse: Int = 1) {
        startSurah = surah
        startVerse = verse
        _surah = State(initialValue: surah)
    }

    private var isListening: Bool { session.status == .listening }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    currentVerse
                    if !session.results.isEmpty { resultsList }
                    note
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .niyatBackground()
            .safeAreaInset(edge: .bottom) { controls }
            .navigationTitle("Recite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Text("Recite").font(.headline)
                        Text("BETA")
                            .font(.caption2.weight(.heavy))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Palette.control.opacity(0.25), in: .capsule)
                    }
                }
            }
            .task { await session.load(surah: startSurah, from: startVerse) }
            .onChange(of: surah) { _, new in Task { await session.load(surah: new, from: 1) } }
            .onDisappear { session.stop() }
            .haptic(.success, trigger: session.results.count)
            .haptic(.impact(weight: .medium), trigger: isListening)
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Menu {
                    Picker("Surah", selection: $surah) {
                        ForEach(store.surahs) { Text("\($0.id). \($0.transliteration)").tag($0.id) }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(store.surah(surah)?.transliteration ?? "Surah \(surah)").font(.title3.weight(.bold))
                        Image(systemName: "chevron.down").font(.caption.weight(.bold))
                    }
                    .foregroundStyle(.white)
                }
                .disabled(isListening)
                Spacer()
                Text(store.surah(surah)?.name ?? "")
                    .font(.quran(size: 22))
                    .foregroundStyle(Palette.highlight)
            }
            if let current = session.current {
                HStack {
                    Text("Verse \(current.number) of \(session.verses.count)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if isListening {
                        Label(session.isOnDevice ? "On this iPhone" : "Apple speech service",
                              systemImage: session.isOnDevice ? "lock.fill" : "network")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var currentVerse: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let current = session.current {
                WordFlow(spacing: 10, lineSpacing: 14) {
                    ForEach(Array(current.words.enumerated()), id: \.offset) { index, word in
                        WordView(word: word, state: session.states.indices.contains(index) ? session.states[index] : .pending,
                                 isNext: isListening && index == nextWordIndex)
                    }
                    Text("\u{06DD}\(arabicDigits(current.number))")
                        .font(.quran(size: 26))
                        .foregroundStyle(Palette.highlight)
                }
                .environment(\.layoutDirection, .rightToLeft)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.smooth(duration: 0.25), value: session.states)

                if isListening {
                    HStack(spacing: 8) {
                        Image(systemName: "waveform")
                            .symbolEffect(.variableColor.iterative, options: .repeating)
                            .foregroundStyle(Palette.control)
                        Text(session.heard.isEmpty ? "Listening… start reciting" : session.heard)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }

            switch session.status {
            case .unavailable(let message):
                VStack(alignment: .leading, spacing: 8) {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    .font(.footnote.weight(.semibold))
                }
            case .finished:
                Label("Surah complete. \(summary)", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.highlight)
            default:
                EmptyView()
            }
        }
        .padding(18)
        .surface(cornerRadius: 24)
    }

    private var resultsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("This session").sectionLabelStyle()
                Spacer()
                Text(summary).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(session.results.reversed()) { result in
                ResultRow(result: result) {
                    session.stop()
                    player.play(surah: surah, from: result.number, verseCounts: store.hafsVerseCounts, only: true)
                } onRetry: {
                    session.jump(to: result.number)
                }
            }
        }
    }

    private var note: some View {
        Text("Beta. Niyat follows the words you recite. It doesn't judge tajwid or pronunciation, and speech recognition can mishear, so treat highlighted words as a prompt to double-check with the text or a teacher. Checks the Hafs reading. Nothing is recorded or saved.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var controls: some View {
        HStack(spacing: 14) {
            Button {
                if let current = session.current, current.number > 1 { session.jump(to: current.number - 1) }
            } label: {
                Image(systemName: "backward.fill").frame(width: 44, height: 44)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Previous verse")

            Button {
                if isListening { session.stop() } else { Task { await session.start() } }
            } label: {
                Label(isListening ? "Stop" : (session.status == .finished ? "Start again" : "Start reciting"),
                      systemImage: isListening ? "stop.fill" : "mic.fill")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .tint(isListening ? .red : Palette.control)
            .controlSize(.large)
            .disabled(session.current == nil)

            Button { session.skipVerse() } label: {
                Image(systemName: "forward.fill").frame(width: 44, height: 44)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Next verse")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: Helpers

    private var nextWordIndex: Int {
        (session.states.lastIndex { $0 != .pending }).map { $0 + 1 } ?? 0
    }

    private var summary: String {
        let words = session.results.reduce(0) { $0 + $1.words.count }
        let issues = session.results.reduce(0) { $0 + $1.issues }
        let verses = session.results.count
        return "\(verses) \(verses == 1 ? "verse" : "verses"), \(issues == 0 ? "no words" : "\(issues) of \(words) words") to check"
    }

    private func arabicDigits(_ value: Int) -> String {
        let digits = Array("٠١٢٣٤٥٦٧٨٩")
        return String(String(value).compactMap { $0.wholeNumberValue.map { digits[$0] } })
    }
}

/// One word, coloured by how it was heard.
private struct WordView: View {
    let word: String
    let state: RecitationMatcher.WordState
    let isNext: Bool

    var body: some View {
        Text(word)
            .font(.quran(size: 26))
            .foregroundStyle(color)
            .padding(.horizontal, 4)
            .padding(.bottom, 4)
            .background(alignment: .bottom) {
                if state == .different || state == .skipped {
                    Capsule().fill(.orange).frame(height: 3)
                } else if isNext {
                    Capsule().fill(Palette.control.opacity(0.7)).frame(height: 3)
                }
            }
            .accessibilityLabel(accessibility)
    }

    private var color: Color {
        switch state {
        case .matched: Palette.highlight
        case .different, .skipped: .orange
        case .pending: .white.opacity(0.55)
        }
    }

    private var accessibility: String {
        switch state {
        case .matched: "\(word), heard"
        case .different: "\(word), check this word"
        case .skipped: "\(word), may have been skipped"
        case .pending: word
        }
    }
}

private struct ResultRow: View {
    let result: RecitationSession.VerseResult
    let onListen: () -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: result.issues == 0 ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(result.issues == 0 ? Palette.highlight : .orange)
                Text("Verse \(result.number)").font(.subheadline.weight(.semibold))
                Text(result.issues == 0 ? "All words heard" : "\(result.issues) to check")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: onListen) { Image(systemName: "speaker.wave.2") }
                    .accessibilityLabel("Listen to verse \(result.number)")
                Button(action: onRetry) { Image(systemName: "arrow.counterclockwise") }
                    .accessibilityLabel("Recite verse \(result.number) again")
            }
            if result.issues > 0 {
                WordFlow(spacing: 8, lineSpacing: 8) {
                    ForEach(Array(result.words.enumerated()).filter { result.states[$0.offset] == .different || result.states[$0.offset] == .skipped },
                            id: \.offset) { _, word in
                        Text(word)
                            .font(.quran(size: 20))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 10).padding(.vertical, 2)
                            .background(Color.orange.opacity(0.12), in: .capsule)
                    }
                }
                .environment(\.layoutDirection, .rightToLeft)
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .surface(cornerRadius: 18)
    }
}

/// Lays words out in lines, wrapping like text.
struct WordFlow: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: proposal.width ?? widest, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > bounds.width {
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
