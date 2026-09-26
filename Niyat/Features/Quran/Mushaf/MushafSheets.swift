import SwiftUI
import UIKit

/// Shown after tapping a verse: its meaning and what you can do with it.
struct MushafVerseActions: View {
    let verse: Verse
    let showTranslation: Bool
    let canPlay: Bool
    let isBookmarked: Bool
    let onPlayFromHere: () -> Void
    let onPlayVerse: () -> Void
    let onBookmark: () -> Void
    let onClose: () -> Void
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(QuranStore.shared.surah(verse.surah)?.transliteration ?? "") \(verse.surah):\(verse.number)")
                    .font(.subheadline.weight(.bold))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.caption.weight(.bold)).frame(width: 28, height: 28)
                }
                .accessibilityLabel("Close verse options")
            }
            if showTranslation, !verse.translation.isEmpty {
                ScrollView {
                    Text(verse.translation)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 90)
                .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                if canPlay {
                    action("Play from here", "play.fill", onPlayFromHere)
                    action("This verse", "repeat.1", onPlayVerse)
                }
                action(isBookmarked ? "Saved" : "Bookmark", isBookmarked ? "bookmark.fill" : "bookmark", onBookmark)
                action(copied ? "Copied" : "Copy", copied ? "checkmark" : "doc.on.doc") {
                    UIPasteboard.general.string = "\(verse.arabic)\n\n\(verse.translation)\n— Qur'an \(verse.surah):\(verse.number)"
                    copied = true
                }
            }
            .haptic(.impact(weight: .light), trigger: isBookmarked)
            .haptic(.success, trigger: copied)
        }
        .foregroundStyle(.white)
        .padding(14)
        .glassPanel(cornerRadius: 24, tint: Palette.glow.opacity(0.35))
        // A dark panel on every paper, so it reads as floating above the page.
        .environment(\.colorScheme, .dark)
        .onChange(of: verse) { _, _ in copied = false }
    }

    private func action(_ title: String, _ icon: String, _ perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.headline)
                Text(title).font(.caption2.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.08), in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.pressable)
    }
}

/// Page settings.
struct MushafOptionsSheet: View {
    @Binding var options: MushafOptions
    @AppStorage("quran.tajweed") private var tajweedOn = true
    @Environment(\.dismiss) private var dismiss
    @State private var store = QuranStore.shared
    @State private var player = RecitationPlayer.shared

    var body: some View {
        NavigationStack {
            Form {
                Section("Paper") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 12) {
                        ForEach(MushafStyle.allCases) { style in
                            swatch(style)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Toggle("Tajweed colours", isOn: $tajweedOn)
                    NavigationLink("Colour guide") { TajweedGuideView() }
                } header: {
                    Text("Tajweed")
                } footer: {
                    Text("Coloured letter by letter from a verified dataset, for the Uthmani script (Hafs). With Increase Contrast on (Settings › Accessibility), the colours are deeper.")
                }

                Section("Tap and recitation") {
                    Picker("Tapping a verse", selection: $options.tapAction) {
                        ForEach(MushafOptions.TapAction.allCases) { Text($0.title).tag($0) }
                    }
                    Toggle("Show meaning of tapped verse", isOn: $options.showTranslation)
                    Toggle("Turn pages with the recitation", isOn: $options.followRecitation)
                    Toggle("Keep screen on", isOn: $options.keepScreenOn)
                        .onChange(of: options.keepScreenOn) { _, on in UIApplication.shared.isIdleTimerDisabled = on }
                    if store.edition.riwayah.hasVerseAudio {
                        NavigationLink {
                            ReciterPicker(embedded: true)
                        } label: {
                            LabeledContent("Reciter", value: player.reciter.name)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .niyatBackground()
            .navigationTitle("Page settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func swatch(_ style: MushafStyle) -> some View {
        let colors = style.colors
        return Button {
            options.style = style
        } label: {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(colors.paper))
                    .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(Color(colors.frame), lineWidth: 1.5).padding(3) }
                    .overlay {
                        Text("بِسْمِ")
                            .font(.quran(size: 14))
                            .foregroundStyle(Color(colors.ink))
                    }
                    .frame(height: 52)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(options.style == style ? Palette.control : .clear, lineWidth: 2)
                            .padding(-3)
                    }
                Text(style.title).font(.caption)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.pressable)
        .haptic(.selection, trigger: options.style)
        .accessibilityLabel("\(style.title) paper")
        .accessibilityAddTraits(options.style == style ? .isSelected : [])
    }
}

/// Jump to a page, juz or surah.
struct MushafJumpSheet: View {
    @Binding var page: Int
    @Environment(\.dismiss) private var dismiss
    @State private var store = QuranStore.shared
    @State private var layout = MushafLayout.shared

    var body: some View {
        NavigationStack {
            List {
                Section("Page") {
                    Stepper(value: $page, in: 1...MushafLayout.pageCount) {
                        Text("Page \(page)").monospacedDigit()
                    }
                }
                Section("Juz") {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(Array(store.juzStarts.enumerated()), id: \.offset) { index, start in
                                Button("\(index + 1)") { go(to: start) }
                                    .buttonStyle(.glass)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
                Section("Surah") {
                    ForEach(store.surahs) { surah in
                        Button {
                            go(to: VerseReference(surah: surah.id, verse: 1))
                        } label: {
                            HStack {
                                Text("\(surah.id). \(surah.transliteration)").foregroundStyle(.white)
                                Spacer()
                                Text(surah.name).font(.quran(size: 18)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .niyatBackground()
            .navigationTitle("Go to")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func go(to reference: VerseReference) {
        // Hafs numbering, as in the Uthmani text the pages are laid out for.
        page = layout.page(containing: WordID(surah: reference.surah, verse: reference.verse, index: 0))
        dismiss()
    }
}
