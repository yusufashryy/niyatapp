import SwiftUI
import UIKit

/// "Share": a preview of the card, a choice to include the translation, and
/// the iOS share sheet (Messages, WhatsApp, Instagram, Save Image…).
struct QuranShareSheet: View {
    let content: QuranShareContent
    @Environment(\.dismiss) private var dismiss
    @AppStorage("share.includesTranslation") private var includesTranslation = true
    @State private var image: QuranShareImage?
    @State private var failed = false
    @State private var copied = false

    private var showsTranslation: Bool { includesTranslation && !content.translation.isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    QuranShareCard(content: content, showsTranslation: showsTranslation, isPicture: false)
                        .clipShape(.rect(cornerRadius: 24))
                        .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(Palette.hairline) }
                        .shadow(color: Palette.glow.opacity(0.4), radius: 24, y: 8)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Card preview: \(content.title), \(content.reference)")

                    if !content.translation.isEmpty {
                        Toggle("Include the translation", isOn: $includesTranslation)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .surface(cornerRadius: 18)
                    }

                    if failed {
                        Text("Couldn't make the picture. You can still copy the text.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(16)
                .readableWidth(520)
            }
            .niyatBackground()
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        UIPasteboard.general.string = content.plainText(includingTranslation: showsTranslation)
                        copied = true
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .accessibilityLabel(copied ? "Copied" : "Copy the text")
                }
            }
            .safeAreaInset(edge: .bottom) { shareButton }
        }
        .haptic(.success, trigger: copied)
        // Drawn again whenever the translation is switched on or off.
        .task(id: showsTranslation) { render() }
    }

    @ViewBuilder
    private var shareButton: some View {
        Group {
            if let image {
                ShareLink(item: image,
                          message: Text(content.plainText(includingTranslation: showsTranslation)),
                          preview: SharePreview(content.reference, image: image.preview)) {
                    Label("Share card", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
            } else if failed {
                ShareLink(item: content.plainText(includingTranslation: showsTranslation)) {
                    Label("Share text", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .buttonStyle(.glassProminent)
        .tint(Palette.control)
        .controlSize(.large)
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
        .readableWidth(520)
    }

    private func render() {
        copied = false
        let rendered = QuranShareImage.render(content, showsTranslation: showsTranslation)
        image = rendered
        failed = rendered == nil
    }
}
