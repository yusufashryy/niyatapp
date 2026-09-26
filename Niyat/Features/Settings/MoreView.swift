import StoreKit
import SwiftUI

struct MoreView: View {
    @State private var showTutorial = false
    @Environment(\.openURL) private var openURL
    @Environment(\.requestReview) private var requestReview

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    GlassEffectContainer(spacing: 12) {
                        HStack(spacing: 12) {
                            tile("Tasbih", systemImage: "circle.hexagongrid.fill", tint: Palette.accent) { TasbihView() }
                            tile("Prayer Lock", systemImage: "lock.shield.fill", tint: Palette.highlight) { FocusView() }
                        }
                    }
                    GlassEffectContainer(spacing: 12) {
                        HStack(spacing: 12) {
                            tile("Groups", systemImage: "person.3.fill", tint: Palette.highlight) { GroupsView() }
                            tile("Qibla", systemImage: "location.north.circle.fill", tint: Palette.accent) { QiblaView() }
                        }
                    }
                    .appearAnimation(0)

                    VStack(spacing: 0) {
                        Button { showTutorial = true } label: {
                            rowLabel("How to use Niyat", systemImage: "questionmark.circle.fill")
                        }
                        .buttonStyle(.pressable)
                        Divider().overlay(Palette.hairline).padding(.leading, 56)
                        row("Settings", systemImage: "gearshape.fill") { SettingsView() }
                        Divider().overlay(Palette.hairline).padding(.leading, 56)
                        row("Themes", systemImage: "paintpalette.fill") { ThemePickerView() }
                        Divider().overlay(Palette.hairline).padding(.leading, 56)
                        row("Add widgets", systemImage: "square.grid.2x2.fill") { WidgetGuideView() }
                        Divider().overlay(Palette.hairline).padding(.leading, 56)
                        row("About & credits", systemImage: "info.circle.fill") { AboutView() }
                    }
                    .surface(cornerRadius: 22)
                    .appearAnimation(1)

                    VStack(spacing: 0) {
                        row("Support Niyat", systemImage: "heart.fill") { SupportView() }
                        Divider().overlay(Palette.hairline).padding(.leading, 56)
                        row("Send feedback", systemImage: "envelope.fill") { FeedbackView() }
                        Divider().overlay(Palette.hairline).padding(.leading, 56)
                        Button {
                            if let url = ReviewPrompter.writeReviewURL {
                                openURL(url)
                            } else {
                                requestReview()
                            }
                        } label: {
                            rowLabel("Rate Niyat", systemImage: "star.fill")
                        }
                        .buttonStyle(.pressable)
                    }
                    .surface(cornerRadius: 22)
                    .appearAnimation(2)

                    VStack(spacing: 10) {
                        Text("إِنَّمَا ٱلْأَعْمَالُ بِٱلنِّيَّاتِ")
                            .font(.calligraphy(size: 30))
                            .foregroundStyle(Palette.highlight)
                        Text("“Actions are judged by their intentions.”")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        OrnamentDivider()
                            .frame(width: 160)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
                    .appearAnimation(3)
                }
                .padding(16)
            }
            .niyatBackground()
            .navigationTitle("More")
            .fullScreenCover(isPresented: $showTutorial) { TutorialView() }
        }
    }

    private func tile<Destination: View>(_ title: String, systemImage: String, tint: Color,
                                         @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink(destination: destination) {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: systemImage)
                    .font(.title.weight(.semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
            .padding(18)
            .background(alignment: .bottomTrailing) {
                EightPointStar()
                    .stroke(tint.opacity(0.25), lineWidth: 1.5)
                    .frame(width: 70, height: 70)
                    .offset(x: 18, y: 18)
            }
            .clipShape(.rect(cornerRadius: 26))
            .glassPanel(cornerRadius: 26, interactive: true)
        }
        .buttonStyle(.pressable)
    }

    private func row<Destination: View>(_ title: String, systemImage: String,
                                        @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink(destination: destination) {
            rowLabel(title, systemImage: systemImage)
        }
        .buttonStyle(.pressable)
    }

    private func rowLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .foregroundStyle(Palette.accent)
                .frame(width: 28)
            Text(title).foregroundStyle(.white)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .contentShape(.rect)
    }
}

