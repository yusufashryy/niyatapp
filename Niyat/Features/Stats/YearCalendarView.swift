import SwiftUI

/// A whole year at a glance, one square per day, for seeing consistency over
/// the years. Every year since you started using Niyat is kept, and new years
/// appear as they come.
struct YearCalendarView: View {
    enum Kind: String, CaseIterable, Identifiable {
        case salah = "Salah", quran = "Qur'an"
        var id: String { rawValue }
    }

    @Environment(AppModel.self) private var model
    @State private var year = Calendar.current.component(.year, from: .now)
    @State private var kind = Kind.salah
    @State private var selectedDay: DayDestination?

    private var calendar: Calendar { .current }
    private var currentYear: Int { calendar.component(.year, from: .now) }

    var body: some View {
        let data = YearData(model: model, year: year, kind: kind)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                Picker("Show", selection: $kind.animation(.smooth)) {
                    ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                summary(data)
                    .appearAnimation(0)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12, alignment: .top), GridItem(.flexible(), spacing: 12, alignment: .top)], spacing: 12) {
                    ForEach(1...12, id: \.self) { month in
                        MiniMonth(year: year, month: month, data: data) { day in
                            if kind == .salah { selectedDay = DayDestination(day: day) }
                        }
                    }
                }
                .appearAnimation(1)

                legend
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .niyatBackground()
        .navigationTitle("Year")
        .navigationBarTitleDisplayMode(.inline)
        .haptic(.selection, trigger: year)
        .sheet(item: $selectedDay) { destination in
            DayDetailSheet(day: destination.day)
        }
    }

    /// The first year with anything logged, up to this year.
    private var years: ClosedRange<Int> {
        let keys = model.records.keys.map { String($0.prefix(4)) } + QuranProgress.allDays().keys.map { String($0.prefix(4)) }
        let first = keys.compactMap(Int.init).min() ?? currentYear
        return min(first, currentYear)...currentYear
    }

    private var header: some View {
        HStack {
            Text(String(year))
                .font(.display(34, weight: .heavy).monospacedDigit())
                .contentTransition(.numericText(value: Double(year)))
            Spacer()
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    Button { withAnimation(.smooth) { year -= 1 } } label: {
                        Image(systemName: "chevron.left").frame(width: 20, height: 20)
                    }
                    .disabled(year <= years.lowerBound)
                    .accessibilityLabel("Previous year")
                    Button { withAnimation(.smooth) { year += 1 } } label: {
                        Image(systemName: "chevron.right").frame(width: 20, height: 20)
                    }
                    .disabled(year >= years.upperBound)
                    .accessibilityLabel("Next year")
                }
                .buttonStyle(.glass)
            }
        }
        .foregroundStyle(.white)
    }

    private func summary(_ data: YearData) -> some View {
        HStack(spacing: 10) {
            switch kind {
            case .salah:
                StatTile(value: "\(data.completeDays)", label: "Full days", color: Palette.highlight)
                StatTile(value: "\(data.total)", label: "Prayers", color: Palette.accent)
                StatTile(value: data.consistency, label: "Of days logged", color: Palette.accent)
            case .quran:
                StatTile(value: "\(data.completeDays)", label: "Goal days", color: Palette.highlight)
                StatTile(value: "\(data.total)", label: "Ayat read", color: Palette.accent)
                StatTile(value: "\(data.bestStreak)", label: "Best streak", color: Palette.highlight)
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 6) {
            Text("Less").font(.caption2).foregroundStyle(.secondary)
            ForEach([0.0, 0.25, 0.5, 0.75], id: \.self) { level in
                RoundedRectangle(cornerRadius: 2)
                    .fill(level == 0 ? Color.white.opacity(0.08) : Palette.accent.opacity(0.25 + level * 0.75))
                    .frame(width: 12, height: 12)
            }
            RoundedRectangle(cornerRadius: 2).fill(Palette.highlight).frame(width: 12, height: 12)
            Text(kind == .salah ? "All 5" : "Goal met").font(.caption2).foregroundStyle(.secondary)
            Spacer()
        }
    }
}

