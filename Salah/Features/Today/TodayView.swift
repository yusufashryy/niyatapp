import SwiftUI

struct TodayView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            // Re-render every 30s so "next prayer" and highlights move on by themselves.
            TimelineView(.periodic(from: .now, by: 30)) { context in
                content(now: context.date)
            }
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let schedule = model.schedule(for: now)
        let next = model.nextPrayer(after: now)
        let current = model.currentPrayer(at: now)

        ScrollView {
            VStack(spacing: 16) {
                header(now: now, next: next)

                if let schedule {
                    VStack(spacing: 0) {
                        ForEach(schedule.times) { time in
                            PrayerRow(time: time,
                                      isCurrent: time.id == current?.id && time.name.isObligatory,
                                      isNext: time.id == next?.id,
                                      day: schedule.day)
                            if time.name != .isha { Divider().padding(.leading, 56) }
                        }
                    }
                    .background(.background.secondary, in: .rect(cornerRadius: 18))
                }

                StreakCard(streak: model.streak(asOf: now))

                if let location = model.location {
                    Text("\(model.prayerSettings.method.title) · Asr: \(model.prayerSettings.madhab == .hanafi ? "Hanafi" : "Standard") · \(location.name)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }

    private func header(now: Date, next: PrayerTime?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(model.location?.name ?? "No location", systemImage: "location.fill")
                    .font(.subheadline.weight(.medium))
                Spacer()
            }
            .foregroundStyle(.white.opacity(0.85))

            if let next {
                Text("Next: \(next.name.displayName(on: next.date))")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.salahGold)
                Text(next.date, style: .timer)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("at \(next.date.shortTime)")
                    .foregroundStyle(.white.opacity(0.85))
            }

            Divider().overlay(.white.opacity(0.3))

            HStack {
                Text(now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                Spacer()
                Text(HijriDate.string(for: now, adjustmentDays: model.hijriAdjustment))
            }
            .font(.footnote)
            .foregroundStyle(.white.opacity(0.85))
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.salahBackground, in: .rect(cornerRadius: 22))
    }
}

private struct PrayerRow: View {
    @Environment(AppModel.self) private var model
    let time: PrayerTime
    let isCurrent: Bool
    let isNext: Bool
    let day: Date

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: time.name.symbolName)
                .font(.title3)
                .frame(width: 28)
                .foregroundStyle(isCurrent || isNext ? Color.salahGold : Color.salahGreen)

            VStack(alignment: .leading, spacing: 2) {
                Text(time.name.displayName(on: time.date))
                    .font(.body.weight(isCurrent ? .bold : .regular))
                Text(time.name.arabicName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isNext {
                Text("NEXT")
                    .font(.caption2.bold())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.salahGold.opacity(0.25), in: .capsule)
            }

            Text(time.date.shortTime)
                .font(.body.monospacedDigit().weight(isCurrent ? .bold : .regular))

            notificationButton

            if time.name.isObligatory {
                prayedButton
            } else {
                Color.clear.frame(width: 28)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(isCurrent ? Color.salahGreen.opacity(0.10) : .clear)
    }

    private var notificationButton: some View {
        let enabled = model.notificationSettings.enabledPrayers.contains(time.name)
        return Button {
            if enabled {
                model.notificationSettings.enabledPrayers.remove(time.name)
            } else {
                model.notificationSettings.enabledPrayers.insert(time.name)
                Task { await NotificationScheduler.requestAuthorization() }
            }
            model.settingsChanged()
        } label: {
            Image(systemName: enabled ? "bell.fill" : "bell.slash")
                .foregroundStyle(enabled ? Color.salahGreen : .secondary)
                .frame(width: 28)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(enabled ? "Turn off \(time.name.englishName) alert" : "Turn on \(time.name.englishName) alert")
    }

    private var prayedButton: some View {
        let prayed = model.isPrayed(time.name, on: day)
        return Button {
            model.togglePrayed(time.name, on: day)
        } label: {
            Image(systemName: prayed ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(prayed ? Color.salahGreen : .secondary)
                .frame(width: 28)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.success, trigger: prayed) { _, new in new }
        .accessibilityLabel(prayed ? "Mark \(time.name.englishName) as not prayed" : "Mark \(time.name.englishName) as prayed")
    }
}

private struct StreakCard: View {
    let streak: Int

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "flame.fill")
                .font(.title)
                .foregroundStyle(.orange)
            VStack(alignment: .leading) {
                Text(streak == 1 ? "1 day streak" : "\(streak) day streak").font(.headline)
                Text("Tick off each prayer after you pray it. Days with all five count toward your streak.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(.background.secondary, in: .rect(cornerRadius: 18))
    }
}
