import Adhan
import SwiftUI

// Small setup panels shown inside the tutorial, so people can change the
// setting being explained right there. Every change is saved immediately,
// exactly as if it were made in Settings.

/// Calculation method and Asr time.
struct TutorialPrayerSetup: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            LabeledContent("Location", value: model.location?.name ?? "Not set")
                .font(.subheadline)
            Divider().overlay(Palette.hairline)
            HStack {
                Text("Method").font(.subheadline)
                Spacer()
                Menu {
                    Picker("Method", selection: Binding(
                        get: { model.prayerSettings.method },
                        set: {
                            model.prayerSettings.method = $0
                            model.prayerSettings.methodChosenManually = true
                            model.settingsChanged()
                        }
                    )) {
                        ForEach(CalculationMethod.selectable, id: \.self) { Text($0.title).tag($0) }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(model.prayerSettings.method.title).lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down").font(.caption)
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Asr time").font(.subheadline)
                Picker("Asr time", selection: Binding(
                    get: { model.prayerSettings.madhab },
                    set: { model.prayerSettings.madhab = $0; model.settingsChanged() }
                )) {
                    ForEach(Madhab.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            if let schedule = model.schedule(for: .now) {
                Divider().overlay(Palette.hairline)
                HStack {
                    ForEach(schedule.times.filter { $0.name.isObligatory }, id: \.name) { time in
                        VStack(spacing: 2) {
                            Text(time.name.englishName).font(.caption2).foregroundStyle(.secondary)
                            Text(time.date.shortTime).font(.caption.monospacedDigit().weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .contentTransition(.numericText())
                .animation(.smooth, value: model.prayerSettings)
            }
        }
        .padding(18)
        .surface(cornerRadius: 22)
    }
}

/// Allow notifications, pick prayers and alert times, send a test.
struct TutorialNotificationSetup: View {
    @Environment(AppModel.self) private var model
    @State private var allowed: Bool?
    @State private var testSent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if allowed != true {
                Button {
                    Task {
                        allowed = await NotificationScheduler.requestAuthorization()
                        model.refresh()
                    }
                } label: {
                    Label("Allow notifications", systemImage: "bell.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(Palette.accent)
                .foregroundStyle(.black)
                .controlSize(.large)
                if allowed == false {
                    Text("Notifications are off. Turn them on in the Settings app › Notifications › Niyat.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }

            Text("Alert me for").font(.subheadline.weight(.semibold))
            HStack(spacing: 6) {
                ForEach(PrayerName.obligatory, id: \.self) { prayer in
                    let isOn = model.notificationSettings.enabledPrayers.contains(prayer)
                    Button {
                        if isOn {
                            model.notificationSettings.enabledPrayers.remove(prayer)
                        } else {
                            model.notificationSettings.enabledPrayers.insert(prayer)
                        }
                        model.settingsChanged()
                    } label: {
                        Text(prayer.englishName)
                            .font(.caption.weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .foregroundStyle(isOn ? .black : .white)
                            .background(isOn ? Palette.accent : Color.white.opacity(0.08), in: .rect(cornerRadius: 10))
                    }
                    .buttonStyle(.pressable)
                    .haptic(.selection, trigger: isOn)
                }
            }

            Text("Alert times").font(.subheadline.weight(.semibold))
            ForEach(AlertTiming.allCases) { timing in
                Toggle(timing.title, isOn: Binding(
                    get: { model.notificationSettings.timings.contains(timing) },
                    set: { isOn in
                        if isOn {
                            model.notificationSettings.timings.insert(timing)
                        } else {
                            model.notificationSettings.timings.remove(timing)
                        }
                        model.settingsChanged()
                    }
                ))
                .font(.subheadline)
            }

            Button {
                Task {
                    testSent = await NotificationScheduler.sendTest(location: model.location,
                                                                    current: model.currentPrayer(at: .now),
                                                                    next: model.nextPrayer(after: .now))
                    if testSent { allowed = true }
                }
            } label: {
                Label(testSent ? "Sent! Lock your phone, then press and hold it" : "Try it: send a test alert",
                      systemImage: testSent ? "checkmark.circle.fill" : "paperplane.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .haptic(.success, trigger: testSent)
        }
        .padding(18)
        .surface(cornerRadius: 22)
        .task { allowed = await NotificationScheduler.isAuthorized() }
    }
}

/// Daily goal and Qur'an reminders.
struct TutorialQuranSetup: View {
    @Environment(AppModel.self) private var model
    @State private var goal = QuranGoalModel.shared
    @State private var showReminders = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            GoalPicker(selection: Binding(get: { goal.goal ?? 10 }, set: { goal.setGoal($0) }))
            Divider().overlay(Palette.hairline)
            Toggle("Qur'an reminders", isOn: Binding(
                get: { model.quranReminders.isEnabled },
                set: { isOn in
                    model.quranReminders.isEnabled = isOn
                    if isOn, goal.goal == nil { goal.setGoal(10) }
                    Task { await NotificationScheduler.requestAuthorization() }
                    model.settingsChanged()
                }
            ))
            .font(.subheadline)
            Button("Choose reminder types and times") { showReminders = true }
                .font(.subheadline.weight(.semibold))
        }
        .padding(18)
        .surface(cornerRadius: 22)
        .sheet(isPresented: $showReminders) {
            NavigationStack { QuranNotificationsView(showsDone: true) }
        }
    }
}

/// Theme and haptics.
struct TutorialStyleSetup: View {
    @State private var themes = ThemeManager.shared
    @AppStorage(Haptics.settingKey) private var hapticsEnabled = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Theme").font(.subheadline.weight(.semibold))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(AppTheme.presets) { theme in
                    let selected = themes.selectedID == theme.id
                    Button {
                        withAnimation(.smooth) { themes.select(theme.id) }
                    } label: {
                        VStack(spacing: 6) {
                            ZStack {
                                Circle().fill(theme.glow.color)
                                Circle().fill(theme.accent.color).frame(width: 18, height: 18).offset(x: -7)
                                Circle().fill(theme.highlight.color).frame(width: 18, height: 18).offset(x: 7)
                            }
                            .frame(width: 46, height: 46)
                            .overlay { Circle().strokeBorder(selected ? Palette.highlight : .clear, lineWidth: 2) }
                            Text(theme.name).font(.caption.weight(selected ? .bold : .regular))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.pressable)
                    .haptic(.selection, trigger: selected)
                }
            }
            Divider().overlay(Palette.hairline)
            Toggle("Haptics", isOn: $hapticsEnabled).font(.subheadline)
        }
        .padding(18)
        .surface(cornerRadius: 22)
    }
}
