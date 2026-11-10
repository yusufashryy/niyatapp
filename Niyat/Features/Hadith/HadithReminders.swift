import Foundation
import SwiftUI
import UserNotifications

/// The daily hadith notification: on or off, and when.
struct HadithReminderSettings: Codable, Equatable {
    var isEnabled = false
    /// Minutes after midnight.
    var minute = 12 * 60

    init() {}

    // Tolerant decoding, so fields added later don't reset the setting.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .isEnabled)) ?? false
        minute = (try? c.decodeIfPresent(Int.self, forKey: .minute)) ?? 12 * 60
    }

    private enum CodingKeys: String, CodingKey { case isEnabled, minute }

    private static let key = "hadithReminders"

    static var saved: HadithReminderSettings {
        get { AppGroup.defaults.decoded(HadithReminderSettings.self, forKey: key) ?? HadithReminderSettings() }
        set { AppGroup.defaults.setEncoded(newValue, forKey: key) }
    }
}

extension HadithIndex {
    /// The bundled hadiths, read once, for work outside the screens (notifications).
    static let bundled: HadithIndex? = {
        guard let url = Bundle.main.url(forResource: "hadith-en", withExtension: "hadith"),
              let data = try? Data(contentsOf: url),
              let file = try? HadithFile.decode(compressed: data) else { return nil }
        return HadithIndex(file)
    }()
}

/// Which hadith goes out when. Pure, so it's tested.
enum HadithReminders {
    /// Days scheduled ahead (the app tops them up whenever it opens).
    static let daysAhead = 7

    /// Each upcoming day's notification: its time and that day's hadith (the
    /// same one the Hadith tab shows that day).
    static func plan(settings: HadithReminderSettings, index: HadithIndex, now: Date,
                     calendar: Calendar = .current) -> [(date: Date, hadith: Hadith)] {
        guard settings.isEnabled else { return [] }
        let today = calendar.startOfDay(for: now)
        return (0..<daysAhead).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let date = calendar.date(byAdding: .minute, value: settings.minute, to: day),
                  date > now,
                  let hadith = index.hadithOfTheDay(day, calendar: calendar) else { return nil }
            return (date, hadith)
        }
    }

    /// The notification text: the hadith's title, with its grade and source.
    static func content(for hadith: Hadith) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "Hadith of the day"
        content.subtitle = "\(hadith.level.title) · \(hadith.source)"
        content.body = hadith.title
        content.sound = .default
        content.threadIdentifier = "hadith"
        content.userInfo = [NotificationScheduler.UserInfoKey.kind: "hadith", "hadith": hadith.id]
        return content
    }
}

/// The setting itself, used in Settings and from the Hadith tab.
struct HadithNotificationSection: View {
    @Environment(AppModel.self) private var model
    @State private var settings = HadithReminderSettings.saved
    @State private var authorized = true

    var body: some View {
        Section {
            Toggle(isOn: $settings.isEnabled) {
                Label("Daily hadith", systemImage: "text.quote")
            }
            if settings.isEnabled {
                DatePicker("Time", selection: time, displayedComponents: .hourAndMinute)
            }
            if !authorized {
                Label("Notifications are off for Niyat. Turn them on in the Settings app › Notifications › Niyat.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Hadith notifications")
        } footer: {
            Text("One authentic hadith a day: the same one as the Hadith tab's hadith of the day. Tap it to read it in full.")
        }
        .onChange(of: settings) { _, new in
            HadithReminderSettings.saved = new
            model.refresh()
        }
        .onChange(of: settings.isEnabled) { _, isOn in
            guard isOn else { return }
            Task { authorized = await NotificationScheduler.requestAuthorization() }
        }
    }

    private var time: Binding<Date> {
        Binding(
            get: { Calendar.current.startOfDay(for: .now).addingTimeInterval(TimeInterval(settings.minute * 60)) },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                settings.minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }
}

/// The same setting as a small sheet from the Hadith tab's bell: exactly as
/// tall as what it shows.
struct HadithNotificationSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var settings = HadithReminderSettings.saved
    @State private var authorized = true
    @State private var height: CGFloat = 360

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Image(systemName: settings.isEnabled ? "bell.badge.fill" : "bell.fill")
                    .font(.title2)
                    .foregroundStyle(Palette.highlight)
                    .frame(width: 56, height: 56)
                    .background(Palette.highlight.opacity(0.14), in: .circle)
                    .contentTransition(.symbolEffect(.replace))
                Text("Daily hadith").font(.title3.weight(.bold))
                Text("One authentic hadith a day, the same as the hadith of the day. Tap it to read it in full.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 0) {
                Toggle("Send me one each day", isOn: $settings.isEnabled)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                if settings.isEnabled {
                    Divider().overlay(Palette.hairline).padding(.leading, 16)
                    DatePicker("Time", selection: time, displayedComponents: .hourAndMinute)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
            }
            .surface(cornerRadius: 20)

            if !authorized {
                Label("Notifications are off for Niyat. Turn them on in the Settings app › Notifications › Niyat.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button { dismiss() } label: {
                Text("Done").font(.headline).frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.glassProminent)
            .tint(Palette.control)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .padding(.bottom, 12)
        .readableWidth(520)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .presentationDetents([.height(height)])
        .presentationDragIndicator(.visible)
        .animation(.smooth, value: settings.isEnabled)
        .onChange(of: settings) { _, new in
            HadithReminderSettings.saved = new
            model.refresh()
        }
        .onChange(of: settings.isEnabled) { _, isOn in
            guard isOn else { return }
            Task { authorized = await NotificationScheduler.requestAuthorization() }
        }
    }

    private var time: Binding<Date> {
        Binding(
            get: { Calendar.current.startOfDay(for: .now).addingTimeInterval(TimeInterval(settings.minute * 60)) },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                settings.minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }
}
