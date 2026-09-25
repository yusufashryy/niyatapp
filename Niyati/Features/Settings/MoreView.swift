import SwiftUI

struct MoreView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink { TasbihView() } label: {
                        Label("Tasbih counter", systemImage: "circle.hexagongrid.fill")
                    }
                    NavigationLink { WidgetGuideView() } label: {
                        Label("Add widgets", systemImage: "square.grid.2x2.fill")
                    }
                }
                Section {
                    NavigationLink { SettingsView() } label: {
                        Label("Settings", systemImage: "gearshape.fill")
                    }
                    NavigationLink { AboutView() } label: {
                        Label("About & credits", systemImage: "info.circle.fill")
                    }
                }
            }
            .navigationTitle("More")
        }
    }
}

private struct WidgetGuideView: View {
    var body: some View {
        List {
            Section("Home Screen") {
                step(1, "Touch and hold an empty spot on your Home Screen until the apps jiggle.")
                step(2, "Tap Edit (or +) in the top corner, then Add Widget.")
                step(3, "Search for Niyati and pick a widget: Next Prayer, Prayer Times, Verse of the Day or Tasbih.")
            }
            Section("Lock Screen") {
                step(1, "Touch and hold your Lock Screen, then tap Customize › Lock Screen.")
                step(2, "Tap the widget area under the clock and add Next Prayer.")
            }
        }
        .navigationTitle("Widgets")
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.footnote.bold())
                .frame(width: 24, height: 24)
                .background(Color.niyatiGreen, in: .circle)
                .foregroundStyle(.white)
            Text(text)
        }
    }
}

struct AboutView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Niyati").font(.title.bold())
                    Text("A free, open-source companion for your deen. No ads, no subscriptions, no accounts and no tracking. Everything runs on your phone.")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                Link(destination: URL(string: "https://github.com/yusufashryy/niyatiapp")!) {
                    Label("Source code on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
            }

            Section("Credits") {
                credit("Quran text", "Tanzil Project (tanzil.net), Uthmani text. CC BY 3.0, used verbatim.")
                credit("English translation", "Translation by Talal Itani, ClearQuran.com. CC BY-ND 4.0.")
                credit("Surah information", "Tanzil Project metadata. CC BY 3.0.")
                credit("Quran font", "Amiri Quran by Khaled Hosny and the Amiri Quran Project Authors. SIL Open Font License 1.1.")
                credit("Prayer time calculation", "Adhan by Batoul Apps. MIT License.")
            }

            Section {
                Text("May Allah accept it from us and from you.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("About")
    }

    private func credit(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(detail).font(.footnote).foregroundStyle(.secondary)
        }
    }
}
