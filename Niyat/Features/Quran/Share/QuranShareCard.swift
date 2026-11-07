import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

/// What goes on a share card: a verse or a dua from the Qur'an. The Arabic
/// and English are the bundled, verified text, never retyped.
struct QuranShareContent: Identifiable, Hashable {
    /// What it's about (a dua's title, or the surah's name).
    let title: String
    /// Who made the dua, as told in the Qur'an (duas only).
    let context: String?
    let arabic: String
    let translation: String
    /// "Al-Baqarah 2:201".
    let reference: String

    var id: String { reference }

    /// The text, for apps that take words rather than a picture.
    func plainText(includingTranslation: Bool) -> String {
        var parts = [arabic]
        if includingTranslation, !translation.isEmpty { parts.append(translation) }
        parts.append("— Qur'an, \(reference)")
        return parts.joined(separator: "\n\n")
    }
}

extension QuranShareContent {
    @MainActor
    static func verse(_ verse: Verse) -> QuranShareContent {
        let surahName = QuranStore.shared.surah(verse.surah)?.transliteration ?? "Surah \(verse.surah)"
        return QuranShareContent(title: surahName, context: nil, arabic: verse.arabic, translation: verse.translation,
                                 reference: "\(surahName) \(verse.surah):\(verse.number)")
    }

    @MainActor
    static func dua(_ dua: QuranicDua, verses: [Verse]) -> QuranShareContent {
        let surahName = QuranStore.shared.surah(dua.surah)?.transliteration ?? "Surah \(dua.surah)"
        return QuranShareContent(title: dua.title, context: dua.context,
                                 arabic: verses.map(\.arabic).joined(separator: " "),
                                 translation: verses.map(\.translation).joined(separator: " "),
                                 reference: "\(surahName) \(dua.reference)")
    }
}

/// The card itself, drawn the same on screen and in the shared picture. No
/// Liquid Glass here: it can't be drawn into an image.
struct QuranShareCard: View {
    let content: QuranShareContent
    let showsTranslation: Bool
    /// The shared picture is always `width` wide; the on-screen preview may
    /// be narrower on a small iPhone.
    var isPicture = true

    /// The picture is this wide in points (three times as many pixels).
    static let width: CGFloat = 360

    var body: some View {
        VStack(spacing: 18) {
            EightPointStar()
                .stroke(Palette.highlight.opacity(0.8), lineWidth: 1.5)
                .frame(width: 26, height: 26)
            VStack(spacing: 4) {
                Text(content.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                if let context = content.context {
                    Text(context)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .multilineTextAlignment(.center)

            Text(content.arabic)
                .font(.quran(size: 26))
                .lineSpacing(12)
                .multilineTextAlignment(.center)
                .foregroundStyle(Palette.highlight)
                .environment(\.layoutDirection, .rightToLeft)
                .fixedSize(horizontal: false, vertical: true)

            if showsTranslation, !content.translation.isEmpty {
                Rectangle()
                    .fill(Palette.highlight.opacity(0.3))
                    .frame(width: 48, height: 1)
                Text(content.translation)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 4) {
                Text(content.reference)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Palette.accent)
                Text(showsTranslation && !content.translation.isEmpty
                     ? "Translation: The Clear Quran · Shared from Niyat" : "Shared from Niyat")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 32)
        .frame(width: isPicture ? Self.width : nil)
        .frame(maxWidth: Self.width)
        .background {
            ZStack {
                LinearGradient(colors: [Palette.glow.opacity(0.9), Palette.base], startPoint: .top, endPoint: .bottom)
                IslamicPattern(tile: 48, lineWidth: 0.8, color: Palette.highlight.opacity(0.07))
            }
        }
        .environment(\.colorScheme, .dark)
    }
}

/// The card as a PNG, for the share sheet.
struct QuranShareImage: Transferable {
    let png: Data
    let preview: Image

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { $0.png }
            .suggestedFileName("Niyat.png")
    }

    /// Draws the card at three times its size. Nil if it couldn't be drawn.
    @MainActor
    static func render(_ content: QuranShareContent, showsTranslation: Bool) -> QuranShareImage? {
        let renderer = ImageRenderer(content: QuranShareCard(content: content, showsTranslation: showsTranslation))
        renderer.scale = 3
        renderer.isOpaque = true
        guard let image = renderer.uiImage, let png = image.pngData() else { return nil }
        return QuranShareImage(png: png, preview: Image(uiImage: image))
    }
}
