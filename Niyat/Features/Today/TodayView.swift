import SwiftUI

struct TodayView: View {
    @Environment(AppModel.self) private var model
    @State private var checkIn: PrayerSlot?

    var body: some View {
        NavigationStack {
            // Re-render every 30s so the dial, highlights and prompts move on by themselves.
            TimelineView(.periodic(from: .now, by: 30)) { context in
                ScrollView {
                    content(now: context.date)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 28)
                }
                .scrollEdgeEffectStyle(.soft, for: .top)
                .background { SkyBackdrop(prayer: skyPrayer(at: context.date)) }
            }
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
            .sheet(item: $checkIn) { slot in
                CheckInSheet(slot: slot)
            }
        }
    }

    /// The sky behind the screen follows the real time of day.
    private func skyPrayer(at now: Date) -> PrayerName {
        model.currentPrayer(at: now)?.name ?? .isha
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let schedule = model.schedule(for: now)
        let next = model.nextPrayer(after: now)

        VStack(alignment: .leading, spacing: 18) {
            if let schedule {
                PrayerDial(schedule: schedule, now: now, next: next,
                           locationName: model.location?.name ?? "",
                           hijri: HijriDate.string(for: now, adjustmentDays: model.hijriAdjustment)) { time in
                    checkIn = PrayerSlot(prayer: time.name, day: schedule.day)
                }
                .appearAnimation(0)

                if let pending = model.pendingCheckIn(at: now) {
                    CheckInPrompt(time: pending, day: schedule.day) {
                        checkIn = PrayerSlot(prayer: pending.name, day: schedule.day)
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .appearAnimation(1)
                }

                VStack(spacing: 8) {
                    ForEach(Array(schedule.times.enumerated()), id: \.element.id) { index, time in
                        PrayerTimeRow(time: time, day: schedule.day, now: now, isNext: time.id == next?.id) {
                            checkIn = PrayerSlot(prayer: time.name, day: schedule.day)
                        }
                        .appearAnimation(2 + index)
                    }
                }
            }

            StreakStrip(now: now)
                .appearAnimation(9)

            HStack {
                Spacer()
                Text("\(model.prayerSettings.method.title) · Asr: \(model.prayerSettings.madhab.title)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
        }
        .animation(.smooth(duration: 0.45), value: model.pendingCheckIn(at: now)?.id)
    }
}

/// Ambient background with the current sky washing down from the top.
private struct SkyBackdrop: View {
    let prayer: PrayerName

    var body: some View {
        ZStack {
            AmbientBackground()
            PrayerSky(prayer: prayer)
                .opacity(0.32)
                .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .center))
                .ignoresSafeArea()
                .animation(.smooth(duration: 1.2), value: prayer)
        }
    }
}

// MARK: - The prayer dial

