import Charts
import SwiftUI

/// Salah statistics: this week at a glance, a calendar of consistency, and
/// which prayers you miss most and why.
struct SalahStatsSection: View {
    @Environment(AppModel.self) private var model
    @State private var month = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
    @State private var selectedDay: DayDestination?

    private var calendar: Calendar { .current }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            todayAndWeek
                .appearAnimation(0)
            header
                .appearAnimation(1)
            calendarGrid
                .appearAnimation(2)
            legend
                .appearAnimation(3)
            statsSection
        }
        .sheet(item: $selectedDay) { destination in
            DayDetailSheet(day: destination.day)
        }
        .haptic(.selection, trigger: month)
    }

    // MARK: Today and this week

    private struct DayBar: Identifiable {
        let day: Date
        let status: String
        let count: Int
        var id: String { "\(day.timeIntervalSince1970)-\(status)" }
    }

    private var todayAndWeek: some View {
        let today = calendar.startOfDay(for: .now)
        let week = (0..<7).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
        let bars: [DayBar] = week.flatMap { day -> [DayBar] in
            let records = PrayerName.obligatory.compactMap { model.record(for: $0, on: day) }
            return [
                DayBar(day: day, status: "On time", count: records.filter { $0.status == .onTime }.count),
                DayBar(day: day, status: "Late", count: records.filter { $0.status == .late }.count),
            ]
        }
        let weekStats = model.stats(for: week)
        let thirty = (0..<30).compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
        let monthStats = model.stats(for: thirty)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                StatTile(value: "\(model.prayedCount(on: today))/5", label: "Today", color: Palette.accent)
                StatTile(value: "\(model.streak())", label: "Day streak", color: Palette.highlight)
                StatTile(value: "\(weekStats.prayed)/\(7 * 5)", label: "This week", color: Palette.accent)
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Last 7 days").sectionLabelStyle()
                    Spacer()
                    Text("30 days: \(monthStats.prayed) of \(30 * 5) prayed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Chart(bars) { bar in
                    BarMark(x: .value("Day", bar.day, unit: .day), y: .value("Prayers", bar.count))
                        .foregroundStyle(by: .value("Status", bar.status))
                        .cornerRadius(4)
                }
                .chartForegroundStyleScale(["On time": Palette.accent, "Late": Palette.highlight])
                .chartYScale(domain: 0...5)
                .chartYAxis { AxisMarks(values: [0, 5]) }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisValueLabel(format: .dateTime.weekday(.narrow))
                    }
                }
                .chartLegend(position: .bottom, alignment: .leading)
                .frame(height: 150)
            }
            .padding(18)
            .surface(cornerRadius: 26)
        }
    }

    // MARK: Month header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(month.formatted(.dateTime.month(.wide).year()))
                    .font(.title2.weight(.bold))
                    .contentTransition(.numericText())
                Text(HijriDate.string(for: month.addingTimeInterval(14 * 86_400)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    Button { changeMonth(by: -1) } label: {
                        Image(systemName: "chevron.left").frame(width: 20, height: 20)
                    }
                    .accessibilityLabel("Previous month")
                    Button { changeMonth(by: 1) } label: {
                        Image(systemName: "chevron.right").frame(width: 20, height: 20)
                    }
                    .disabled(isCurrentMonth)
                    .accessibilityLabel("Next month")
                }
                .buttonStyle(.glass)
            }
        }
    }

    private var isCurrentMonth: Bool {
        calendar.isDate(month, equalTo: .now, toGranularity: .month)
    }

    private func changeMonth(by value: Int) {
        guard let newMonth = calendar.date(byAdding: .month, value: value, to: month) else { return }
        withAnimation(.smooth(duration: 0.4)) { month = newMonth }
    }

    // MARK: Calendar

    private var daysInMonth: [Date] {
        guard let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        return range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: month) }
    }

    /// Days up to today, for stats.
    private var loggableDays: [Date] {
        let today = calendar.startOfDay(for: .now)
        return daysInMonth.filter { $0 <= today }
    }

    private var calendarGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
        let leadingBlanks = (calendar.component(.weekday, from: month) - calendar.firstWeekday + 7) % 7
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let orderedSymbols = Array(symbols[(calendar.firstWeekday - 1)...] + symbols[..<(calendar.firstWeekday - 1)])

        return VStack(spacing: 10) {
            HStack {
                ForEach(Array(orderedSymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(0..<leadingBlanks, id: \.self) { _ in Color.clear.frame(height: 50) }
                ForEach(daysInMonth, id: \.self) { day in
                    DayCell(day: day)
                        .onTapGesture {
                            guard day <= .now else { return }
                            selectedDay = DayDestination(day: day)
                        }
                }
            }
            .id(month)
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
        .padding(14)
        .glassPanel(cornerRadius: 28, tint: Palette.glow.opacity(0.2))
        .gesture(
            DragGesture(minimumDistance: 30).onEnded { value in
                if value.translation.width < -60, !isCurrentMonth { changeMonth(by: 1) }
                if value.translation.width > 60 { changeMonth(by: -1) }
            }
        )
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem(Palette.highlight, "All 5")
            legendItem(Palette.accent, "Prayed")
            legendItem(PrayerStatus.missed.color, "Missed")
            Spacer()
            Text("Tap a day to edit")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    private func legendItem(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
        }
    }

    // MARK: Stats

    @ViewBuilder
    private var statsSection: some View {
        let stats = model.stats(for: loggableDays)

        HStack(spacing: 10) {
            StatTile(value: stats.logged == 0 ? "–" : "\(Int((stats.onTimeRate * 100).rounded()))%",
                     label: "On time", color: Palette.accent)
            StatTile(value: "\(stats.prayed)", label: "Prayed", color: Palette.highlight)
            StatTile(value: "\(stats.missed)", label: "Missed", color: PrayerStatus.missed.color)
        }
        .appearAnimation(3)

        if stats.logged == 0 {
            VStack(spacing: 10) {
                Rosette(color: Palette.highlight.opacity(0.4))
                    .frame(width: 70, height: 70)
                Text("Nothing logged this month yet")
                    .font(.headline)
                Text("Check in after each prayer on the Today tab and this month will fill in here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(24)
            .surface(cornerRadius: 26)
            .appearAnimation(4)
        } else {
            byPrayerCard
                .appearAnimation(4)
            if let hardest = stats.hardestPrayer {
                insightCard(hardest: hardest, stats: stats)
                    .appearAnimation(5)
            }
            if !stats.reasons.isEmpty {
                reasonsCard(stats)
                    .appearAnimation(6)
            }
        }
    }

    /// For each prayer: how often it was on time this month.
    private var byPrayerCard: some View {
        let days = loggableDays
        return VStack(alignment: .leading, spacing: 12) {
            Text("By prayer").sectionLabelStyle()
            ForEach(PrayerName.obligatory) { prayer in
                let records = days.compactMap { model.record(for: prayer, on: $0) }
                let onTime = records.filter { $0.status == .onTime }.count
                let late = records.filter { $0.status == .late }.count
                let missed = records.filter { $0.status == .missed }.count
                let total = max(days.count, 1)
                HStack(spacing: 12) {
                    Text(prayer.englishName)
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 64, alignment: .leading)
                    GeometryReader { geo in
                        HStack(spacing: 2) {
                            bar(PrayerStatus.onTime.color, width: geo.size.width * CGFloat(onTime) / CGFloat(total))
                            bar(PrayerStatus.late.color, width: geo.size.width * CGFloat(late) / CGFloat(total))
                            bar(PrayerStatus.missed.color, width: geo.size.width * CGFloat(missed) / CGFloat(total))
                            Spacer(minLength: 0)
                        }
                        .background(Capsule().fill(.white.opacity(0.06)))
                    }
                    .frame(height: 10)
                    Text("\(onTime + late)/\(days.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
            }
        }
        .padding(18)
        .surface(cornerRadius: 26)
    }

    private func bar(_ color: Color, width: CGFloat) -> some View {
        Capsule().fill(color).frame(width: max(0, width), height: 10)
    }

    private func insightCard(hardest: PrayerName, stats: PrayerStats) -> some View {
        HStack(spacing: 14) {
            Text(hardest.arabicName)
                .font(.calligraphy(size: 34))
                .foregroundStyle(Palette.highlight)
                .frame(width: 80)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(hardest.englishName) is your hardest prayer")
                    .font(.headline)
                Text("It was late or missed \(stats.missedOrLateByPrayer[hardest] ?? 0) times this month. \(tip(for: hardest))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .glassPanel(cornerRadius: 26, tint: Palette.glow.opacity(0.25))
    }

    private func tip(for prayer: PrayerName) -> String {
        switch prayer {
        case .fajr: "Try an alarm a few minutes before Fajr and sleeping a little earlier."
        case .dhuhr: "Try blocking a few minutes in your day at Dhuhr time."
        case .asr: "Asr's window is shorter than it feels. Pray soon after the adhan."
        case .maghrib: "Maghrib time is short, so pray as soon as the sun sets."
        case .isha: "Pray Isha before winding down for the night."
        case .sunrise: ""
        }
    }

    private func reasonsCard(_ stats: PrayerStats) -> some View {
        let maxCount = stats.sortedReasons.first?.count ?? 1
        return VStack(alignment: .leading, spacing: 12) {
            Text("Why prayers were late or missed").sectionLabelStyle()
            ForEach(stats.sortedReasons, id: \.reason) { item in
                HStack(spacing: 12) {
                    Image(systemName: item.reason.symbolName)
                        .foregroundStyle(Palette.highlight)
                        .frame(width: 24)
                    Text(item.reason.title)
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 92, alignment: .leading)
                    GeometryReader { geo in
                        Capsule()
                            .fill(LinearGradient(colors: [Palette.highlight, Palette.accent], startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * CGFloat(item.count) / CGFloat(maxCount), height: 10)
                            .frame(maxHeight: .infinity)
                    }
                    .frame(height: 16)
                    Text("\(item.count)×")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 30, alignment: .trailing)
                }
            }
        }
        .padding(18)
        .surface(cornerRadius: 26)
    }
}

struct DayDestination: Identifiable, Hashable {
    let day: Date
    var id: Date { day }
}

// MARK: - Day cell

private struct DayCell: View {
    @Environment(AppModel.self) private var model
    let day: Date

    var body: some View {
        let calendar = Calendar.current
        let isToday = calendar.isDateInToday(day)
        let isFuture = day > .now
        let prayed = model.prayedCount(on: day)
        let missed = PrayerName.obligatory.filter { model.record(for: $0, on: day)?.status == .missed }.count
        let complete = model.isComplete(day)

        VStack(spacing: 3) {
            ZStack {
                if complete {
                    EightPointStar()
                        .fill(Palette.highlight)
                        .shadow(color: Palette.highlight.opacity(0.6), radius: 6)
                } else {
                    Circle()
                        .stroke(.white.opacity(isFuture ? 0.04 : 0.1), lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: CGFloat(prayed) / 5)
                        .stroke(Palette.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                Text("\(calendar.component(.day, from: day))")
                    .font(.caption.weight(isToday ? .heavy : .semibold).monospacedDigit())
                    .foregroundStyle(complete ? .black : (isFuture ? .secondary : .primary))
            }
            .frame(width: 34, height: 34)

            Circle()
                .fill(missed > 0 ? PrayerStatus.missed.color : .clear)
                .frame(width: 5, height: 5)
        }
        .frame(maxWidth: .infinity, minHeight: 50)
        .background {
            if isToday {
                RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.accent.opacity(0.7), lineWidth: 1.5)
            }
        }
        .contentShape(.rect)
        .opacity(isFuture ? 0.45 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(day.formatted(date: .complete, time: .omitted)): \(prayed) of 5 prayed\(missed > 0 ? ", \(missed) missed" : "")")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Day detail

/// One day's five prayers, each editable, for catching up or fixing a log.
private struct DayDetailSheet: View {
    @Environment(AppModel.self) private var model
    let day: Date
    @State private var checkIn: PrayerSlot?

    var body: some View {
        NavigationStack {
            List {
                ForEach(PrayerName.obligatory) { prayer in
                    let record = model.record(for: prayer, on: day)
                    Button {
                        checkIn = PrayerSlot(prayer: prayer, day: day)
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: record?.status.symbolName ?? "circle")
                                .font(.title2)
                                .foregroundStyle(record?.status.color ?? .secondary)
                                .frame(width: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(prayer.displayName(on: day)).font(.headline)
                                Text(record.map { r in r.reason.map { "\(r.status.title) · \($0.title)" } ?? r.status.title } ?? "Not logged")
                                    .font(.caption)
                                    .foregroundStyle(record?.status.color ?? .secondary)
                            }
                            Spacer()
                            Text(prayer.arabicName)
                                .font(.calligraphy(size: 22))
                                .foregroundStyle(Palette.highlight)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.pressable)
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $checkIn) { slot in
                CheckInSheet(slot: slot)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

struct StatTile: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.display(28, weight: .heavy))
                .foregroundStyle(color)
                .contentTransition(.numericText())
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .surface(cornerRadius: 22)
    }
}
