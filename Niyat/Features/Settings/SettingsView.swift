import Adhan
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var notificationsAuthorized = true
    @AppStorage(Haptics.settingKey) private var hapticsEnabled = true
    @State private var testMessage: String?

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Appearance") {
                NavigationLink {
                    ThemePickerView()
                } label: {
                    LabeledContent {
                        HStack(spacing: 6) {
                            Circle().fill(Palette.accent).frame(width: 12, height: 12)
                            Circle().fill(Palette.highlight).frame(width: 12, height: 12)
                            Text(ThemeManager.shared.theme.name)
                        }
                    } label: {
                        Label("Theme", systemImage: "paintpalette.fill")
                    }
                }
                Toggle(isOn: $hapticsEnabled) {
                    Label("Haptics", systemImage: "hand.tap.fill")
                }
            }

            Section("Location") {
                NavigationLink {
                    LocationSettingsView()
                } label: {
                    LabeledContent("Location", value: model.location?.name ?? "Not set")
                }
            }

            Section {
                Picker("Method", selection: Binding(
                    get: { model.prayerSettings.method },
                    set: {
                        model.prayerSettings.method = $0
                        model.prayerSettings.methodChosenManually = true
                    }
                )) {
                    ForEach(CalculationMethod.selectable, id: \.self) { method in
                        Text(method.title).tag(method)
                    }
                }
                .pickerStyle(.navigationLink)
                Picker("Asr time", selection: $model.prayerSettings.madhab) {
                    ForEach(Madhab.allCases, id: \.self) { madhab in
                        Text(madhab.title).tag(madhab)
                    }
                }
                Picker("High latitudes", selection: $model.prayerSettings.highLatitude) {
                    ForEach(HighLatitudeOption.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                NavigationLink("Adjust times manually") { AdjustmentsView() }
            } header: {
                Text("Calculation")
            } footer: {
                Text("Different communities use different methods. If times don't match your local mosque, try another method or adjust them manually. Hanafi Asr starts later than the Standard (Shafi'i, Maliki, Hanbali) time.")
            }

            Section {
                if !notificationsAuthorized {
                    Button("Allow notifications") {
                        Task {
                            notificationsAuthorized = await NotificationScheduler.requestAuthorization()
                            model.refresh()
                        }
                    }
                }
                ForEach(PrayerName.allCases) { prayer in
                    Toggle(prayer.englishName, isOn: Binding(
                        get: { model.notificationSettings.enabledPrayers.contains(prayer) },
                        set: { isOn in
                            if isOn {
                                model.notificationSettings.enabledPrayers.insert(prayer)
                            } else {
                                model.notificationSettings.enabledPrayers.remove(prayer)
                            }
                        }
                    ))
                }
                NavigationLink {
                    AlertTimingsView()
                } label: {
                    LabeledContent("Alert times", value: "\(model.notificationSettings.timings.count) per prayer")
                }
                Button {
                    Task {
                        let sent = await NotificationScheduler.sendTest(location: model.location,
                                                                        current: model.currentPrayer(at: .now),
                                                                        next: model.nextPrayer(after: .now))
                        testMessage = sent ? "Sent! It arrives in 5 seconds. Lock your phone, then press and hold the alert to try Log Prayer."
                                           : "Notifications are off. Turn them on in the iPhone Settings app › Notifications › Niyat."
                    }
                } label: {
                    Label("Send a test notification", systemImage: "bell.and.waves.left.and.right.fill")
                }
                if let testMessage {
                    Text(testMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                NavigationLink {
                    ScheduledAlertsView()
                } label: {
                    Label("Scheduled alerts", systemImage: "list.bullet.clipboard.fill")
                }
            } header: {
                Text("Adhan notifications")
            } footer: {
                Text("iOS limits how many alerts an app can queue, so the more alert times you choose, the fewer days ahead are covered. Open Niyat every couple of days to keep them coming.")
            }

            Section {
                Stepper(value: $model.hijriAdjustment, in: -2...2) {
                    LabeledContent("Hijri date", value: HijriDate.string(for: .now, adjustmentDays: model.hijriAdjustment))
                }
            } header: {
                Text("Hijri calendar")
            } footer: {
                Text("Shift by a day or two to match the moon sighting where you live.")
            }
        }
        .scrollContentBackground(.hidden)
        .niyatBackground()
        .navigationTitle("Settings")
        .onChange(of: model.prayerSettings) { model.settingsChanged() }
        .onChange(of: model.notificationSettings) { model.settingsChanged() }
        .onChange(of: model.hijriAdjustment) { model.settingsChanged() }
        .task { notificationsAuthorized = await NotificationScheduler.isAuthorized() }
    }
}

private struct LocationSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let location = model.location {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Current").sectionLabelStyle()
                        Text(location.name).font(.title3.weight(.bold))
                        Text(String(format: "%.4f°, %.4f° · %@", location.latitude, location.longitude, location.timeZoneIdentifier))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .glassPanel(cornerRadius: 24)
                }
                LocationPickerView { location in
                    model.setLocation(location)
                    dismiss()
                }
            }
            .padding()
        }
        .niyatBackground()
        .navigationTitle("Location")
    }
}

private struct AdjustmentsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                ForEach(PrayerName.allCases) { prayer in
                    let minutes = model.prayerSettings.adjustment(for: prayer)
                    Stepper(value: Binding(
                        get: { minutes },
                        set: { model.prayerSettings.setAdjustment($0, for: prayer) }
                    ), in: -30...30) {
                        LabeledContent(prayer.englishName, value: minutes == 0 ? "—" : String(format: "%+d min", minutes))
                    }
                }
            } footer: {
                Text("Nudge any time to match your local mosque's timetable.")
            }
        }
        .scrollContentBackground(.hidden)
        .niyatBackground()
        .navigationTitle("Adjustments")
        .onChange(of: model.prayerSettings) { model.settingsChanged() }
    }
}

/// Lists the adhan alerts iOS currently has queued, so you can check they're set.
private struct ScheduledAlertsView: View {
    @State private var alerts: [NotificationScheduler.ScheduledAlert] = []
    @State private var loaded = false

    var body: some View {
        List {
            if loaded, alerts.isEmpty {
                ContentUnavailableView("No alerts scheduled", systemImage: "bell.slash",
                                       description: Text("Allow notifications and turn on at least one prayer."))
            }
            ForEach(alerts) { alert in
                HStack {
                    Text(alert.title)
                    Spacer()
                    Text(alert.date.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .niyatBackground()
        .navigationTitle("\(alerts.count) scheduled")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            alerts = await NotificationScheduler.scheduledAlerts()
            loaded = true
        }
    }
}

/// Which of the four alerts to send for each prayer.
private struct AlertTimingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                ForEach(AlertTiming.allCases) { timing in
                    Toggle(isOn: Binding(
                        get: { model.notificationSettings.timings.contains(timing) },
                        set: { isOn in
                            if isOn {
                                model.notificationSettings.timings.insert(timing)
                            } else {
                                model.notificationSettings.timings.remove(timing)
                            }
                            model.settingsChanged()
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(timing.title)
                            if timing.offersLogging {
                                Text("Has a Log Prayer button").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } footer: {
                Text("These apply to every prayer you've turned on. Press and hold an alert (or pull it down) to use Log Prayer without opening the app. Logging a prayer cancels its \"30 minutes after\" alert.")
            }
        }
        .scrollContentBackground(.hidden)
        .niyatBackground()
        .navigationTitle("Alert times")
        .haptic(.selection, trigger: model.notificationSettings.timings)
    }
}
