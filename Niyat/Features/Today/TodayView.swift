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
                        .padding(.bottom, 28)
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

        VStack(alignment: .leading, spacing: 18) {
            if let next {
                NextPrayerHero(next: next, schedule: schedule, now: now,
                               locationName: model.location?.name ?? "",
                               hijri: HijriDate.string(for: now, adjustmentDays: model.hijriAdjustment))
                    .appearAnimation(0)
            }

            if let schedule {
                SectionTitle("Check your prayers", arabic: "صلاتي")
                    .appearAnimation(1)
                PrayerCheckRow(schedule: schedule, now: now)
                    .appearAnimation(2)

                SectionTitle("Today's times", arabic: "المواقيت")
                    .appearAnimation(3)
                VStack(spacing: 8) {
                    ForEach(Array(schedule.times.enumerated()), id: \.element.id) { index, time in
                        PrayerTimeRow(time: time,
                                      isCurrent: time.id == current?.id && time.name.isObligatory,
                                      isNext: time.id == next?.id)
                            .appearAnimation(4 + index)
                    }
                }
            }

            StreakCard(now: now)
                .appearAnimation(10)

            HStack {
                Spacer()
                Text("\(model.prayerSettings.method.title) · Asr: \(model.prayerSettings.madhab.title)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
        }
        .animation(.smooth(duration: 0.5), value: next?.id)
    }
}

/// Section heading with a small calligraphic Arabic label.
struct SectionTitle: View {
    let title: String
    let arabic: String?

    init(_ title: String, arabic: String? = nil) {
        self.title = title
        self.arabic = arabic
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.weight(.bold))
            Spacer()
            if let arabic {
                Text(arabic)
                    .font(.calligraphy(size: 20))
                    .foregroundStyle(Palette.highlight.opacity(0.85))
            }
        }
        .padding(.top, 6)
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
        ZStack {
            PrayerSky(prayer: next.name)
            IslamicPattern(tile: 60, lineWidth: 0.7, color: .white.opacity(0.07))

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Label(locationName, systemImage: "location.fill")
                        .lineLimit(1)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .glassEffect(.clear, in: .capsule)
                    Spacer(minLength: 4)
                    Text(hijri)
                        .lineLimit(1)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .glassEffect(.clear, in: .capsule)
                }
                .font(.caption.weight(.semibold))

                Spacer(minLength: 0)

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Next · \(next.name.displayName(on: next.date))")
                            .font(.headline)
                            .opacity(0.9)
                        Text(next.date.shortTime)
                            .font(.display(58, weight: .heavy))
                            .monospacedDigit()
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                            .contentTransition(.numericText())
                    }
                    Spacer()
                    Text(next.name.arabicName)
                        .font(.calligraphy(size: 46))
                        .shadow(color: .black.opacity(0.35), radius: 8)
                }

                HStack(spacing: 8) {
                    Image(systemName: "timer")
                    Text("in \(Text(next.date, style: .timer))")
                        .monospacedDigit()
                }
                .font(.subheadline.weight(.bold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassEffect(.regular.tint(.black.opacity(0.15)), in: .capsule)

                if let schedule {
                    DayTimeline(schedule: schedule, now: now)
                }
            }
            .foregroundStyle(.white)
            .padding(20)
        }
        .frame(height: 300)
        .clipShape(.rect(cornerRadius: 32))
        .overlay {
            RoundedRectangle(cornerRadius: 32).strokeBorder(.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: next.name.skyColors[1].opacity(0.45), radius: 24, y: 10)
        .id(next.id)
        .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 1.02)), removal: .opacity))
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
                    .fill(.white.opacity(0.22))
                    .frame(height: 4)
                Capsule()
                    .fill(.white)
                    .frame(width: max(0, width * fraction(now)), height: 4)
                ForEach(schedule.times) { time in
                    Circle()
                        .fill(time.date <= now ? Color.white : Color.white.opacity(0.45))
                        .frame(width: 7, height: 7)
                        .offset(x: width * fraction(time.date) - 3.5)
                }
                Circle()
                    .fill(.white)
                    .frame(width: 14, height: 14)
                    .shadow(color: .white, radius: 8)
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

// MARK: - Check your prayers

private struct PrayerCheckRow: View {
    @Environment(AppModel.self) private var model
    let schedule: DaySchedule
    let now: Date

    var body: some View {
        HStack(spacing: 8) {
            ForEach(PrayerName.obligatory) { prayer in
                if let time = schedule.time(for: prayer) {
                    PrayerCheckCard(time: time, day: schedule.day, hasStarted: time.date <= now,
                                    prayed: model.isPrayed(prayer, on: schedule.day)) {
                        withAnimation(.bouncy) { model.togglePrayed(prayer, on: schedule.day) }
                    }
                }
            }
        }
    }
}

