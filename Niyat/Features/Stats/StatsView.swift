import Charts
import SwiftUI

/// The Stats tab: Salah and Qur'an habits in one place.
struct StatsView: View {
    enum Section: String, CaseIterable, Identifiable {
        case salah = "Salah", quran = "Qur'an"
        var id: String { rawValue }
    }

    @State private var section: Section = .salah

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Section", selection: $section.animation(.smooth)) {
                        ForEach(Section.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    switch section {
                    case .salah: SalahStatsSection()
                    case .quran: QuranStatsSection()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .niyatBackground()
            .navigationTitle("Stats")
            .haptic(.selection, trigger: section)
        }
    }
}

/// Qur'an statistics: today, the week, all time, streaks and the reward estimate.
struct QuranStatsSection: View {
    @State private var goal = QuranGoalModel.shared
    @State private var showMethod = false

    private struct DayPoint: Identifiable {
        let day: Date
        let ayat: Int
        let complete: Bool
        var id: Date { day }
    }

    var body: some View {
        let week = QuranProgress.totals(lastDays: 7)
        let month = QuranProgress.totals(lastDays: 30)
        let allTime = QuranProgress.allTime()
        let days = QuranProgress.allDays()
        let calendar = Calendar.current
        let points: [DayPoint] = (0..<14).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: .now)) else { return nil }
            let entry = days[QuranProgress.dayKey(for: day)]
            return DayPoint(day: day, ayat: entry?.count ?? 0, complete: entry?.isComplete ?? false)
        }

        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                StatTile(value: goal.goal.map { "\(goal.today.count)/\($0)" } ?? "\(goal.today.count)",
                         label: "Ayat today", color: Palette.accent)
                StatTile(value: "\(goal.streak)", label: "Day streak", color: Palette.highlight)
                StatTile(value: "\(QuranProgress.longestStreak(days: days))", label: "Longest", color: Palette.highlight)
            }
            .appearAnimation(0)

            HStack(spacing: 10) {
                StatTile(value: "\(week.ayat)", label: "This week", color: Palette.accent)
                StatTile(value: "\(allTime.ayat)", label: "All time", color: Palette.accent)
                StatTile(value: "\(month.completedDays)/30", label: "Goal days", color: Palette.highlight)
            }
            .appearAnimation(1)

            VStack(alignment: .leading, spacing: 10) {
                Text("Last 14 days").sectionLabelStyle()
                Chart(points) { point in
                    BarMark(x: .value("Day", point.day, unit: .day), y: .value("Ayat", point.ayat))
                        .foregroundStyle(point.complete ? Palette.highlight : Palette.accent)
                        .cornerRadius(4)
                    if let target = goal.goal {
                        RuleMark(y: .value("Goal", target))
                            .foregroundStyle(.white.opacity(0.35))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                        AxisValueLabel(format: .dateTime.day())
                    }
                }
                .frame(height: 160)
                Text("Gold bars are days you reached your goal. The dashed line is your current goal.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(18)
            .surface(cornerRadius: 26)
            .appearAnimation(2)

            rewardCard(week: week.letters, allTime: allTime.letters)
                .appearAnimation(3)
        }
        .onAppear { goal.refresh() }
        .sheet(isPresented: $showMethod) { RewardMethodSheet() }
    }

    private func rewardCard(week: Int, allTime: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Estimated recitation reward").sectionLabelStyle()
                Spacer()
                Button { showMethod = true } label: {
                    Image(systemName: "info.circle")
                }
                .accessibilityLabel("How this is estimated")
            }
            HStack(alignment: .firstTextBaseline, spacing: 20) {
                VStack(alignment: .leading, spacing: 2) {
                    Text((week * 10).formatted())
                        .font(.display(26, weight: .heavy))
                        .foregroundStyle(Palette.highlight)
                    Text("this week").font(.caption).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text((allTime * 10).formatted())
                        .font(.display(26, weight: .heavy))
                        .foregroundStyle(Palette.highlight)
                    Text("all time").font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("An estimate based on the 10×-per-letter hadith (Tirmidhi 2910): \((week).formatted()) letters read this week × 10. Only Allah knows the true reward.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .glassPanel(cornerRadius: 26, tint: Palette.glow.opacity(0.3))
    }
}

/// Explains exactly how the reward estimate is worked out.
private struct RewardMethodSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("The narration")
                        .font(.headline)
                    Text("Abdullah ibn Mas'ud reported that the Prophet ﷺ said that whoever recites a letter from the Book of Allah receives a good deed, and a good deed is multiplied ten times. He said: I do not say that Alif-Lam-Mim is one letter; rather Alif is a letter, Lam is a letter and Mim is a letter.")
                    Link("Read it on Sunnah.com (Jami' at-Tirmidhi 2910)",
                         destination: URL(string: "https://sunnah.com/tirmidhi:2910")!)

                    Text("How Niyat estimates it")
                        .font(.headline)
                        .padding(.top, 6)
                    VStack(alignment: .leading, spacing: 8) {
                        bullet("Only verses you've actually read count: a verse must stay on screen for a few seconds, and each verse counts once per day.")
                        bullet("Letters are counted in the verified Arabic text you're reading, in the script and riwayah you've chosen.")
                        bullet("Letters are the written Arabic letters (including hamza and alif wasla). Harakat, the small \"dagger\" alif, small waw/ya, tatweel and waqf marks are not letters and aren't counted.")
                        bullet("The Bismillah counts where it is a verse (Al-Fatiha 1:1), not when shown as a surah header.")
                        bullet("Estimate = letters × 10.")
                    }
                    Text("This is only an encouragement. Scholars count letters in different ways, the riwayat differ slightly, and no app can know the reward Allah gives. That is with Allah alone.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                }
                .padding(20)
            }
            .navigationTitle("About the estimate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            EightPointStar().fill(Palette.highlight).frame(width: 8, height: 8).padding(.top, 5)
            Text(text)
        }
        .font(.subheadline)
    }
}
