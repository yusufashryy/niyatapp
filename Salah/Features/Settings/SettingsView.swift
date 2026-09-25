import Adhan
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var notificationsAuthorized = true

    var body: some View {
        @Bindable var model = model
        Form {
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
                Text("Different communities use different methods. If times don't match your local mosque, try another method or adjust them manually.")
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
                Picker("Reminder before", selection: $model.notificationSettings.reminderMinutesBefore) {
                    Text("Off").tag(0)
                    ForEach([5, 10, 15, 20, 30], id: \.self) { minutes in
                        Text("\(minutes) min").tag(minutes)
                    }
                }
            } header: {
                Text("Adhan notifications")
            } footer: {
                Text("iOS limits how many alerts an app can schedule, so open Salah at least once a week to keep them coming.")
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
                    LabeledContent("Current", value: location.name)
                    Text(String(format: "%.4f°, %.4f° · %@", location.latitude, location.longitude, location.timeZoneIdentifier))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                LocationPickerView(style: .settings) { location in
                    model.setLocation(location)
                    dismiss()
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
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
        .navigationTitle("Adjustments")
        .onChange(of: model.prayerSettings) { model.settingsChanged() }
    }
}
