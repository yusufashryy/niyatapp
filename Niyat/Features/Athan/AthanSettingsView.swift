import SwiftUI

/// Settings › Athan: which muezzin calls each prayer, Fajr's own choice, and
/// whether opening the alert plays the whole athan.
struct AthanSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var settings = SettingsStore.athan
    @State private var player = AthanPlayer.shared

    var body: some View {
        Form {
            Section {
                row(nil)
                ForEach(Muezzin.allCases) { row($0) }
            } header: {
                Text("When a prayer begins")
            } footer: {
                Text("The alert plays the opening of the athan (iOS lets an alert sound last up to 30 seconds). Tap ▶ to hear it. The reminders before and after a prayer keep the standard sound.")
            }

            Section {
                Picker("Fajr", selection: $settings.fajrMuezzin) {
                    Text("Same as the others").tag(Muezzin?.none)
                    ForEach(Muezzin.allCases) { Text(title($0)).tag(Muezzin?.some($0)) }
                }
            } footer: {
                Text("A different voice to wake up to, if you like.")
            }

            Section {
                Toggle("Play the full athan", isOn: $settings.playsFullAthan)
            } footer: {
                Text("When you open the alert, or Niyat is open when it comes, the whole athan plays, with a Stop button. It streams, so it needs internet; without it, the opening plays instead.")
            }

            Section {
                Text("Recordings from Aladhan.com (Islamic Network).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .niyatBackground()
        .navigationTitle("Athan")
        .navigationBarTitleDisplayMode(.inline)
        .haptic(.selection, trigger: settings.muezzin)
        .onChange(of: settings) { _, new in
            SettingsStore.athan = new
            model.settingsChanged()
        }
        .onDisappear { if player.isPreview { player.stop() } }
    }

    /// A choice of athan (nil: the standard alert sound), with a preview button.
    private func row(_ muezzin: Muezzin?) -> some View {
        let chosen = settings.muezzin == muezzin
        return HStack(spacing: 12) {
            Button {
                settings.muezzin = muezzin
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(muezzin?.name ?? "Standard alert sound")
                            .foregroundStyle(.primary)
                        if let detail = muezzin?.detail {
                            Text(detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 8)
                    if chosen {
                        Image(systemName: "checkmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Palette.control)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.borderless)
            .accessibilityAddTraits(chosen ? .isSelected : [])

            if let muezzin {
                let previewing = player.playing == muezzin && player.isPreview
                Button {
                    player.preview(muezzin)
                } label: {
                    Image(systemName: previewing ? "stop.circle.fill" : "play.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Palette.control)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(previewing ? "Stop" : "Hear \(title(muezzin))")
            }
        }
    }

    private func title(_ muezzin: Muezzin) -> String {
        muezzin.detail.map { "\(muezzin.name) (\($0))" } ?? muezzin.name
    }
}
