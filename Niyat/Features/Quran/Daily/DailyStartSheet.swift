import SwiftUI

/// The daily reader's pencil: choose the surah and ayah your daily reading
/// goes on from. Only the green daily bookmark moves; the red ribbon stays.
/// Exactly as tall as what it shows.
struct DailyStartSheet: View {
    let verseCounts: [Int]
    let onChoose: (DailyPlace) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var store = QuranStore.shared
    @State private var surah: Int
    @State private var verse: Int
    @State private var height: CGFloat = 480

    init(start: DailyPlace, verseCounts: [Int], onChoose: @escaping (DailyPlace) -> Void) {
        self.verseCounts = verseCounts
        self.onChoose = onChoose
        _surah = State(initialValue: start.surah)
        _verse = State(initialValue: start.verse)
    }

    /// Ayat in the chosen surah (at least one, while the text loads).
    private var count: Int {
        verseCounts.indices.contains(surah - 1) ? max(verseCounts[surah - 1], 1) : 1
    }

    private func name(_ number: Int) -> String {
        store.surah(number)?.transliteration ?? "Surah \(number)"
    }

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Image(systemName: "pencil")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color(QuranTextStyle.dailyGreen))
                    .frame(width: 56, height: 56)
                    .background(Color(QuranTextStyle.dailyGreen).opacity(0.16), in: .circle)
                Text("Where to read").font(.title3.weight(.bold))
                Text("Your daily ayat go on from here, and the green bookmark moves with them. Your red ribbon stays where it is.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 0) {
                Picker("Surah", selection: $surah) {
                    ForEach(1...114, id: \.self) { number in
                        Text("\(number). \(name(number))").tag(number)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
                Picker("Ayah", selection: $verse) {
                    ForEach(1...count, id: \.self) { number in
                        Text("\(number)").monospacedDigit().tag(number)
                    }
                }
                .pickerStyle(.wheel)
                .frame(width: 92)
            }
            .frame(height: 180)
            .clipped()
            .surface(cornerRadius: 20)

            Button {
                onChoose(DailyPlace(surah: surah, verse: min(verse, count)))
                dismiss()
            } label: {
                Text("Read from \(name(surah)) \(surah):\(min(verse, count))")
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.glassProminent)
            .tint(Palette.control)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .padding(.bottom, 12)
        .readableWidth(520)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .presentationDetents([.height(height)])
        .presentationDragIndicator(.visible)
        // A new surah starts at its first ayah (the old number may not exist in it).
        .onChange(of: surah) { _, _ in verse = 1 }
    }
}
