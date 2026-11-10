import SwiftUI

struct TodayView: View {
    @Environment(AppModel.self) private var model
    @State private var checkIn: PrayerSlot?
    /// The dial has turned into the Qibla compass.
    @State private var qiblaOpen = false
    @Namespace private var qiblaMorph

    /// One spring for both ways, so opening and closing feel the same.
    static let morph = Animation.spring(duration: 0.65, bounce: 0.18)

    var body: some View {
        NavigationStack {
            // Re-render every 30s so the dial, highlights and prompts move on by themselves.
            TimelineView(.periodic(from: .now, by: 30)) { context in
                ScrollView {
                    content(now: context.date)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 28)
                        .readableWidth()
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
                        .padding(.horizontal, 12)
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
            .toolbar(qiblaOpen ? .hidden : .visible, for: .tabBar)
        }
        .overlay {
            if qiblaOpen {
                QiblaTakeover(namespace: qiblaMorph) {
                    withAnimation(Self.morph) { qiblaOpen = false }
                }
                .transition(.opacity)
            }
        }
        .haptic(.impact(weight: .light), trigger: qiblaOpen)
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
            if let change = model.recentLocationChange {
                LocationUpdatedBanner(change: change)
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else if let location = model.location, model.shouldOfferTimeZoneUpdate(now: now) {
                TimeZoneChangedCard(location: location)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if let schedule {
                PrayerDial(schedule: schedule, now: now, next: next,
                           locationName: model.location?.name ?? "",
                           hijri: HijriDate.string(for: now, adjustmentDays: model.hijriAdjustment),
                           qiblaOpen: qiblaOpen, namespace: qiblaMorph,
                           qiblaBearing: model.location.map { PrayerCalculator.qiblaDirection(from: $0) },
                           onQibla: { withAnimation(Self.morph) { qiblaOpen = true } }) { time in
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
        .animation(.smooth(duration: 0.45), value: model.recentLocationChange)
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
    /// While the Qibla is open, the ring, next prayer and countdown have
    /// become the compass, and the rest folds into the centre.
    let qiblaOpen: Bool
    let namespace: Namespace.ID
    /// Degrees from north to the Kaaba, shown on the button.
    let qiblaBearing: Double?
    let onQibla: () -> Void
    let onSelect: (PrayerTime) -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Label(locationName, systemImage: "location.fill")
                    .fitText(0.5)
                Spacer(minLength: 8)
                Text(hijri).fitText(0.5)
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
                        .rotationEffect(.degrees(qiblaOpen ? 90 : 0))
                        .opacity(qiblaOpen ? 0 : 1)

                    // Hour ticks, longer every 6 hours.
                    ForEach(0..<24, id: \.self) { hour in
                        Capsule()
                            .fill(.white.opacity(hour % 6 == 0 ? 0.45 : 0.18))
                            .frame(width: hour % 6 == 0 ? 2 : 1, height: hour % 6 == 0 ? 9 : 5)
                            .offset(y: -(radius + 18))
                            .rotationEffect(.degrees(Double(hour) * 15 + 180))
                    }
                    .opacity(qiblaOpen ? 0 : 1)

                    // Track and daylight arc: they become the compass ring.
                    if !qiblaOpen {
                        ZStack {
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
                        }
                        .frame(width: radius * 2, height: radius * 2)
                        .matchedGeometryEffect(id: QiblaMorph.ring, in: namespace)
                    }

                    ForEach(schedule.times) { time in
                        if time.id == next?.id {
                            // The next prayer becomes the Kaaba.
                            if !qiblaOpen {
                                node(for: time)
                                    .matchedGeometryEffect(id: QiblaMorph.kaaba, in: namespace)
                                    .position(point(fraction(time.date), radius: radius, center: center))
                            }
                        } else {
                            // The others fold into the centre.
                            // The others fold into the centre.
                            node(for: time)
                                .scaleEffect(qiblaOpen ? 0.2 : 1)
                                .opacity(qiblaOpen ? 0 : 1)
                                .position(qiblaOpen ? center : point(fraction(time.date), radius: radius, center: center))
                        }
                    }

                    nowMarker
                        .scaleEffect(qiblaOpen ? 0.2 : 1)
                        .opacity(qiblaOpen ? 0 : 1)
                        .position(qiblaOpen ? center : point(fraction(now), radius: radius, center: center))

                    // The countdown, with the way into the Qibla set beneath it as one centred line.
                    VStack(spacing: 4) {
                        if !qiblaOpen {
                            centerLabel
                                .allowsHitTesting(false)
                                .matchedGeometryEffect(id: QiblaMorph.center, in: namespace)
                            QiblaLink(bearing: qiblaBearing, action: onQibla)
                                .transition(.opacity)
                        }
                    }
                    .frame(width: radius * 1.45)
                    .position(x: center.x, y: center.y + 8)
                }
            }
            .frame(height: 340)
        }
        .padding(18)
        .glassPanel(cornerRadius: 34, tint: Palette.glow.opacity(0.25))
        // A fixed circle can't reflow: above the largest standard text size it
        // stops growing (VoiceOver and the rows below still follow the setting).
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    @ViewBuilder
    private var centerLabel: some View {
        if let next {
            VStack(spacing: 0) {
                Text(next.name.arabicName)
                    .font(.calligraphy(size: 40))
                    .fitText()
                    .foregroundStyle(Palette.highlight)
                Text("Next · \(next.name.displayName(on: next.date))")
                    .font(.subheadline.weight(.semibold))
                    .fitText()
                    .foregroundStyle(.secondary)
                Text(next.date.shortTime)
                    .font(.display(40, weight: .heavy))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                Text("in \(Text(next.date, style: .timer))")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .fitText()
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
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Its time began at \(time.date.shortTime).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(time.name.arabicName)
                    .font(.calligraphy(size: 28))
                    .fixedSize()
                    .foregroundStyle(Palette.highlight)
            }
            // Side by side; stacked when large text won't fit them on one line.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { onTimeButton(fit: true); moreButton(fit: true) }
                VStack(spacing: 10) { onTimeButton(fit: false); moreButton(fit: false) }
            }
        }
        .padding(18)
        .surface(cornerRadius: 26)
        .haptic(.success, trigger: model.record(for: time.name, on: day))
    }

    /// `fit`: side by side, so each label must stay on one line (shrinking if
    /// need be) for `ViewThatFits` to judge whether the row fits.
    private func onTimeButton(fit: Bool) -> some View {
        Button {
            withAnimation(.bouncy) { model.setRecord(PrayerRecord(status: .onTime), for: time.name, on: day) }
        } label: {
            Label("On time", systemImage: "checkmark")
                .font(.subheadline.weight(.bold))
                .lineLimit(fit ? 1 : 2)
                .minimumScaleFactor(fit ? 0.85 : 1)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .tint(Palette.accent)
        .controlSize(.large)
        .accessibilityLabel("Prayed \(time.name.englishName) on time")
    }

    private func moreButton(fit: Bool) -> some View {
        Button(action: onMore) {
            Text("Late / missed")
                .font(.subheadline.weight(.semibold))
                .lineLimit(fit ? 1 : 2)
                .minimumScaleFactor(fit ? 0.85 : 1)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glass)
        .controlSize(.large)
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 36

    var body: some View {
        let record = model.record(for: time.name, on: day)
        let hasStarted = time.date <= now

        // One line normally; at accessibility text sizes the name goes on top
        // and the time and buttons below, so nothing is squeezed out.
        let row = Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) { icon; names }
                    HStack(spacing: 12) {
                        timeLabel
                        Spacer(minLength: 4)
                        notificationButton
                        checkInButton(record: record, hasStarted: hasStarted)
                    }
                }
            } else {
                HStack(spacing: 14) {
                    icon
                    names
                    Spacer(minLength: 4)
                    timeLabel
                    notificationButton
                    checkInButton(record: record, hasStarted: hasStarted)
                }
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

    private var icon: some View {
        Image(systemName: time.name.symbolName)
            .font(.body.weight(.semibold))
            .foregroundStyle(isNext ? Palette.highlight : Palette.accent)
            .frame(width: iconSize, height: iconSize)
            .background(.white.opacity(0.08), in: .circle)
    }

    private var names: some View {
        let record = model.record(for: time.name, on: day)
        return VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                Text(time.name.displayName(on: time.date))
                    .font(.body.weight(.semibold))
                    .fitText(0.5)
                if isNext {
                    Text("NEXT")
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(.black)
                        .badgeText()
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Palette.highlight, in: .capsule)
                }
            }
            Text(record.map { recordSummary($0) } ?? time.name.arabicName)
                .font(.caption)
                .fitText()
                .foregroundStyle(record?.status.color ?? .secondary)
        }
    }

