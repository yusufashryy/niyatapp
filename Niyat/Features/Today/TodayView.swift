import SwiftUI

struct TodayView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            // Re-render every 30s so "next prayer" and highlights move on by themselves.
            TimelineView(.periodic(from: .now, by: 30)) { context in
                ScrollView {
                    content(now: context.date)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                }
                .scrollEdgeEffectStyle(.soft, for: .top)
            }
            .niyatBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        .font(.headline)
                        .fixedSize()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                    .accessibilityLabel("Settings")
                }
            }
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let schedule = model.schedule(for: now)
        let next = model.nextPrayer(after: now)
        let current = model.currentPrayer(at: now)

        VStack(spacing: 14) {
            if let next {
                NextPrayerHero(next: next, schedule: schedule, now: now,
                               locationName: model.location?.name ?? "",
                               hijri: HijriDate.string(for: now, adjustmentDays: model.hijriAdjustment))
            }

            if let schedule {
                VStack(spacing: 8) {
                    ForEach(schedule.times) { time in
                        PrayerRow(time: time,
                                  isCurrent: time.id == current?.id && time.name.isObligatory,
                                  isNext: time.id == next?.id,
                                  day: schedule.day)
                    }
                }
            }

            WeekTracker(now: now)

            Text("\(model.prayerSettings.method.title) · Asr: \(model.prayerSettings.madhab.title)")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
    }
}

// MARK: - Hero

private struct NextPrayerHero: View {
    let next: PrayerTime
    let schedule: DaySchedule?
    let now: Date
    let locationName: String
    let hijri: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(locationName, systemImage: "location.fill")
                    .lineLimit(1)
                Spacer()
                Text(hijri)
                    .lineLimit(1)
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text("Next prayer")
                    .sectionLabelStyle()
                    .foregroundStyle(Palette.emerald)
                HStack(alignment: .firstTextBaseline) {
                    Text(next.name.displayName(on: next.date))
                        .font(.display(34))
                    Spacer()
                    Text(next.name.arabicName)
                        .font(.quran(size: 30))
                        .foregroundStyle(Palette.gold)
                }
                Text(next.date.shortTime)
                    .font(.display(64, weight: .heavy))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                Image(systemName: "timer")
                Text("in \(Text(next.date, style: .timer))")
                    .monospacedDigit()
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(.regular.tint(Palette.emerald.opacity(0.35)), in: .capsule)

            if let schedule {
                DayTimeline(schedule: schedule, now: now)
                    .padding(.top, 4)
            }
        }
        .foregroundStyle(.white)
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: 32, tint: Palette.deepEmerald.opacity(0.35))
    }
}

/// A line across the day with a dot for each prayer and a glowing marker for "now".
private struct DayTimeline: View {
    let schedule: DaySchedule
    let now: Date

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.14))
                    .frame(height: 4)
                Capsule()
                    .fill(LinearGradient(colors: [Palette.emerald, Palette.gold], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(0, width * fraction(now)), height: 4)
                ForEach(schedule.times) { time in
                    Circle()
                        .fill(time.date <= now ? Palette.gold : Color.white.opacity(0.4))
                        .frame(width: 8, height: 8)
                        .offset(x: width * fraction(time.date) - 4)
                }
                Circle()
                    .fill(.white)
                    .frame(width: 14, height: 14)
                    .shadow(color: Palette.emerald, radius: 8)
                    .offset(x: width * fraction(now) - 7)
            }
            .frame(height: 16)
        }
        .frame(height: 16)
        .accessibilityHidden(true)
    }

    private func fraction(_ date: Date) -> CGFloat {
        CGFloat(min(max(date.timeIntervalSince(schedule.day) / 86_400, 0), 1))
    }
}

// MARK: - Rows

private struct PrayerRow: View {
    @Environment(AppModel.self) private var model
    let time: PrayerTime
    let isCurrent: Bool
    let isNext: Bool
    let day: Date

    var body: some View {
        let row = HStack(spacing: 14) {
            Image(systemName: time.name.symbolName)
                .font(.body.weight(.semibold))
                .foregroundStyle(isNext || isCurrent ? Palette.gold : Palette.emerald)
                .frame(width: 36, height: 36)
                .background(.white.opacity(0.08), in: .circle)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(time.name.displayName(on: time.date))
                        .font(.body.weight(.semibold))
                    if isNext {
                        Text("NEXT")
                            .font(.caption2.weight(.heavy))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Palette.gold, in: .capsule)
                    } else if isCurrent {
                        Text("NOW")
                            .font(.caption2.weight(.heavy))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Palette.emerald, in: .capsule)
                    }
                }
                Text(time.name.arabicName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            Text(time.date.shortTime)
                .font(.body.monospacedDigit().weight(.semibold))
                .lineLimit(1)
                .fixedSize()

            notificationButton

            if time.name.isObligatory {
                prayedButton
            } else {
                Color.clear.frame(width: 30)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)

        if isNext {
            row.glassPanel(cornerRadius: 22, tint: Palette.emerald.opacity(0.22))
        } else {
            row.surface()
                .opacity(time.date < .now && !isCurrent ? 0.75 : 1)
        }
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
                .foregroundStyle(enabled ? Color.white : Color.secondary)
                .frame(width: 30, height: 30)
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
                .font(.title2)
                .foregroundStyle(prayed ? Palette.emerald : Color.white.opacity(0.35))
                .frame(width: 30, height: 30)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.success, trigger: prayed) { _, new in new }
        .accessibilityLabel(prayed ? "Mark \(time.name.englishName) as not prayed" : "Mark \(time.name.englishName) as prayed")
    }
}

// MARK: - Week tracker

private struct WeekTracker: View {
    @Environment(AppModel.self) private var model
    let now: Date

    var body: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let days = (0..<7).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
        let streak = model.streak(asOf: now)

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("This week").sectionLabelStyle()
                Spacer()
                Label(streak == 1 ? "1 day streak" : "\(streak) day streak", systemImage: "flame.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(streak > 0 ? Palette.gold : .secondary)
            }
            HStack {
                ForEach(days, id: \.self) { day in
                    let count = model.prayedCount(on: day)
                    VStack(spacing: 6) {
                        ZStack {
                            Circle().stroke(.white.opacity(0.12), lineWidth: 4)
                            Circle()
                                .trim(from: 0, to: CGFloat(count) / 5)
                                .stroke(count == 5 ? Palette.gold : Palette.emerald,
                                        style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            if count == 5 {
                                Image(systemName: "checkmark")
                                    .font(.caption2.weight(.heavy))
                                    .foregroundStyle(Palette.gold)
                            }
                        }
                        .frame(width: 30, height: 30)
                        Text(day.formatted(.dateTime.weekday(.narrow)))
                            .font(.caption2.weight(calendar.isDate(day, inSameDayAs: today) ? .heavy : .regular))
                            .foregroundStyle(calendar.isDate(day, inSameDayAs: today) ? .primary : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(day.formatted(.dateTime.weekday(.wide))): \(count) of 5 prayers")
                }
            }
            Text("Tick each prayer after you pray it. Days with all five count toward your streak.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .surface(cornerRadius: 26)
    }
}