/// Per-day levels for one year, computed once per render.
private struct YearData {
    /// Day key → 0...1 progress, and whether the day is complete.
    let levels: [String: (fraction: Double, complete: Bool)]
    let completeDays: Int
    let total: Int
    let loggedDays: Int
    let bestStreak: Int

    var consistency: String {
        loggedDays == 0 ? "–" : "\(Int((Double(completeDays) / Double(loggedDays) * 100).rounded()))%"
    }

    @MainActor
    init(model: AppModel, year: Int, kind: YearCalendarView.Kind) {
        let prefix = "\(year)-"
        var levels: [String: (fraction: Double, complete: Bool)] = [:]
        var total = 0
        switch kind {
        case .salah:
            var prayed: [String: Int] = [:]
            var logged: [String: Int] = [:]
            for (key, record) in model.records where key.hasPrefix(prefix) {
                let day = String(key.prefix(10))
                if record.status.countsAsPrayed { prayed[day, default: 0] += 1 }
                if record.status.keepsStreak { logged[day, default: 0] += 1 }
            }
            for day in Set(prayed.keys).union(logged.keys) {
                levels[day] = (fraction: Double(prayed[day] ?? 0) / 5, complete: (logged[day] ?? 0) >= 5)
            }
            total = prayed.values.reduce(0, +)
        case .quran:
            for (day, entry) in QuranProgress.allDays() where day.hasPrefix(prefix) && entry.count > 0 {
                let goal = max(entry.goal, 1)
                levels[day] = (fraction: min(Double(entry.count) / Double(goal), 1), complete: entry.isComplete)
                total += entry.count
            }
        }
        self.levels = levels
        self.total = total
        loggedDays = levels.count
        completeDays = levels.values.filter(\.complete).count
        // Longest run of consecutive complete days within the year.
        let calendar = Calendar(identifier: .gregorian)
        var best = 0, run = 0
        var cursor = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? .now
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        while calendar.component(.year, from: cursor) == year {
            if levels[formatter.string(from: cursor)]?.complete == true { run += 1; best = max(best, run) } else { run = 0 }
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor.addingTimeInterval(86_400)
        }
        bestStreak = best
    }
}

/// One month of small day squares.
private struct MiniMonth: View {
    let year: Int
    let month: Int
    let data: YearData
    let onTap: (Date) -> Void

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    var body: some View {
        let calendar = Calendar.current
        let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? .now
        let count = calendar.range(of: .day, in: .month, for: first)?.count ?? 30
        let leading = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        let days = (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: first) }
        let complete = days.filter { data.levels[Self.formatter.string(from: $0)]?.complete == true }.count

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(first.formatted(.dateTime.month(.abbreviated)))
                    .font(.subheadline.weight(.bold))
                Spacer()
                if complete > 0 {
                    Text("\(complete)")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(Palette.highlight)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 7), spacing: 3) {
                ForEach(0..<leading, id: \.self) { _ in Color.clear.aspectRatio(1, contentMode: .fit) }
                ForEach(days, id: \.self) { day in
                    let level = data.levels[Self.formatter.string(from: day)]
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(color(level, future: day > .now))
                        .aspectRatio(1, contentMode: .fit)
                        .overlay {
                            if calendar.isDateInToday(day) {
                                RoundedRectangle(cornerRadius: 2.5).strokeBorder(.white, lineWidth: 1)
                            }
                        }
                        .onTapGesture { if day <= .now { onTap(day) } }
                }
            }
        }
        .foregroundStyle(.white)
        .padding(12)
        .surface(cornerRadius: 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(first.formatted(.dateTime.month(.wide).year())): \(complete) complete days")
    }

    private func color(_ level: (fraction: Double, complete: Bool)?, future: Bool) -> Color {
        guard let level else { return Color.white.opacity(future ? 0.03 : 0.08) }
        if level.complete { return Palette.highlight }
        return level.fraction == 0 ? Color.white.opacity(0.12) : Palette.accent.opacity(0.25 + level.fraction * 0.75)
    }
}