    private var timeLabel: some View {
        Text(time.date.shortTime)
            .font(.body.monospacedDigit().weight(.semibold))
            .fitText(0.5)
            .layoutPriority(1)
    }

    @ViewBuilder
    private func checkInButton(record: PrayerRecord?, hasStarted: Bool) -> some View {
        if time.name.isObligatory {
            Button(action: onCheckIn) {
                Image(systemName: record?.status.symbolName ?? "circle")
                    .font(.title2)
                    .foregroundStyle(record?.status.color ?? .white.opacity(hasStarted ? 0.5 : 0.15))
                    .frame(minWidth: 34, minHeight: 34)
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
                .frame(minWidth: 30, minHeight: 34)
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
                    .fitText(0.5)
                    .foregroundStyle(streak > 0 ? Palette.highlight : .secondary)
                    .contentTransition(.numericText(value: Double(streak)))
                Spacer()
                Text("Last 7 days").sectionLabelStyle().fitText(0.5)
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
                            .fitText()
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

/// The Qibla, opened from the dial: full screen, with the dial's parts
/// carried into the compass. Closing plays it back.
private struct QiblaTakeover: View {
    let namespace: Namespace.ID
    let onClose: () -> Void
    @State private var closeShown = false

    var body: some View {
        ZStack {
            AmbientBackground()
                .ignoresSafeArea()
            VStack(spacing: 0) {
                ZStack {
                    Text("Qibla").font(.headline)
                    HStack {
                        Spacer()
                        Button(action: onClose) {
                            Image(systemName: "xmark")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(.white.opacity(0.08), in: .circle)
                                .overlay(Circle().strokeBorder(Palette.highlight.opacity(0.45), lineWidth: 1))
                        }
                        .buttonStyle(.pressable)
                        // Drops in from the top of the screen and fades in.
                        .offset(y: closeShown ? 0 : -70)
                        .opacity(closeShown ? 1 : 0)
                        .accessibilityLabel("Close the Qibla")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                QiblaScreen(namespace: namespace)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            withAnimation(.spring(duration: 0.55, bounce: 0.3).delay(0.25)) { closeShown = true }
        }
        // Swipe down to close, as with a sheet.
        .gesture(DragGesture(minimumDistance: 40).onEnded { drag in
            if drag.translation.height > 120, abs(drag.translation.width) < drag.translation.height { onClose() }
        })
    }
}

/// The way into the Qibla: the Kaaba in a round, gold-edged button, centred
/// under the countdown. A soft ring breathes out from it now and then, so it
/// reads as something to tap.
private struct QiblaLink: View {
    let bearing: Double?
    let action: () -> Void
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            ZStack {
                // The breathing ring.
                Circle()
                    .stroke(Palette.highlight.opacity(pulse ? 0 : 0.5), lineWidth: 1.5)
                    .frame(width: 44, height: 44)
                    .scaleEffect(pulse ? 1.45 : 1)
                // Gold-tinted glass, lit from the top like the dial's arc.
                Circle()
                    .fill(RadialGradient(colors: [Palette.highlight.opacity(0.32), Palette.highlight.opacity(0.08)],
                                         center: .top, startRadius: 2, endRadius: 40))
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.tint(Palette.highlight.opacity(0.18)), in: .circle)
                    .overlay(Circle().strokeBorder(
                        LinearGradient(colors: [Palette.highlight.opacity(0.9), Palette.highlight.opacity(0.25)],
                                       startPoint: .top, endPoint: .bottom), lineWidth: 1))
                KaabaMarker(highlighted: false, size: 18)
            }
            .frame(width: 64, height: 64)
            .contentShape(.circle)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Qibla")
        .accessibilityHint("Turns the dial into the Qibla compass")
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 2.2).repeatForever(autoreverses: false)) { pulse = true }
        }
    }
}
