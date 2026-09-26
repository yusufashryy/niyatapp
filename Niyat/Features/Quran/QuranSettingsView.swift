import SwiftUI

/// Qur'an › Settings: reading, script, recitation and daily goal, in one sheet
/// so the reader itself stays uncluttered.
struct QuranSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @State private var store = QuranStore.shared
    @State private var player = RecitationPlayer.shared
    @State private var goal = QuranGoalModel.shared
    @AppStorage("quran.arabicSize") private var arabicSize = 30.0
    @AppStorage("quran.showTranslation") private var showTranslation = true
    @State private var showMushaf = false

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section {
                    Button {
                        showMushaf = true
                    } label: {
                        Label("Read by mushaf page", systemImage: "book.pages")
                    }
                    NavigationLink {
                        QuranNotificationsView()
                    } label: {
                        Label("Qur'an notifications", systemImage: "bell.badge")
                    }
                } footer: {
                    Text("Page view follows the 604 pages of the Madinah mushaf (Hafs), using Tanzil's verified page divisions. Niyat typesets the text itself, so line breaks can differ from a printed copy.")
                }

                Section {
                    Picker("Qira'ah / Riwayah", selection: Binding(
                        get: { store.edition.riwayah },
                        set: { riwayah in select(riwayah.editions.first ?? .default) }
                    )) {
                        ForEach(Riwayah.allCases) { riwayah in
                            VStack(alignment: .leading) {
                                Text(riwayah.title)
                                Text(riwayah.arabicTitle).font(.caption).foregroundStyle(.secondary)
                            }
                            .tag(riwayah)
                        }
                    }
                    .pickerStyle(.navigationLink)

                    if store.edition.riwayah.editions.count > 1 {
                        Picker("Script", selection: Binding(get: { store.edition }, set: { select($0) })) {
                            ForEach(store.edition.riwayah.editions) { edition in
                                VStack(alignment: .leading) {
                                    Text(edition.title)
                                    Text(edition.detail).font(.caption).foregroundStyle(.secondary)
                                }
                                .tag(edition)
                            }
                        }
                        .pickerStyle(.navigationLink)
                    }

                    Toggle("Show translation", isOn: $showTranslation)
                    VStack(alignment: .leading) {
                        LabeledContent("Arabic size", value: "\(Int(arabicSize))")
                        Slider(value: $arabicSize, in: 20...48, step: 2)
                    }
                    Text("بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ")
                        .font(.quran(size: arabicSize))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .foregroundStyle(Palette.highlight)
                        .accessibilityLabel("Preview of the Arabic size")
                } header: {
                    Text("Reading")
                } footer: {
                    Text("\(store.edition.riwayah.detail) Text source: \(store.edition.source) Bookmarks and your reading position carry over when you switch.")
                }

                Section {
                    if store.edition.riwayah.hasVerseAudio {
                        NavigationLink {
                            ReciterPicker(embedded: true)
                        } label: {
                            LabeledContent("Reciter", value: player.reciter.name)
                        }
                        Toggle("Continue to the next verse", isOn: Binding(
                            get: { player.continuous }, set: { player.continuous = $0 }))
                    } else {
                        Label("No verified verse-by-verse audio for \(store.edition.riwayah.title) yet, so recitation is off to keep text and audio in sync.",
                              systemImage: "speaker.slash")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Recitation")
                }

                Section {
                    GoalPicker(selection: Binding(get: { goal.goal ?? 10 }, set: { goal.setGoal($0) }))
                    Toggle("Qur'an notifications", isOn: Binding(
                        get: { model.quranReminders.isEnabled },
                        set: { isOn in
                            model.quranReminders.isEnabled = isOn
                            if isOn, goal.goal == nil { goal.setGoal(10) }
                            Task { await NotificationScheduler.requestAuthorization() }
                            model.settingsChanged()
                        }
                    ))
                    if model.quranReminders.isEnabled {
                        NavigationLink("Choose reminders") { QuranNotificationsView() }
                    }
                } header: {
                    Text("Daily goal")
                } footer: {
                    Text("A verse counts once it has been on screen for a few seconds, once per day. Changing your goal only affects today onwards. The afternoon reminder only comes if you haven't finished.")
                }
            }
            .scrollContentBackground(.hidden)
            .niyatBackground()
            .navigationTitle("Qur'an settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.large])
        .fullScreenCover(isPresented: $showMushaf) { MushafPageView() }
    }

    private func select(_ edition: QuranEdition) {
        if !edition.riwayah.hasVerseAudio { player.stop() }
        Task { await store.setEdition(edition) }
    }
}

/// 5 / 10 / 20 ayat or a custom number.
struct GoalPicker: View {
    @Binding var selection: Int
    private let presets = [5, 10, 20]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ayat per day").font(.subheadline.weight(.semibold))
            HStack(spacing: 8) {
                ForEach(presets, id: \.self) { value in
                    Button {
                        selection = value
                    } label: {
                        Text("\(value)")
                            .font(.headline.monospacedDigit())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .foregroundStyle(selection == value ? .black : .white)
                            .background(selection == value ? Palette.accent : Color.white.opacity(0.08), in: .rect(cornerRadius: 12))
                    }
                    .buttonStyle(.pressable)
                }
            }
            Stepper(value: $selection, in: 1...300) {
                Text(presets.contains(selection) ? "Custom" : "Custom: \(selection) ayat")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .haptic(.selection, trigger: selection)
        .padding(.vertical, 4)
    }
}

/// Tapping the goal pill: today's progress, streak and the goal setting.
struct QuranGoalSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var goal = QuranGoalModel.shared

    var body: some View {
        VStack(spacing: 20) {
            Text("Today's Qur'an").sectionLabelStyle().padding(.top, 20)
            ZStack {
                Circle().stroke(.white.opacity(0.1), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: goal.progress)
                    .stroke(goal.today.isComplete ? Palette.highlight : Palette.accent,
                            style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text("\(goal.today.count)")
                        .font(.display(44, weight: .heavy))
                        .contentTransition(.numericText(value: Double(goal.today.count)))
                    Text(goal.goal.map { "of \($0) ayat" } ?? "ayat today")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 170, height: 170)

            Label("\(goal.streak)-day Qur'an streak", systemImage: "flame.fill")
                .font(.headline)
                .foregroundStyle(goal.streak > 0 ? Palette.highlight : .secondary)

            GoalPicker(selection: Binding(get: { goal.goal ?? 10 }, set: { goal.setGoal($0) }))
                .padding(16)
                .surface(cornerRadius: 20)
                .padding(.horizontal, 20)

            Button("Done") { dismiss() }
                .buttonStyle(.glass)
                .controlSize(.large)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
