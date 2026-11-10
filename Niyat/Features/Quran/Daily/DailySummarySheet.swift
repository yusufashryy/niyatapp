import SwiftUI

/// After "Done": Today / Week / All. A hero (goal ring, the week's bars, or
/// the all-time star) with the headline, then hasanat, ayat, time and pages,
/// and where the ribbon is. Exactly as tall as what it shows.
struct DailySummarySheet: View {
    /// Ayat counted in this sitting.
    let countedNow: Int
    @Environment(\.dismiss) private var dismiss
    @State private var goal = QuranGoalModel.shared
    @State private var store = QuranStore.shared
    @State private var period = ReadingPeriod.today
    @State private var height: CGFloat = 560
    @State private var showMethod = false

    var body: some View {
        let totals = QuranProgress.totals(days: period.days)
        VStack(spacing: 16) {
            Picker("Period", selection: $period.animation(.smooth)) {
                ForEach(ReadingPeriod.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            hero(ayat: totals.ayat)
            tiles(totals)
            ribbonRow

            Button { dismiss() } label: {
                Text("Close").font(.headline).frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.glassProminent)
            .tint(Palette.control)
            .padding(.top, 2)
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
        .presentationBackground {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                LinearGradient(colors: [Palette.glow.opacity(0.35), .clear], startPoint: .top, endPoint: .center)
            }
        }
        .sheet(isPresented: $showMethod) { RewardMethodSheet() }
        .haptic(.selection, trigger: period)
    }

    // MARK: Hero

    private func hero(ayat: Int) -> some View {
        HStack(spacing: 18) {
            Group {
                switch period {
                case .today: GoalRing(count: goal.today.count, target: goal.goal, complete: goal.today.isComplete)
                case .week: WeekBars(goal: goal.goal)
                case .all: AllTimeStar()
                }
            }
            .frame(width: 104, height: 104)
            .transition(.scale(scale: 0.85).combined(with: .opacity))
            .id(period)

            VStack(alignment: .leading, spacing: 6) {
                Text(caption)
                    .sectionLabelStyle()
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(ayat)")
                        .font(.display(40, weight: .heavy))
                        .contentTransition(.numericText(value: Double(ayat)))
                    Text(ayat == 1 ? "ayah" : "ayat")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(2)
                Label("\(goal.streak)-day streak", systemImage: "flame.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(goal.streak > 0 ? Palette.highlight : .secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Palette.highlight.opacity(goal.streak > 0 ? 0.14 : 0.06), in: .capsule)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .glassPanel(cornerRadius: 26, tint: Palette.glow.opacity(0.25))
        .accessibilityElement(children: .combine)
    }

    private var caption: String {
        switch period {
        case .today: "Today"
        case .week: "Last 7 days"
        case .all: "Since you started"
        }
    }

    /// Today: this sitting and the goal. Week: goal days. All: best streak.
    private var detail: String {
        switch period {
        case .today:
            let sitting = countedNow == 0 ? nil : "+\(countedNow) just now"
            guard let target = goal.goal else { return sitting ?? "Keep going" }
            let left = goal.today.isComplete ? "Goal done" : "\(max(target - goal.today.count, 0)) to go"
            return [sitting, left].compactMap { $0 }.joined(separator: " · ")
        case .week:
            return "Goal met \(QuranProgress.totals(lastDays: 7).completedDays) of 7 days"
        case .all:
            return "Best streak \(QuranProgress.longestStreak()) days"
        }
    }

    // MARK: Tiles

    private func tiles(_ totals: QuranTotals) -> some View {
        let pages = ReadingStats.pagesCompleted(read: totals.verses, pages: PageIndex.shared.pages(store))
        let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        return LazyVGrid(columns: columns, spacing: 10) {
            Button { showMethod = true } label: {
                ReadingStatTile(value: ReadingStats.compact(totals.hasanat), label: "Hasanat", icon: "heart.fill", tint: .pink,
                         hint: "info.circle")
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("\(ReadingStats.compact(totals.hasanat)) hasanat, an estimate")
            .accessibilityHint("Explains how the estimate is worked out")
            ReadingStatTile(value: "\(totals.ayat)", label: "Ayat", icon: "text.alignright", tint: Palette.accent)
            ReadingStatTile(value: ReadingStats.duration(totals.seconds), label: "Time", icon: "clock.fill", tint: .orange)
            ReadingStatTile(value: "\(pages)", label: pages == 1 ? "Page" : "Pages", icon: "book.pages.fill", tint: .teal)
        }
    }

    // MARK: Ribbon

    @ViewBuilder
    private var ribbonRow: some View {
        if let ribbon = store.ribbon {
            HStack(spacing: 12) {
                RibbonMark(color: Color(QuranTextStyle.ribbonRed), starColor: .white)
                    .frame(width: 14, height: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Next time").font(.caption).foregroundStyle(.secondary)
                    Text("\(store.surah(ribbon.surah)?.transliteration ?? "Surah \(ribbon.surah)") \(ribbon.surah):\(ribbon.verse)")
                        .font(.subheadline.weight(.semibold))
                }
                Spacer()
                if let name = store.surah(ribbon.surah)?.name {
                    Text(name)
                        .font(.calligraphy(size: 20))
                        .foregroundStyle(Palette.highlight)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .surface(cornerRadius: 18)
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Pieces

/// One number: a tinted icon, the value, its label.
private struct ReadingStatTile: View {
    let value: String
    let label: String
    let icon: String
    let tint: Color
    var hint: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.16), in: .circle)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.display(22, weight: .heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                HStack(spacing: 3) {
                    Text(label)
                    if let hint { Image(systemName: hint).imageScale(.small) }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(LinearGradient(colors: [tint.opacity(0.14), .white.opacity(0.03)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .accessibilityElement(children: .combine)
    }
}

/// Today: progress towards the daily goal.
private struct GoalRing: View {
    let count: Int
    let target: Int?
    let complete: Bool
    @State private var shown = 0.0

    private var progress: Double {
        guard let target, target > 0 else { return 0 }
        return min(Double(count) / Double(target), 1)
    }

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.1), lineWidth: 10)
            Circle()
                .trim(from: 0, to: shown)
                .stroke(AngularGradient(colors: [Palette.accent, Palette.highlight, Palette.accent], center: .center),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if complete {
                Image(systemName: "checkmark")
                    .font(.title.weight(.bold))
                    .foregroundStyle(Palette.highlight)
            } else {
                VStack(spacing: 0) {
                    Text("\(Int(progress * 100))%").font(.headline.monospacedDigit())
                    Text("of goal").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(5)
        .onAppear { withAnimation(.smooth(duration: 0.8)) { shown = progress } }
        .onChange(of: progress) { _, new in withAnimation(.smooth) { shown = new } }
    }
}

/// Week: one bar a day, gold on days the goal was met.
private struct WeekBars: View {
    let goal: Int?

    private struct Day: Identifiable {
        let id: Int
        let letter: String
        let ayat: Int
        let complete: Bool
        let isToday: Bool
    }

    private static let dayLetter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEEE"
        return formatter
    }()

    private var days: [Day] {
        let all = QuranProgress.allDays()
        let calendar = Calendar.current
        let formatter = Self.dayLetter
        return (0..<7).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: .now) else { return nil }
            let entry = all[QuranProgress.dayKey(for: date)]
            return Day(id: offset, letter: formatter.string(from: date), ayat: entry?.count ?? 0,
                       complete: entry?.isComplete ?? false, isToday: offset == 0)
        }
    }

    var body: some View {
        let days = days
        let top = max(days.map(\.ayat).max() ?? 0, goal ?? 0, 1)
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(days) { day in
                VStack(spacing: 5) {
                    GeometryReader { geo in
                        VStack {
                            Spacer(minLength: 0)
                            Capsule()
                                .fill(day.complete ? Palette.highlight : Palette.accent.opacity(day.ayat > 0 ? 0.8 : 0.2))
                                .frame(height: max(geo.size.height * CGFloat(day.ayat) / CGFloat(top), 4))
                        }
                    }
                    Text(day.letter)
                        .font(.system(size: 10, weight: day.isToday ? .bold : .medium))
                        .foregroundStyle(day.isToday ? .white : .secondary)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// All time: Niyat's eight-point star.
private struct AllTimeStar: View {
    @State private var turned = false

    var body: some View {
        ZStack {
            EightPointStar()
                .fill(LinearGradient(colors: [Palette.highlight.opacity(0.35), Palette.accent.opacity(0.15)],
                                     startPoint: .top, endPoint: .bottom))
            EightPointStar()
                .stroke(Palette.highlight, lineWidth: 1.5)
            Image(systemName: "book.closed.fill")
                .font(.title2)
                .foregroundStyle(Palette.highlight)
        }
        .rotationEffect(.degrees(turned ? 0 : -22.5))
        .onAppear { withAnimation(.smooth(duration: 0.9)) { turned = true } }
        .accessibilityHidden(true)
    }
}

/// Each mushaf page's ayat as "surah:verse", worked out once.
@MainActor
private final class PageIndex {
    static let shared = PageIndex()
    private var cached: [[String]]?

    func pages(_ store: QuranStore) -> [[String]] {
        if let cached { return cached }
        guard !store.pageStarts.isEmpty else { return [] }
        let pages = (1...store.pageStarts.count).map { page in
            store.verses(onPage: page).map { "\($0.hafsReference.surah):\($0.hafsReference.verse)" }
        }
        cached = pages
        return pages
    }
}
