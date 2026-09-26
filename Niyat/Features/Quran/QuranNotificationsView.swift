import SwiftUI
import UserNotifications

/// Qur'an › Notifications: choose which Qur'an reminders you get and when.
struct QuranNotificationsView: View {
    /// Shows a Done button when presented on its own (not pushed from settings).
    var showsDone = false

    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @State private var goal = QuranGoalModel.shared
    @State private var authorized = true
    @State private var testSent = false

    init(showsDone: Bool = false) {
        self.showsDone = showsDone
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: binding(\.isEnabled)) {
                    Label("Qur'an notifications", systemImage: "bell.badge.fill")
                }
                .onChange(of: model.quranReminders.isEnabled) { _, isOn in
                    guard isOn else { return }
                    Task { authorized = await NotificationScheduler.requestAuthorization() }
                }
                if !authorized {
                    Label("Notifications are off for Niyat. Turn them on in the Settings app › Notifications › Niyat.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            } footer: {
                Text("Each type below can be turned on or off on its own. Tapping a notification opens the Qur'an right where it's needed.")
            }

            if model.quranReminders.isEnabled {
                Section {
                    if goal.goal == nil {
                        Button("Set a daily goal first") { goal.setGoal(10) }
                    }
                    reminderRow("Morning reminder", icon: "sunrise.fill", isOn: \.morningEnabled, minute: \.morningMinute)
                    reminderRow("Afternoon check-in", icon: "sun.max.fill", isOn: \.afternoonEnabled, minute: \.afternoonMinute)
                    if model.quranReminders.afternoonEnabled {
                        Toggle("Tell me when I've finished", isOn: binding(\.sendCompletionMessage))
                    }
                    reminderRow("Streak at risk", icon: "flame.fill", isOn: \.eveningEnabled, minute: \.eveningMinute)
                } header: {
                    Text("Daily goal")
                } footer: {
                    Text("Goal reminders only come on days you haven't finished yet, and stop once you reach your goal.")
                }
                .disabled(goal.goal == nil)

                Section {
                    reminderRow("Verse of the day", icon: "text.book.closed.fill", isOn: \.verseOfDayEnabled, minute: \.verseOfDayMinute)
                    reminderRow("Friday: Surah Al-Kahf", icon: "moon.stars.fill", isOn: \.kahfEnabled, minute: \.kahfMinute)
                } header: {
                    Text("Reading")
                } footer: {
                    Text("Verse of the day uses the same verified verse as the Today screen and widget (Tanzil text, ClearQuran translation).")
                }

                Section {
                    Button {
                        Task { await sendTest() }
                    } label: {
                        Label(testSent ? "Sent. Lock your phone to see it" : "Send a test in 5 seconds",
                              systemImage: testSent ? "checkmark.circle.fill" : "paperplane.fill")
                    }
                    .haptic(.success, trigger: testSent)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .niyatBackground()
        .navigationTitle("Qur'an notifications")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsDone {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .animation(.smooth, value: model.quranReminders)
        .task { authorized = await NotificationScheduler.isAuthorized() || !model.quranReminders.isEnabled }
    }

    private func reminderRow(_ title: String, icon: String,
                             isOn: WritableKeyPath<QuranReminderSettings, Bool>,
                             minute: WritableKeyPath<QuranReminderSettings, Int>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: binding(isOn)) {
                Label(title, systemImage: icon)
            }
            if model.quranReminders[keyPath: isOn] {
                DatePicker("Time", selection: minuteBinding(minute), displayedComponents: .hourAndMinute)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func binding<T>(_ keyPath: WritableKeyPath<QuranReminderSettings, T>) -> Binding<T> {
        Binding(
            get: { model.quranReminders[keyPath: keyPath] },
            set: { model.quranReminders[keyPath: keyPath] = $0; model.settingsChanged() }
        )
    }

    /// Binds a "minutes after midnight" setting to a DatePicker.
    private func minuteBinding(_ keyPath: WritableKeyPath<QuranReminderSettings, Int>) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.startOfDay(for: .now).addingTimeInterval(TimeInterval(model.quranReminders[keyPath: keyPath] * 60))
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                model.quranReminders[keyPath: keyPath] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
                model.settingsChanged()
            }
        )
    }

    private func sendTest() async {
        guard await NotificationScheduler.requestAuthorization() else { authorized = false; return }
        let content = UNMutableNotificationContent()
        let verse = DailyVerse.forDay(.now)
        content.title = "Verse of the day · \(verse.reference)"
        content.body = verse.english
        content.sound = .default
        content.threadIdentifier = "quran"
        content.userInfo = [NotificationScheduler.UserInfoKey.kind: "quran",
                            NotificationScheduler.UserInfoKey.surah: verse.surah,
                            NotificationScheduler.UserInfoKey.verse: verse.ayah]
        let request = UNNotificationRequest(identifier: "quran.test", content: content,
                                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false))
        try? await UNUserNotificationCenter.current().add(request)
        testSent = true
    }
}