/// A 24-hour clock face: midnight at the bottom, noon at the top. The golden arc
/// is daylight, each prayer sits at its time, and the sun or moon marks now.
private struct PrayerDial: View {
    @Environment(AppModel.self) private var model
    let schedule: DaySchedule
    let now: Date
    let next: PrayerTime?
    let locationName: String
    let hijri: String
    let onSelect: (PrayerTime) -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Label(locationName, systemImage: "location.fill")
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(hijri).lineLimit(1)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                let radius = side / 2 - 26
                let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                ZStack {
                    Rosette(color: Palette.highlight.opacity(0.09), lineWidth: 1)
                        .frame(width: radius * 1.55, height: radius * 1.55)

                    // Hour ticks, longer every 6 hours.
                    ForEach(0..<24, id: \.self) { hour in
                        Capsule()
                            .fill(.white.opacity(hour % 6 == 0 ? 0.45 : 0.18))
                            .frame(width: hour % 6 == 0 ? 2 : 1, height: hour % 6 == 0 ? 9 : 5)
                            .offset(y: -(radius + 18))
                            .rotationEffect(.degrees(Double(hour) * 15 + 180))
                    }

                    // Track and daylight arc.
                    Circle()
                        .stroke(.white.opacity(0.07), lineWidth: 16)
                        .frame(width: radius * 2, height: radius * 2)
                    if let sunrise = schedule.time(for: .sunrise), let maghrib = schedule.time(for: .maghrib) {
                        arc(from: fraction(sunrise.date), to: fraction(maghrib.date))
                            .stroke(LinearGradient(colors: [Palette.highlight.opacity(0.5), Palette.highlight.opacity(0.2)],
                                                   startPoint: .top, endPoint: .bottom),
                                    style: StrokeStyle(lineWidth: 16, lineCap: .round))
                            .frame(width: radius * 2, height: radius * 2)
                    }
                    // Time elapsed since the current prayer began.
                    if let current = model.currentPrayer(at: now), current.date >= schedule.day {
                        arc(from: fraction(current.date), to: fraction(now))
                            .stroke(Palette.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .frame(width: radius * 2, height: radius * 2)
                            .shadow(color: Palette.accent, radius: 6)
                    }

                    ForEach(schedule.times) { time in
                        node(for: time)
                            .position(point(fraction(time.date), radius: radius, center: center))
                    }

                    nowMarker
                        .position(point(fraction(now), radius: radius, center: center))

                    centerLabel
                        .frame(width: radius * 1.25)
                        .position(center)
                }
            }
            .frame(height: 340)
        }
        .padding(18)
        .glassPanel(cornerRadius: 34, tint: Palette.glow.opacity(0.25))
    }

    @ViewBuilder
    private var centerLabel: some View {
        if let next {
            VStack(spacing: 0) {
                Text(next.name.arabicName)
                    .font(.calligraphy(size: 40))
                    .foregroundStyle(Palette.highlight)
                Text("Next · \(next.name.displayName(on: next.date))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(next.date.shortTime)
                    .font(.display(40, weight: .heavy))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                Text("in \(Text(next.date, style: .timer))")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(Palette.accent)
            }
            .multilineTextAlignment(.center)
            .id(next.id)
            .transition(.blurReplace)
        }
    }

    private var nowMarker: some View {
        let isDay: Bool = {
            guard let sunrise = schedule.time(for: .sunrise)?.date, let maghrib = schedule.time(for: .maghrib)?.date else { return true }
            return now >= sunrise && now < maghrib
        }()
        return Image(systemName: isDay ? "sun.max.fill" : "moon.fill")
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(isDay ? Palette.highlight : Color.white)
            .frame(width: 30, height: 30)
            .background(Circle().fill(Palette.base))
            .shadow(color: isDay ? Palette.highlight : .white, radius: 10)
            .symbolEffect(.breathe, options: .repeating)
            .accessibilityLabel("Now")
    }

    @ViewBuilder
    private func node(for time: PrayerTime) -> some View {
        let record = model.record(for: time.name, on: schedule.day)
        let isNext = time.id == next?.id
        let hasStarted = time.date <= now
        let size: CGFloat = time.name.isObligatory ? 40 : 26

        Button {
            onSelect(time)
        } label: {
            ZStack {
                Circle()
                    .fill(record?.status.color ?? Palette.base)
                Circle()
                    .strokeBorder(isNext ? Palette.highlight : .white.opacity(hasStarted ? 0.6 : 0.25),
                                  lineWidth: isNext ? 2.5 : 1.5)
                Image(systemName: record.map { $0.status.symbolName } ?? time.name.symbolName)
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(record == nil ? (isNext ? Palette.highlight : .white) : .black)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: size, height: size)
            .shadow(color: isNext ? Palette.highlight.opacity(0.8) : .clear, radius: 10)
            .scaleEffect(isNext ? 1.1 : 1)
        }
        .buttonStyle(.pressable)
        .disabled(!time.name.isObligatory || !hasStarted)
        .accessibilityLabel("\(time.name.englishName) at \(time.date.shortTime)")
    }

    private func arc(from start: CGFloat, to end: CGFloat) -> some Shape {
        Circle()
            .trim(from: min(start, end), to: max(start, end))
            .rotation(.degrees(90))
    }

    /// 0 at midnight, 0.5 at noon.
    private func fraction(_ date: Date) -> CGFloat {
        CGFloat(min(max(date.timeIntervalSince(schedule.day) / 86_400, 0), 1))
    }

    /// Position on the ring: midnight at the bottom, going clockwise so noon is at the top.
    private func point(_ fraction: CGFloat, radius: CGFloat, center: CGPoint) -> CGPoint {
        let angle = Double(fraction) * 2 * .pi + .pi / 2
        return CGPoint(x: center.x + radius * CGFloat(cos(angle)), y: center.y + radius * CGFloat(sin(angle)))
    }
}

// MARK: - Check-in prompt

