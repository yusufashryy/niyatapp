import SwiftUI

struct MoreView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    GlassEffectContainer(spacing: 12) {
                        HStack(spacing: 12) {
                            tile("Tasbih", systemImage: "circle.hexagongrid.fill", tint: Palette.emerald) { TasbihView() }
                            tile("Widgets", systemImage: "square.grid.2x2.fill", tint: Palette.gold) { WidgetGuideView() }
                        }
                    }

                    VStack(spacing: 0) {
                        row("Settings", systemImage: "gearshape.fill") { SettingsView() }
                        Divider().overlay(Palette.hairline).padding(.leading, 56)
                        row("About & credits", systemImage: "info.circle.fill") { AboutView() }
                    }
                    .surface(cornerRadius: 22)
                }
                .padding(16)
            }
            .niyatBackground()
            .navigationTitle("More")
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
            .glassPanel(cornerRadius: 26, interactive: true)
        }
        .buttonStyle(.plain)
    }

    private func row<Destination: View>(_ title: String, systemImage: String,
                                        @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .foregroundStyle(Palette.emerald)
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
        .buttonStyle(.plain)
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
                        .background(Palette.emerald, in: .circle)
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
                    Text("Niyat").font(.display(34, weight: .heavy))
                    Text("نيّة · intention").font(.headline).foregroundStyle(Palette.emerald)
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
                .glassPanel(cornerRadius: 28, tint: Palette.deepEmerald.opacity(0.35))

                Text("Credits").sectionLabelStyle().padding(.top, 6)
                VStack(alignment: .leading, spacing: 14) {
                    credit("Quran text", "Tanzil Project (tanzil.net), Uthmani text. CC BY 3.0, used verbatim.")
                    credit("English translation", "Translation by Talal Itani, ClearQuran.com. CC BY-ND 4.0.")
                    credit("Surah information", "Tanzil Project metadata. CC BY 3.0.")
                    credit("Quran font", "Amiri Quran by Khaled Hosny and the Amiri Quran Project Authors. SIL Open Font License 1.1.")
                    credit("Prayer time calculation", "Adhan by Batoul Apps. MIT License.")
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