private struct WidgetGuideView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                guide(title: "Home Screen", steps: [
                    "Touch and hold an empty spot on your Home Screen until the apps jiggle.",
                    "Tap Edit, then Add Widget.",
                    "Search for Niyat and pick a widget: Next Prayer, Prayer Times, Verse of the Day or Tasbih.",
                ])
                guide(title: "Lock Screen", steps: [
                    "Touch and hold your Lock Screen, then tap Customize › Lock Screen.",
                    "Tap the widget area under the clock and add Next Prayer or Verse of the Day.",
                ])
            }
            .padding(16)
        }
        .niyatBackground()
        .navigationTitle("Widgets")
    }

    private func guide(title: String, steps: [String]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).sectionLabelStyle()
            ForEach(Array(steps.enumerated()), id: \.offset) { index, text in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(index + 1)")
                        .font(.footnote.weight(.heavy))
                        .foregroundStyle(.black)
                        .frame(width: 26, height: 26)
                        .background(Palette.accent, in: .circle)
                    Text(text)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .surface(cornerRadius: 22)
    }
}

struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Niyat").font(.display(34, weight: .heavy))
                        Spacer()
                        Text("نيّة").font(.calligraphy(size: 40)).foregroundStyle(Palette.highlight)
                    }
                    Text("intention").font(.headline).foregroundStyle(Palette.accent)
                    Text("A free, open-source companion for your deen. No ads, no subscriptions, no accounts and no tracking. Everything runs on your phone.")
                        .foregroundStyle(.secondary)
                    Link(destination: URL(string: "https://github.com/yusufashryy/niyatapp")!) {
                        Label("Source code on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                            .font(.headline)
                    }
                    .buttonStyle(.glass)
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .glassPanel(cornerRadius: 28, tint: Palette.glow.opacity(0.35))

                QuranIntegrityRow()

                Text("Credits").sectionLabelStyle().padding(.top, 6)
                VStack(alignment: .leading, spacing: 14) {
                    credit("Quran text", "Tanzil Project (tanzil.net), Uthmani text. CC BY 3.0, used verbatim.")
                    credit("English translation", "Translation by Talal Itani, ClearQuran.com. CC BY-ND 4.0.")
                    credit("Surah information", "Tanzil Project metadata. CC BY 3.0.")
                    credit("Quran font", "Amiri Quran by Khaled Hosny and the Amiri Quran Project Authors. SIL Open Font License 1.1.")
                    credit("Calligraphy font", "Aref Ruqaa by the Aref Ruqaa Project Authors. SIL Open Font License 1.1.")
                    credit("Prayer time calculation", "Adhan by Batoul Apps. MIT License.")
                    credit("Recitation audio", "Streamed from the Islamic Network CDN (islamic.network), free for non-commercial use. Each recitation's copyright stays with its reciter.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .surface(cornerRadius: 22)

                Text("May Allah accept it from us and from you.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
            }
            .padding(16)
        }
        .niyatBackground()
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func credit(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(detail).font(.footnote).foregroundStyle(.secondary)
        }
    }
}

/// Shows whether the bundled Quran files match their published checksums.
private struct QuranIntegrityRow: View {
    @State private var store = QuranStore.shared

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text("Tanzil Uthmani text and ClearQuran translation, checked byte-for-byte against their published SHA-256 checksums. 114 surahs, 6,236 verses.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(cornerRadius: 22)
        .task { await store.load() }
    }

    private var title: String {
        switch store.isVerified {
        case true?: "Quran text verified"
        case false?: "Quran text failed verification"
        case nil: "Checking Quran text…"
        }
    }

    private var icon: String {
        switch store.isVerified {
        case true?: "checkmark.seal.fill"
        case false?: "exclamationmark.octagon.fill"
        case nil: "hourglass"
        }
    }

    private var color: Color {
        switch store.isVerified {
        case true?: Palette.accent
        case false?: .red
        case nil: .secondary
        }
    }
}