private struct PrayerCheckCard: View {
    let time: PrayerTime
    let day: Date
    let hasStarted: Bool
    let prayed: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            VStack(spacing: 8) {
                ZStack(alignment: .bottom) {
                    PrayerSky(prayer: time.name)
                    VStack(spacing: 2) {
                        Spacer()
                        if prayed {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.black, .white)
                                .transition(.scale.combined(with: .opacity))
                        }
                        Text(time.name.displayName(on: time.date))
                            .font(.caption.weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(time.date.shortTime)
                            .font(.caption2.weight(.medium).monospacedDigit())
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .opacity(0.85)
                    }
                    .foregroundStyle(.white)
                    .padding(.bottom, 10)
                    .padding(.horizontal, 2)
                }
                .frame(height: 124)
                .clipShape(.rect(cornerRadius: 18))
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(prayed ? Palette.accent : .white.opacity(0.12), lineWidth: prayed ? 2 : 1)
                }
                .saturation(hasStarted ? 1 : 0.35)
                .opacity(hasStarted ? 1 : 0.6)

                Capsule()
                    .fill(prayed ? Palette.accent : Color.white.opacity(0.12))
                    .frame(height: 4)
                    .shadow(color: prayed ? Palette.accent : .clear, radius: 6)
            }
        }
        .buttonStyle(.pressable)
        .disabled(!hasStarted)
        .haptic(.success, trigger: prayed) { _, new in new }
        .accessibilityLabel(prayed ? "Mark \(time.name.englishName) as not prayed" : "Mark \(time.name.englishName) as prayed")
    }
}

// MARK: - Times list

private struct PrayerTimeRow: View {
    @Environment(AppModel.self) private var model
    let time: PrayerTime
    let isCurrent: Bool
    let isNext: Bool

    var body: some View {
        let row = HStack(spacing: 14) {
            Image(systemName: time.name.symbolName)
                .font(.body.weight(.semibold))
                .foregroundStyle(isNext || isCurrent ? Palette.highlight : Palette.accent)
                .frame(width: 36, height: 36)
                .background(.white.opacity(0.08), in: .circle)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(time.name.displayName(on: time.date))
                        .font(.body.weight(.semibold))
                    if isNext {
                        badge("NEXT", color: Palette.highlight)
                    } else if isCurrent {
                        badge("NOW", color: Palette.accent)
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
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)

        if isNext {
            row.glassPanel(cornerRadius: 22, tint: Palette.accent.opacity(0.2))
        } else {
            row.surface()
                .opacity(time.date < .now && !isCurrent ? 0.7 : 1)
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.heavy))
            .foregroundStyle(.black)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color, in: .capsule)
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
                .frame(width: 34, height: 34)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: enabled)
        }
        .buttonStyle(.pressable)
        .haptic(.selection, trigger: enabled)
        .accessibilityLabel(enabled ? "Turn off \(time.name.englishName) alert" : "Turn on \(time.name.englishName) alert")
    }
}

// MARK: - Streak

private struct StreakCard: View {
    @Environment(AppModel.self) private var model
    let now: Date

    var body: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let days = (0..<7).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
        let streak = model.streak(asOf: now)
        let todayCount = model.prayedCount(on: today)

        VStack(spacing: 18) {
            HStack(spacing: 20) {
                ZStack {
                    Rosette(color: Palette.highlight.opacity(0.25), lineWidth: 1)
                        .frame(width: 124, height: 124)
                    Circle()
                        .stroke(.white.opacity(0.08), lineWidth: 8)
                        .frame(width: 100, height: 100)
                    Circle()
                        .trim(from: 0, to: CGFloat(todayCount) / 5)
                        .stroke(AngularGradient(colors: [Palette.accent, Palette.highlight, Palette.accent], center: .center),
                                style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 100, height: 100)
                        .shadow(color: Palette.accent.opacity(0.7), radius: 8)
                        .animation(.smooth(duration: 0.8), value: todayCount)
                    VStack(spacing: 0) {
                        Text("\(streak)")
                            .font(.display(36, weight: .heavy))
                            .contentTransition(.numericText(value: Double(streak)))
                        Text(streak == 1 ? "day" : "days")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Streak").sectionLabelStyle()
                    Text("\(todayCount) of 5 today")
                        .font(.title3.weight(.bold))
                        .contentTransition(.numericText(value: Double(todayCount)))
                    Text("Tick each prayer after you pray it. Days with all five build your streak.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                ForEach(days, id: \.self) { day in
                    let count = model.prayedCount(on: day)
                    let isToday = calendar.isDate(day, inSameDayAs: today)
                    VStack(spacing: 6) {
                        ZStack {
                            EightPointStar()
                                .fill(count == 5 ? Palette.highlight : Color.white.opacity(0.08))
                            EightPointStar()
                                .stroke(count > 0 ? Palette.accent : Color.white.opacity(0.2), lineWidth: 1.5)
                            if count > 0, count < 5 {
                                Text("\(count)")
                                    .font(.caption2.weight(.heavy))
                                    .foregroundStyle(Palette.accent)
                            }
                        }
                        .frame(width: 30, height: 30)
                        Text(day.formatted(.dateTime.weekday(.narrow)))
                            .font(.caption2.weight(isToday ? .heavy : .regular))
                            .foregroundStyle(isToday ? .primary : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(day.formatted(.dateTime.weekday(.wide))): \(count) of 5 prayers")
                }
            }
        }
        .padding(18)
        .glassPanel(cornerRadius: 28, tint: Palette.glow.opacity(0.3))
    }
}
