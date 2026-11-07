import SwiftUI

/// Which ayah's commentary to show, for `.sheet(item:)`.
struct TafsirTarget: Identifiable, Hashable {
    let surah: Int
    let ayah: Int
    var id: String { "\(surah):\(ayah)" }
}

/// The commentary on one ayah, in Al-Jalalayn or Ibn Kathir (chosen with the
/// switch at the top; Niyat remembers the choice).
struct TafsirSheet: View {
    let surah: Int
    let ayah: Int
    @AppStorage("quran.tafsirBook") private var bookID = TafsirBook.jalalayn.rawValue
    @Environment(\.dismiss) private var dismiss
    @State private var state: LoadState = .loading

    private enum LoadState {
        case loading
        case loaded(TafsirIndex)
        case failed(String)
    }

    private var book: TafsirBook { TafsirBook(rawValue: bookID) ?? .jalalayn }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Picker("Tafsir", selection: $bookID) {
                        ForEach(TafsirBook.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    Text(book.summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    content
                }
                .padding(20)
                .readableWidth()
            }
            .niyatBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .task(id: bookID) { await load() }
    }

    private var title: String {
        "\(QuranStore.shared.surah(surah)?.transliteration ?? "Surah \(surah)") \(surah):\(ayah)"
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            ProgressView()
                .tint(.white)
                .frame(maxWidth: .infinity, minHeight: 200)
        case .failed(let message):
            Text(message)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 200)
        case .loaded(let index):
            if let entry = index.entry(surah: surah, ayah: ayah) {
                commentary(entry, file: index.file)
            } else {
                Text("\(book.title) has no commentary on this ayah. It explains it together with the next one.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 160)
            }
        }
    }

    private func commentary(_ entry: TafsirEntry, file: TafsirFile) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if entry.isRange {
                Label("On ayat \(entry.from)–\(entry.to), explained together", systemImage: "text.alignright")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.accent)
            }
            Text(entry.text)
                .font(.system(size: 20))
                .lineSpacing(9)
                .foregroundStyle(.white.opacity(0.92))
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .environment(\.layoutDirection, .rightToLeft)
                .textSelection(.enabled)
            VStack(alignment: .leading, spacing: 4) {
                Text(file.name).font(.footnote.weight(.semibold))
                Text(file.author).font(.caption)
                Text(file.edition).font(.caption)
                Text("Text from Quranpedia.net, version \(file.version).").font(.caption)
            }
            .foregroundStyle(.secondary)
            .padding(.top, 8)
        }
    }

    private func load() async {
        state = .loading
        do {
            state = .loaded(try await TafsirStore.shared.index(book))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
