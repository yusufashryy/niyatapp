import SwiftUI

/// One hadith: its grade and source, the English and Arabic, the explanation
/// and lessons, and sharing.
struct HadithDetailView: View {
    let hadith: Hadith
    @State private var library = HadithLibrary.shared
    @State private var sharing: QuranShareContent?
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero
                Text(hadith.text)
                    .font(.body)
                    .lineSpacing(6)
                    .foregroundStyle(.white.opacity(0.95))
                    .textSelection(.enabled)
                    .padding(.horizontal, 4)
                if !hadith.explanation.isEmpty {
                    section("Explanation", icon: "text.book.closed.fill") {
                        Text(hadith.explanation).font(.callout).lineSpacing(4).textSelection(.enabled)
                    }
                }
                if !hadith.lessons.isEmpty {
                    section("Lessons", icon: "lightbulb.fill") {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(hadith.lessons.enumerated()), id: \.offset) { number, lesson in
                                HStack(alignment: .firstTextBaseline, spacing: 12) {
                                    Text("\(number + 1)")
                                        .font(.caption.weight(.bold).monospacedDigit())
                                        .foregroundStyle(.black)
                                        .frame(width: 22, height: 22)
                                        .background(Palette.highlight, in: .circle)
                                    Text(lesson).font(.callout)
                                }
                            }
                        }
                    }
                }
                Text("From the Encyclopedia of Translated Prophetic Hadiths, \(library.index?.file.version ?? "HadeethEnc.com").")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .readableWidth()
        }
        .niyatBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    UIPasteboard.general.string = QuranShareContent.hadith(hadith).plainText(includingTranslation: false)
                    copied = true
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .contentTransition(.symbolEffect(.replace))
                }
                .accessibilityLabel(copied ? "Copied" : "Copy the hadith")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { sharing = .hadith(hadith) } label: { Image(systemName: "square.and.arrow.up") }
                    .accessibilityLabel("Share the hadith")
            }
        }
        .haptic(.success, trigger: copied)
        .sheet(item: $sharing) { QuranShareSheet(content: $0) }
    }

    private static let plainGrades: Set<String> = ["authentic", "authentic hadith", "hasan", "good hadith", ""]

    /// The title, the Arabic as the centrepiece, then grade and source.
    private var hero: some View {
        VStack(spacing: 16) {
            Text(hadith.title)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if !hadith.arabic.isEmpty {
                OrnamentDivider().frame(width: 120)
                Text(hadith.arabic)
                    .font(.system(size: 22))
                    .lineSpacing(10)
                    .foregroundStyle(Palette.highlight)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .environment(\.layoutDirection, .rightToLeft)
                    .textSelection(.enabled)
                OrnamentDivider().frame(width: 120)
            }
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    GradeBadge(level: hadith.level)
                    Text(hadith.source).font(.footnote.weight(.semibold)).foregroundStyle(.white.opacity(0.8))
                }
                Text(Self.plainGrades.contains(hadith.grade.lowercased())
                     ? hadith.level.meaning : "Grading: \(hadith.grade). \(hadith.level.meaning)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(alignment: .top) {
            EightPointStar()
                .stroke(Palette.highlight.opacity(0.08), lineWidth: 1.5)
                .frame(width: 240, height: 240)
                .offset(y: -90)
        }
        .clipShape(.rect(cornerRadius: 28))
        .glassPanel(cornerRadius: 28, tint: Palette.glow.opacity(0.3))
    }

    private func section<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.footnote.weight(.bold))
                .textCase(.uppercase)
                .tracking(1)
                .foregroundStyle(Palette.highlight)
            content()
                .foregroundStyle(.white.opacity(0.88))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .surface(cornerRadius: 18)
    }
}
