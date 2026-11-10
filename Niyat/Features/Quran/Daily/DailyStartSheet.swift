import SwiftUI

/// The daily reader's pencil: search for where your daily ayat go on from.
/// Type a surah's name or number and pick the ayah, or type "2:255" to go
/// straight there. The reader's ribbon isn't touched.
struct DailyStartSheet: View {
    let current: DailyPlace
    let verseCounts: [Int]
    let onChoose: (DailyPlace) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var store = QuranStore.shared
    @State private var query = ""
    @State private var path: [Int] = []
    @FocusState private var searching: Bool

    init(start: DailyPlace, verseCounts: [Int], onChoose: @escaping (DailyPlace) -> Void) {
        current = start
        self.verseCounts = verseCounts
        self.onChoose = onChoose
    }

    private var results: [Surah] {
        let found = Set(SurahSearch.matches(store.surahs.map(SurahSearch.Entry.init), query: query).map(\.id))
        return store.surahs.filter { found.contains($0.id) }
    }

    private var typedAyah: DailyPlace? { SurahSearch.place(in: query, verseCounts: verseCounts) }

    /// Ayat in a surah in the shown reading (at least one, while the text loads).
    private func count(_ surah: Int) -> Int {
        verseCounts.indices.contains(surah - 1) ? max(verseCounts[surah - 1], 1) : 1
    }

    private func name(_ surah: Int) -> String {
        store.surah(surah)?.transliteration ?? "Surah \(surah)"
    }

    private func choose(_ place: DailyPlace) {
        onChoose(place)
        dismiss()
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    searchField
                    if let typedAyah {
                        Button { choose(typedAyah) } label: { goRow(typedAyah) }
                            .buttonStyle(.pressable)
                            .transition(.scale(scale: 0.95).combined(with: .opacity))
                    }
                    LazyVStack(spacing: 8) {
                        ForEach(results) { surah in
                            NavigationLink(value: surah.id) {
                                DailySurahRow(surah: surah, count: count(surah.id), isCurrent: surah.id == current.surah)
                            }
                                .buttonStyle(.pressable)
                        }
                    }
                    if results.isEmpty, typedAyah == nil {
                        ContentUnavailableView.search(text: query).padding(.top, 20)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 24)
                .readableWidth(560)
                .animation(.smooth, value: typedAyah)
            }
            .scrollDismissesKeyboard(.interactively)
            .niyatBackground()
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { searching = false }.fontWeight(.semibold)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                }
            }
            .navigationDestination(for: Int.self) { surah in
                DailyAyahGrid(surah: surah, name: name(surah),
                              count: count(surah),
                              current: current.surah == surah ? current.verse : nil) { verse in
                    choose(DailyPlace(surah: surah, verse: verse))
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    /// A bold pencil in the app's star, the title, and where you are now.
    private var header: some View {
        VStack(spacing: 10) {
            ZStack {
                EightPointStar()
                    .fill(Palette.highlight.opacity(0.16))
                EightPointStar()
                    .stroke(Palette.highlight.opacity(0.55), lineWidth: 1.5)
                Image(systemName: "pencil")
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundStyle(Palette.highlight)
            }
            .frame(width: 88, height: 88)
            .accessibilityHidden(true)
            Text("Where to read").font(.title2.weight(.bold))
            Text("Search for a surah, or type an ayah like 2:255.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 6) {
                Image(systemName: "book.fill").font(.caption)
                Text("Now at \(name(current.surah)) \(current.surah):\(current.verse)")
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(Palette.highlight)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Palette.highlight.opacity(0.12), in: .capsule)
        }
        .foregroundStyle(.white)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Surah name or number", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .focused($searching)
                .onSubmit {
                    if let typedAyah { choose(typedAyah) } else if results.count == 1, let only = results.first { path.append(only.id) }
                }
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .accessibilityLabel("Clear")
            }
        }
        .font(.body)
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .frame(minHeight: 50)
        .surface(cornerRadius: 18)
    }

    /// "Read from Al-Baqara 2:255", when an ayah is typed.
    private func goRow(_ place: DailyPlace) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.right.circle.fill").font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text("Read from here").font(.caption.weight(.semibold)).opacity(0.75)
                Text("\(name(place.surah)) \(place.surah):\(place.verse)").font(.headline).monospacedDigit()
            }
            Spacer()
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Palette.control.gradient, in: .rect(cornerRadius: 18))
    }
}

/// A surah in the search: its number in a star, names and length.
private struct DailySurahRow: View {
    let surah: Surah
    let count: Int
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 14) {
            Text("\(surah.id)")
                .font(.footnote.weight(.bold).monospacedDigit())
                .foregroundStyle(Palette.accent)
                .frame(width: 40, height: 40)
                .background { EightPointStar().stroke(Palette.accent.opacity(0.6), lineWidth: 1.5) }
            VStack(alignment: .leading, spacing: 2) {
                Text(surah.transliteration).font(.headline)
                Text(isCurrent ? "Reading now · \(count) ayat" : "\(surah.translation) · \(count) ayat")
                    .font(.caption)
                    .foregroundStyle(isCurrent ? Palette.highlight : .secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(surah.name)
                .font(.quran(size: 20))
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .surface(cornerRadius: 18)
        .contentShape(.rect)
    }
}

/// The ayat of one surah as numbered stars: tap one to read from it.
private struct DailyAyahGrid: View {
    let surah: Int
    let name: String
    let count: Int
    /// The ayah you're on, when it's in this surah.
    let current: Int?
    let onChoose: (Int) -> Void

    private let columns = [GridItem(.adaptive(minimum: 56), spacing: 10)]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 4) {
                    Text(name).font(.title2.weight(.bold))
                    Text("Choose the ayah to read from").font(.subheadline).foregroundStyle(.secondary)
                }
                .foregroundStyle(.white)
                .padding(.top, 8)
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(1...count, id: \.self) { verse in
                        Button { onChoose(verse) } label: {
                            Text("\(verse)")
                                .font(.callout.weight(.bold).monospacedDigit())
                                .foregroundStyle(verse == current ? .black : Palette.highlight)
                                .frame(width: 52, height: 52)
                                .background {
                                    if verse == current {
                                        EightPointStar().fill(Palette.highlight)
                                    } else {
                                        EightPointStar().stroke(Palette.highlight.opacity(0.5), lineWidth: 1.3)
                                    }
                                }
                        }
                        .buttonStyle(.pressable)
                        .accessibilityLabel("Ayah \(verse)\(verse == current ? ", reading now" : "")")
                    }
                }
            }
            .padding(20)
            .readableWidth(560)
        }
        .niyatBackground()
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