/// Shown once a prayer's time has come: one tap to log it.
private struct CheckInPrompt: View {
    @Environment(AppModel.self) private var model
    let time: PrayerTime
    let day: Date
    let onMore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Did you pray \(time.name.displayName(on: time.date))?")
                        .font(.headline)
                    Text("Its time began at \(time.date.shortTime).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(time.name.arabicName)
                    .font(.calligraphy(size: 28))
                    .foregroundStyle(Palette.highlight)
            }
            HStack(spacing: 10) {
                Button {
                    withAnimation(.bouncy) { model.setRecord(PrayerRecord(status: .onTime), for: time.name, on: day) }
                } label: {
                    Label("On time", systemImage: "checkmark")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(Palette.accent)
                .controlSize(.large)
                .accessibilityLabel("Prayed \(time.name.englishName) on time")

                Button(action: onMore) {
                    Text("Late / missed")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            }
        }
        .padding(18)
        .surface(cornerRadius: 26)
        .haptic(.success, trigger: model.record(for: time.name, on: day))
    }
}

// MARK: - Rows

private struct PrayerTimeRow: View {
    @Environment(AppModel.self) private var model
    let time: PrayerTime
    let day: Date
    let now: Date
    let isNext: Bool
    let onCheckIn: () -> Void

    var body: some View {
        let record = model.record(for: time.name, on: day)
        let hasStarted = time.date <= now

        let row = HStack(spacing: 14) {
            Image(systemName: time.name.symbolName)
                .font(.body.weight(.semibold))
                .foregroundStyle(isNext ? Palette.highlight : Palette.accent)
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
                            .background(Palette.highlight, in: .capsule)
                    }
                }
                Text(record.map { recordSummary($0) } ?? time.name.arabicName)
                    .font(.caption)
                    .foregroundStyle(record?.status.color ?? .secondary)
            }

            Spacer(minLength: 4)

            Text(time.date.shortTime)
                .font(.body.monospacedDigit().weight(.semibold))
                .lineLimit(1)
                .fixedSize()

            notificationButton

            if time.name.isObligatory {
                Button(action: onCheckIn) {
                    Image(systemName: record?.status.symbolName ?? "circle")
                        .font(.title2)
                        .foregroundStyle(record?.status.color ?? .white.opacity(hasStarted ? 0.5 : 0.15))
                        .frame(width: 34, height: 34)
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.bounce, value: record?.status)
                }
                .buttonStyle(.pressable)
                .disabled(!hasStarted)
                .accessibilityLabel("Check in \(time.name.englishName)")
            } else {
                Color.clear.frame(width: 34)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)

        if isNext {
            row.glassPanel(cornerRadius: 22, tint: Palette.accent.opacity(0.18))
        } else {
            row.surface()
        }
    }

    private func recordSummary(_ record: PrayerRecord) -> String {
        if let reason = record.reason { return "\(record.status.title) · \(reason.title)" }
        return record.status.title
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
                .foregroundStyle(enabled ? Color.white.opacity(0.85) : Color.secondary)
                .frame(width: 30, height: 34)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.pressable)
        .haptic(.selection, trigger: enabled)
        .accessibilityLabel(enabled ? "Turn off \(time.name.englishName) alert" : "Turn on \(time.name.englishName) alert")
    }
}

// MARK: - Streak

private struct StreakStrip: View {
    @Environment(AppModel.self) private var model
    let now: Date

    var body: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let days = (0..<7).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
        let streak = model.streak(asOf: now)

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(streak == 1 ? "1 day streak" : "\(streak) day streak", systemImage: "flame.fill")
                    .font(.headline)
                    .foregroundStyle(streak > 0 ? Palette.highlight : .secondary)
                    .contentTransition(.numericText(value: Double(streak)))
                Spacer()
                Text("Last 7 days").sectionLabelStyle()
            }
            HStack {
                ForEach(days, id: \.self) { day in
                    let count = model.prayedCount(on: day)
                    let isToday = calendar.isDate(day, inSameDayAs: today)
                    VStack(spacing: 6) {
                        ZStack {
                            EightPointStar()
                                .fill(model.isComplete(day) ? Palette.highlight : Color.white.opacity(0.06))
                            EightPointStar()
                                .trim(from: 0, to: CGFloat(count) / 5)
                                .stroke(Palette.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
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
        .surface(cornerRadius: 26)
    }
}
