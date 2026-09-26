import Speech
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
    @AppStorage("quran.tajweed") private var tajweedOn = true
    @AppStorage("quran.readingLayout") private var readingLayout = "verses"
    @AppStorage(QuranLineSpacing.key) private var lineHeight = QuranLineSpacing.standard
    @AppStorage(ReciterWordSync.settingKey) private var wordSync = true
    @State private var speechStatus = SFSpeechRecognizer.authorizationStatus()
    @State private var speechOnDevice = SFSpeechRecognizer(locale: Locale(identifier: "ar-SA"))?.supportsOnDeviceRecognition ?? false
    @State private var showMushaf = false

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section {
                    Picker("Open surahs as", selection: $readingLayout) {
                        Text("Mushaf pages").tag("pages")
                        Text("Verse by verse").tag("verses")
                    }
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
                    Text("Mushaf pages follow the 604 pages of the Madinah mushaf (Hafs), line for line: every page has the same 15 lines as the printed copy, drawn from Niyat's verified text.")
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
                    Toggle("Tajweed colours", isOn: $tajweedOn)
                    NavigationLink("Tajweed colour guide") { TajweedGuideView() }
                    if tajweedOn, store.edition != .uthmani {
                        Label("Tajweed colours show with the Uthmani script (Hafs). Switch the script above to see them.",
                              systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading) {
                        LabeledContent("Arabic size", value: "\(Int(arabicSize))")
                        Slider(value: $arabicSize, in: 20...48, step: 2)
                    }
                    VStack(alignment: .leading) {
                        LabeledContent("Line spacing", value: lineHeight <= QuranLineSpacing.standard + 0.01 ? "Tight, like print" : String(format: "%.1f×", lineHeight))
                        Slider(value: $lineHeight, in: QuranLineSpacing.range, step: 0.1)
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
                        Toggle("Follow the reciter word by word", isOn: Binding(
                            get: { wordSync && speechStatus == .authorized && speechOnDevice },
                            set: { on in
                                wordSync = on
                                ReciterWordSync.shared.reset()
                                guard on, speechStatus == .notDetermined else { return }
                                SFSpeechRecognizer.requestAuthorization { status in
                                    Task { @MainActor in speechStatus = status }
                                }
                            }))
                            .disabled(!speechOnDevice || speechStatus == .denied || speechStatus == .restricted)
                    } else {
                        Label("No verified verse-by-verse audio for \(store.edition.riwayah.title) yet, so recitation is off to keep text and audio in sync.",
                              systemImage: "speaker.slash")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Recitation")
                } footer: {
                    if store.edition.riwayah.hasVerseAudio { Text(wordSyncFooter) }
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

    private var wordSyncFooter: String {
        let what = "Highlights each word as the reciter says it."
        if !speechOnDevice {
            return what + " This iPhone can't recognise Arabic speech on the device, so the whole ayah is highlighted instead."
        }
        if speechStatus == .denied || speechStatus == .restricted {
            return what + " Allow Speech Recognition for Niyat in the Settings app to use it."
        }
        return what + " The recitations don't come with word timings, so Niyat lines each ayah's audio up with the text on your iPhone, with Apple's speech recognition. Ayat it can't line up confidently are highlighted as a whole. Nothing leaves your iPhone."
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
